import time
import threading
from datetime import datetime, timedelta
from config import (
    PERINTAH_HIDUP, PERINTAH_MATI
)
import database
from sse_manager import broadcast
import lg_manager
import wa_bridge
import tuya_manager

# Status tracking for each machine (unready/ready/occupied)
# Format: { "entity_id": end_datetime_object }
# For occupied (bypass): end_datetime_object = None (no timer)
machine_status = {}
machine_status_lock = threading.Lock()

# Customer info tracking for active machines
# Format: { "entity_id": { "name": "Agus", "phone": "08123..." } }
customer_info = {}
customer_info_lock = threading.Lock()

# Track active countdown threads to avoid duplicates
active_countdown_threads = {}

# Track state transitions for WA notification triggers
# Format: { "entity_id": { "last_state": "Idle", "wa_start_sent": False, "wa_completion_sent": False } }
state_transitions = {}
state_transitions_lock = threading.Lock()


def get_machine_status(entity_id):
    """Get machine status.
    Returns: 'ready' (no active booking timer) or 'unready' (booking timer active)
    """
    with machine_status_lock:
        end_time = machine_status.get(entity_id)
        if end_time and datetime.now() < end_time:
            return "unready"
    return "ready"


def has_pending_items_in_orders(phone, name):
    """Check if the customer has any pending/unstarted laundry/drying runs in active orders."""
    try:
        import sqlite3
        import wa_bridge
        from config import DB_PATH
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        
        # Normalize phone
        normalized_phone = wa_bridge._normalize_phone(phone) if phone else None
        
        # Get all orders that are not completed
        cursor.execute("SELECT id, customer_phone, customer_name FROM orders WHERE LOWER(status) != 'completed'")
        orders = cursor.fetchall()
        
        matching_order_ids = []
        for oid, ophone, oname in orders:
            dec_ophone = database.decrypt_val(ophone)
            dec_oname = database.decrypt_val(oname)
            # Match by phone if phone is provided
            if dec_ophone and normalized_phone:
                if wa_bridge._normalize_phone(dec_ophone) == normalized_phone:
                    matching_order_ids.append(oid)
                    continue
            # Match by name if phone is not available
            if dec_oname and name and not normalized_phone:
                n1 = dec_oname.strip().lower()
                n2 = name.strip().lower()
                if n1 == n2 and n2 not in ("pelanggan", "guest", "", "-"):
                    matching_order_ids.append(oid)
                    
        if not matching_order_ids:
            conn.close()
            return False
            
        total_remaining = 0
        for order_id in matching_order_ids:
            # Count total laundry runs in this order
            cursor.execute("""
                SELECT oi.item_name, oi.quantity, t.machine_type
                FROM order_items oi
                LEFT JOIN transactions t ON oi.item_id = t.id
                WHERE oi.order_id = ?
            """, (order_id,))
            items = cursor.fetchall()
            
            total_qty = 0
            for item_name, quantity, machine_type in items:
                # If transaction explicitly has a machine type, use it
                if machine_type in ('cuci', 'pengering'):
                    total_qty += quantity
                else:
                    # Fallback to string matching on item_name
                    n = item_name.lower()
                    if any(x in n for x in ('cuci', 'wash', 'kering', 'pengering', 'dry', 'jemur', 'basah')):
                        total_qty += quantity
                    
            if total_qty == 0:
                continue
                
            # Count successful usages in history
            cursor.execute("SELECT COUNT(*) FROM machine_usage_history WHERE order_id = ? AND status = 'Success'", (order_id,))
            used_qty = cursor.fetchone()[0]
            
            remaining = total_qty - used_qty
            if remaining > 0:
                total_remaining += remaining
                
        conn.close()
        return total_remaining > 0
    except Exception as e:
        print(f"[DB] Error checking pending items in orders: {e}")
        return False


def is_last_machine_for_customer(entity_id):
    """Check if this is the last active machine for the customer.
    
    Returns True if there are no OTHER machines for this customer that are
    currently running or booking (i.e. not completed, idle, ready, or offline),
    and there are no other pending laundry/drying runs in active orders.
    """
    info = get_customer_info(entity_id)
    if not info:
        return True
    
    name = info.get("name", "").strip().lower()
    phone = info.get("phone")
    
    # If customer still has pending laundry items in queue/active orders,
    # it is not the last machine run for this customer.
    if has_pending_items_in_orders(phone, name):
        return False
        
    normalized_phone = wa_bridge._normalize_phone(phone) if phone else None
    
    with customer_info_lock:
        for eid, cinfo in customer_info.items():
            if eid != entity_id:
                match = False
                p = cinfo.get("phone")
                if p and normalized_phone:
                    if wa_bridge._normalize_phone(p) == normalized_phone:
                        match = True
                else:
                    n = cinfo.get("name", "").strip().lower()
                    if n and name and n == name and name not in ("pelanggan", "guest", "", "-"):
                        match = True
                        
                if match:
                    # Check if this other machine is booking (timer active) or ThinQ is running
                    is_booking = get_machine_status(eid) == "unready"
                    
                    existing_state = lg_manager.latest_state.get(eid, "")
                    parts = existing_state.split("|")
                    state_val = parts[1].upper() if len(parts) > 1 else ""
                    run_state_val = parts[2].lower() if len(parts) > 2 else ""
                    
                    is_running = state_val in ("RUNNING", "RUN") or (
                        run_state_val not in ("", "-", "idle", "ready", "completed", "unknown")
                    )
                    
                    if is_booking or is_running:
                        return False
    return True


def get_other_active_machines(entity_id):
    """Return a list of display names of other active machines for this customer."""
    info = get_customer_info(entity_id)
    if not info:
        return []
        
    name = info.get("name", "").strip().lower()
    phone = info.get("phone")
    
    normalized_phone = wa_bridge._normalize_phone(phone) if phone else None
    
    other_machines = []
    with customer_info_lock:
        for eid, cinfo in customer_info.items():
            if eid != entity_id:
                # 1. Match by phone if both have phone numbers
                p = cinfo.get("phone")
                if p and normalized_phone:
                    if wa_bridge._normalize_phone(p) == normalized_phone:
                        display_name = eid.replace("_", " ")
                        other_machines.append(display_name)
                        continue
                # 2. Match by customer name if phone is not available, avoiding generic words
                n = cinfo.get("name", "").strip().lower()
                if n and name and n == name and name not in ("pelanggan", "guest", "", "-"):
                    display_name = eid.replace("_", " ")
                    other_machines.append(display_name)
    return other_machines


def is_wa_completion_sent(entity_id):
    """Check if WA completion notification was already sent for this machine."""
    with state_transitions_lock:
        tracker = state_transitions.get(entity_id, {})
        return tracker.get("wa_completion_sent", False)


def get_remaining_seconds(entity_id):
    """Get remaining seconds for a machine timer."""
    with machine_status_lock:
        end_time = machine_status.get(entity_id)
        if end_time:
            remaining = (end_time - datetime.now()).total_seconds()
            return max(0, int(remaining))
    return 0


def get_customer_info(entity_id):
    """Get customer info for an active machine."""
    with customer_info_lock:
        return customer_info.get(entity_id, {})


def set_customer_info(entity_id, name, phone):
    """Set customer info for an active machine."""
    with customer_info_lock:
        customer_info[entity_id] = {"name": name, "phone": phone}


def clear_customer_info(entity_id):
    """Clear customer info when machine becomes ready."""
    with customer_info_lock:
        if entity_id in customer_info:
            del customer_info[entity_id]


def set_machine_unready(entity_id, duration_seconds=300, source='customer',
                        customer_name=None, customer_phone=None):
    """Set machine to unready status (monitoring booking window).

    In v2 monitoring-only mode, this only:
    1. Sets the booking window timer (default 5 min)
    2. Saves customer info for WA notifications
    3. Schedules auto-release when timer expires
    No relay/ESP commands are sent.
    """
    end_time = datetime.now() + timedelta(seconds=duration_seconds)
    duration_minutes = duration_seconds // 60

    with machine_status_lock:
        machine_status[entity_id] = end_time

    # Save customer info
    if customer_name:
        set_customer_info(entity_id, customer_name, customer_phone)

    # Save to database for persistence (include customer info and initial checkpoint)
    database.save_active_timer(
        entity_id, end_time, source=source, duration_minutes=duration_minutes,
        customer_name=customer_name, customer_phone=customer_phone,
        last_remain_seconds=duration_seconds, is_running=0, run_state="Idle",
        wa_start_sent=0, wa_completion_sent=0
    )

    # Initialize state transition tracker for WA notifications
    with state_transitions_lock:
        state_transitions[entity_id] = {
            "last_state": "Idle",
            "wa_start_sent": False,
            "wa_completion_sent": False
        }

    def _timer_release():
        """Handle expiration of booking window timer."""
        remaining = (end_time - datetime.now()).total_seconds()
        if remaining > 0:
            time.sleep(remaining)

        # Check if the machine is actually running (ThinQ detected RUNNING or offline running)
        # If running, don't release — let completion handle it
        existing_state = lg_manager.latest_state.get(entity_id, "")
        if "Running" in existing_state:
            print(f"[Timer] Machine {entity_id} is running ({existing_state.split('|')[2]}), keeping active")
            return

        # Booking window expired without starting -> expire booking (preserving customer)
        _expire_booking(entity_id)

    # Start background timer
    threading.Thread(target=_timer_release, daemon=True).start()


def _expire_booking(entity_id):
    """Handle expiration of booking window without starting (status goes READY, keeping customer)."""
    print(f"[Timer] Booking window expired for {entity_id}, setting READY (keeping customer)")
    
    # Clean up memory status so get_machine_status() returns 'ready'
    with machine_status_lock:
        if entity_id in machine_status:
            del machine_status[entity_id]
            
    # Broadcast READY/IDLE state (preserving customer name)
    info = get_customer_info(entity_id)
    cust_name = info.get("name") or "-"
    off_state = f"{entity_id}|Ready|Idle|--:--|-|-|0|{cust_name}"
    lg_manager.latest_state[entity_id] = off_state
    broadcast(off_state)


def _release_machine(entity_id):
    """Release a machine back to Ready status (internal)."""
    # Log the release
    database.log_usage(entity_id, "RELEASE", source='system')
    now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    broadcast(f"LOG|{now_str}|{entity_id}|RELEASE|{entity_id}|system")
    
    # Broadcast Ready state
    off_state = f"{entity_id}|Ready|Idle|--:--|-|-|0|-"
    lg_manager.latest_state[entity_id] = off_state
    broadcast(off_state)
    
    # Remove from database and memory
    database.remove_active_timer(entity_id)
    with machine_status_lock:
        if entity_id in machine_status:
            del machine_status[entity_id]
    
    # Clear customer info and state transitions
    clear_customer_info(entity_id)
    with state_transitions_lock:
        if entity_id in state_transitions:
            del state_transitions[entity_id]


def on_thinq_state_change(entity_id, new_run_state, remain_time_str, is_completed):
    """Called by lg_manager when ThinQ polling detects a state change.
    
    This is the core v2 logic for triggering WA notifications:
    - Idle -> Running: Send "cucian mulai" WA
    - remain ≤ 4 min OR is_completed: Send "cucian selesai" WA, mark as WA_SENT
    
    After WA completion is sent, machine stays in WA_SENT state (not auto-released).
    Kasir must manually replace/release via the UI.
    
    Args:
        entity_id: Machine name (e.g. "Mesin_Cuci_2")
        new_run_state: Current run state from ThinQ (e.g. "Idle", "Washing", "Rinsing")
        remain_time_str: Remaining time string (e.g. "1:15")
        is_completed: Whether the washing cycle is complete
    """
    with state_transitions_lock:
        tracker = state_transitions.get(entity_id, {})
        last_state = tracker.get("last_state", "Idle")
        wa_start_sent = tracker.get("wa_start_sent", False)
        wa_completion_sent = tracker.get("wa_completion_sent", False)
    
    # Get customer info for this machine
    info = get_customer_info(entity_id)
    customer_name = info.get("name")
    customer_phone = info.get("phone")
    
    # Transition: Idle -> Running (machine started washing)
    is_running = new_run_state not in ("Idle", "-", "")
    if is_running and not wa_start_sent and customer_phone:
        print(f"[WA] Detected machine {entity_id} started running, sending WA to {customer_phone}")
        
        # Send WA "cucian mulai" in background thread to not block polling
        threading.Thread(
            target=wa_bridge.send_wa_cucian_mulai,
            args=(customer_phone, customer_name or "Pelanggan", entity_id, remain_time_str),
            daemon=True
        ).start()
        
        with state_transitions_lock:
            if entity_id in state_transitions:
                state_transitions[entity_id]["wa_start_sent"] = True
                state_transitions[entity_id]["last_state"] = new_run_state
        
        # Set target end time to exactly 40 minutes from now as a backup run timer
        end_time = datetime.now() + timedelta(minutes=40)
        with machine_status_lock:
            machine_status[entity_id] = end_time

        # Also persist the 40-minute backup timer to database
        try:
            db_timer = database.get_active_timer(entity_id)
            source = db_timer['source'] if db_timer and 'source' in db_timer else 'customer'
        except Exception:
            source = 'customer'

        database.save_active_timer(
            entity_id, end_time, source=source, duration_minutes=40,
            customer_name=customer_name, customer_phone=customer_phone
        )
    
    # Check remaining time for early WA trigger (≤4 minutes)
    remain_minutes = 999
    try:
        parts = remain_time_str.split(":")
        if len(parts) >= 2:
            remain_minutes = int(parts[0]) * 60 + int(parts[1])
    except:
        pass
    
    should_send_completion = False
    if not wa_completion_sent:
        is_last = is_last_machine_for_customer(entity_id)
        if is_completed:
            should_send_completion = is_last
        elif is_running and remain_minutes <= 4 and remain_minutes > 0:
            should_send_completion = is_last
            if is_last:
                print(f"[WA] Machine {entity_id} has <=4 min remaining ({remain_time_str}), sending early completion WA (last machine)")
    
    if should_send_completion and customer_phone:
        print(f"[WA] Sending completion WA for {entity_id} to {customer_phone}")
        
        # Send WA "cucian selesai" in background thread
        threading.Thread(
            target=wa_bridge.send_wa_cucian_selesai,
            args=(customer_phone, customer_name or "Pelanggan", entity_id),
            daemon=True
        ).start()
        
        # Mark as WA sent — do NOT release machine
        # Machine stays with customer name + "wa_sent" badge until kasir replaces
        with state_transitions_lock:
            if entity_id in state_transitions:
                state_transitions[entity_id]["wa_completion_sent"] = True
                
    # Update SSE display state if ThinQ completed
    if is_completed:
        # Clear the active timer from memory so status becomes 'ready'
        with machine_status_lock:
            if entity_id in machine_status:
                del machine_status[entity_id]
        
        output = f"{entity_id}|Ready|Completed|--:--|-|-|1"
        existing = lg_manager.latest_state.get(entity_id, "")
        existing_parts = existing.split("|") if existing else []
        if len(existing_parts) > 7 and existing_parts[7] != "-" and existing_parts[7] != "":
            output = f"{output}|{existing_parts[7]}"
        lg_manager.latest_state[entity_id] = output
        broadcast(output)
    
    # Update last state
    with state_transitions_lock:
        if entity_id in state_transitions:
            state_transitions[entity_id]["last_state"] = new_run_state


def _start_countdown_broadcast(entity_id, end_time, duration_minutes=5):
    """Start a countdown broadcast thread for a machine.

    For LG machines: Adds control time to existing LG state as position 7.
    For manual-only machines: Creates full state with control time.
    Periodically checkpoints remaining seconds and timestamp to SQLite database.
    """
    # Check if there's already an active countdown for this entity
    if entity_id in active_countdown_threads:
        return

    # Determine if this is an LG ThinQ machine (by checking discovered devices list)
    is_lg_machine = entity_id in lg_manager.get_discovered_devices()

    def _update_countdown(ent, end_dt, dur_min, is_lg):
        active_countdown_threads[ent] = True
        is_tuya = tuya_manager.resolve_tuya_device(ent) is not None
        try:
            while True:
                if is_tuya:
                    status = tuya_manager.get_dryer_status(ent)
                    if status.get("success"):
                        if not status.get("switch"):
                            print(f"[Tuya] Dryer {ent} switch detected as OFF. Stopping countdown.")
                            break
                        remaining = status.get("countdown", 0)
                        if remaining <= 0:
                            print(f"[Tuya] Dryer {ent} countdown reached 0. Stopping countdown.")
                            break
                    else:
                        # Fallback to local clock calculation if API fails
                        remaining = (end_dt - datetime.now()).total_seconds()
                        if remaining <= 0:
                            break
                else:
                    remaining = (end_dt - datetime.now()).total_seconds()
                    if remaining <= 0:
                        break

                m = int(remaining) // 60
                s = int(remaining) % 60
                control_time = f"{m}:{s:02d}"

                # Periodic checkpointing to SQLite database on every tick!
                try:
                    curr_st = lg_manager.latest_state.get(ent, "")
                    parts = curr_st.split("|") if curr_st else []
                    curr_run_st = parts[2] if len(parts) > 2 else "Idle"
                    is_run = 1 if (curr_run_st not in ("Idle", "-", "", "Ready") or "Offline" in curr_run_st) else 0
                    database.update_active_timer_checkpoint(
                        ent,
                        remain_seconds=int(remaining),
                        run_state=curr_run_st,
                        is_running=is_run
                    )
                except Exception as db_err:
                    pass

                import lg_manager
                config = lg_manager.load_lg_config()
                is_degraded_or_bypass = lg_manager.thinq_degraded or config.get("monitoring_mode") == "bypass"

                cust_info = get_customer_info(ent)
                cust_name_str = cust_info.get("name") if cust_info else "-"

                with state_transitions_lock:
                    tracker = state_transitions.get(ent, {})
                    is_running_flag = tracker.get("wa_start_sent", False) or (tracker.get("last_state") == "Running (Offline)")

                if is_lg and not is_degraded_or_bypass:
                    # Check if LG machine is currently reporting live sensor data from ThinQ cloud
                    existing_state = lg_manager.latest_state.get(ent, "")
                    existing_parts = existing_state.split("|") if existing_state else []
                    run_st_val = existing_parts[2] if len(existing_parts) > 2 else ""

                    is_live_cloud_sensor = (
                        len(existing_parts) >= 6 and
                        run_st_val in ("Rinsing", "Washing", "Spinning", "Drying", "Running", "Completed", "Idle") and
                        "Offline" not in run_st_val and
                        "Menit" not in run_st_val
                    )

                    if is_live_cloud_sensor:
                        # Machine is online and actively monitored by LG Cloud API!
                        # Do NOT overwrite with fallback - let LG polling broadcast live sensor data!
                        while len(existing_parts) < 7:
                            existing_parts.append("-")
                        if len(existing_parts) == 7:
                            existing_parts.append(control_time)
                        else:
                            existing_parts[7] = control_time
                        state = "|".join(existing_parts)
                        lg_manager.latest_state[ent] = state
                    elif is_running_flag:
                        # Machine is offline / cloud degraded but has active customer run -> show fallback timer
                        state = f"{ent}|Running|Running (Offline)|{control_time}|-|-|0|{cust_name_str}"
                        lg_manager.latest_state[ent] = state
                        broadcast(state)
                    else:
                        state = f"{ent}|Ready|Idle|--:--|-|-|0|{control_time}"
                        lg_manager.latest_state[ent] = state
                        broadcast(state)
                else:
                    # Manual/Tuya machine or degraded/bypass LG machine - broadcast directly
                    if is_running_flag:
                        siklus_label = f"{dur_min} Menit"
                        state = f"{ent}|Ready|{siklus_label}|{control_time}|-|-|0|{cust_name_str}"
                    else:
                        state = f"{ent}|Ready|Idle|--:--|-|-|0|{cust_name_str}"
                    lg_manager.latest_state[ent] = state
                    broadcast(state)

                time.sleep(5)  # Update and checkpoint every 5 seconds

            # Final OFF state - clear control time but preserve customer name
            cust_info = get_customer_info(ent)
            cust_name = cust_info.get("name") if cust_info else None
            cust_name_str = cust_name if cust_name else "-"

            if is_lg:
                existing_state = lg_manager.latest_state.get(ent, "")
                existing_parts = existing_state.split("|") if existing_state else []
                if len(existing_parts) > 7:
                    existing_parts[7] = cust_name_str
                    state = "|".join(existing_parts)
                else:
                    state = f"{ent}|Ready|Idle|--:--|-|-|0|{cust_name_str}"
            else:
                state = f"{ent}|Ready|Idle|--:--|-|-|0|{cust_name_str}"

            lg_manager.latest_state[ent] = state
            broadcast(state)

            if is_tuya:
                # Tuya device completion - release and notify
                print(f"[Tuya] Autoclosing dryer {ent} and triggering notifications.")
                finish_and_notify(ent, send_wa=True)
            else:
                # Clean up memory status for manual machines
                with machine_status_lock:
                    if ent in machine_status:
                        del machine_status[ent]
        finally:
            if ent in active_countdown_threads:
                del active_countdown_threads[ent]

    threading.Thread(target=_update_countdown, args=(entity_id, end_time, duration_minutes, is_lg_machine), daemon=True).start()


def resume_active_timers():
    """Resume active timers and restore customer info from database after server restart/relog.

    Supports dual-mode recovery:
    1. Real-time Clock Mode (when PC clock is valid & synchronized with CMOS/NTP)
    2. Fallback State Mode (when PC clock is inaccurate / CMOS battery dead / clock reset)
    """
    timers = database.get_all_active_timers()
    now = datetime.now()
    resumed_count = 0

    for timer in timers:
        entity_id = timer['entity_id']
        end_time_str = timer.get('end_time')
        started_at_str = timer.get('started_at')
        last_saved_str = timer.get('last_saved_time') or started_at_str
        last_remain_seconds = timer.get('last_remain_seconds')
        source = timer.get('source', 'customer')
        customer_name = timer.get('customer_name')
        customer_phone = timer.get('customer_phone')
        duration_minutes = timer.get('duration_minutes', 40 if ('cuci' in entity_id.lower() or 'wash' in entity_id.lower()) else 45)
        is_running = timer.get('is_running', 0) == 1
        saved_run_state = timer.get('run_state') or ('Running (Offline)' if is_running else 'Idle')
        wa_start_sent = timer.get('wa_start_sent', 0) == 1
        wa_completion_sent = timer.get('wa_completion_sent', 0) == 1

        is_lg_machine = entity_id in lg_manager.get_discovered_devices()

        # Restore customer info (always, even if timer expired, since machine is not released!)
        if customer_name:
            set_customer_info(entity_id, customer_name, customer_phone)

        # Determine if WA completion or start has been sent previously
        if not wa_completion_sent and customer_phone:
            wa_completion_sent = database.has_wa_been_sent(entity_id, "complete", customer_phone)
        if not wa_start_sent and customer_phone:
            wa_start_sent = database.has_wa_been_sent(entity_id, "start", customer_phone)

        with state_transitions_lock:
            state_transitions[entity_id] = {
                "last_state": saved_run_state,
                "wa_start_sent": wa_start_sent or is_running,
                "wa_completion_sent": wa_completion_sent
            }

        # Parse timestamps
        last_saved_dt = None
        if last_saved_str:
            try:
                last_saved_dt = datetime.strptime(last_saved_str, "%Y-%m-%d %H:%M:%S")
            except Exception:
                pass

        end_time_dt = None
        if end_time_str:
            try:
                end_time_dt = datetime.strptime(end_time_str, "%Y-%m-%d %H:%M:%S")
            except Exception:
                pass

        # Fallback if last_remain_seconds is None or invalid
        if last_remain_seconds is None or last_remain_seconds < 0:
            if end_time_dt and last_saved_dt:
                last_remain_seconds = max(0, int((end_time_dt - last_saved_dt).total_seconds()))
            else:
                last_remain_seconds = duration_minutes * 60

        # Check clock validity:
        # Clock is ACCURATE if:
        # 1. now >= last_saved_dt - 60s (clock didn't jump backward)
        # 2. now.year >= 2024 (valid modern year)
        # 3. time difference is within reasonable bounds (< 30 days)
        clock_is_accurate = False
        if last_saved_dt:
            time_diff = (now - last_saved_dt).total_seconds()
            if -60 <= time_diff <= 86400 * 30 and now.year >= 2024:
                clock_is_accurate = True

        if clock_is_accurate:
            # Case 1: RTC / System Clock is accurate
            elapsed = max(0, (now - last_saved_dt).total_seconds())
            effective_remaining = max(0, int(last_remain_seconds - elapsed))
            print(f"[Timer Recovery] Real Clock Accurate: {entity_id} elapsed {int(elapsed)}s since {last_saved_str}. Remaining: {effective_remaining}s")
        else:
            # Case 2: Clock is inaccurate / CMOS dead / clock went backwards
            # Fallback to last recorded state minutes/seconds as requested!
            effective_remaining = int(last_remain_seconds)
            print(f"[Timer Recovery] Clock Inaccurate/Reset detected (now={now.strftime('%Y-%m-%d %H:%M:%S')}, saved={last_saved_str}). Restoring state from last recorded time: {effective_remaining}s ({effective_remaining//60} min)")

        if effective_remaining > 0:
            # Calculate new target end_time based on current runtime reference
            new_end_time = now + timedelta(seconds=effective_remaining)
            with machine_status_lock:
                machine_status[entity_id] = new_end_time

            # Update database checkpoint with new reference
            database.update_active_timer_checkpoint(
                entity_id,
                remain_seconds=effective_remaining,
                run_state=saved_run_state,
                is_running=1 if is_running else 0,
                wa_start_sent=1 if (wa_start_sent or is_running) else 0,
                wa_completion_sent=1 if wa_completion_sent else 0,
                end_time=new_end_time
            )

            m = effective_remaining // 60
            s = effective_remaining % 60
            control_time = f"{m}:{s:02d}"

            cust_name_str = customer_name if customer_name else "-"

            if is_running:
                # If machine was running offline or in wash cycle
                run_state_to_show = "Running (Offline)" if ("Offline" in saved_run_state or "offline" in saved_run_state.lower()) else saved_run_state
                state = f"{entity_id}|Running|{run_state_to_show}|{control_time}|-|-|0|{cust_name_str}"
            else:
                # Booking state
                if is_lg_machine:
                    state = f"{entity_id}|Ready|Idle|--:--|-|-|0|{control_time}"
                else:
                    siklus_label = f"{duration_minutes} Menit"
                    state = f"{entity_id}|Ready|{siklus_label}|{control_time}|-|-|0|{control_time}"

            lg_manager.latest_state[entity_id] = state
            broadcast(state)

            _start_countdown_broadcast(entity_id, new_end_time, duration_minutes)
            resumed_count += 1

            # If it's a booking timer (not running), schedule booking expiration
            if not is_running:
                def _timer_release(ent, end_dt):
                    rem = (end_dt - datetime.now()).total_seconds()
                    if rem > 0:
                        time.sleep(rem)
                    existing_st = lg_manager.latest_state.get(ent, "")
                    if "Running" in existing_st:
                        print(f"[Timer] Machine {ent} is running (ThinQ), keeping active (resumed)")
                        return
                    print(f"[Timer] Booking window expired for {ent} (resumed), setting READY (preserving customer)")
                    _expire_booking(ent)

                threading.Thread(target=_timer_release, args=(entity_id, new_end_time), daemon=True).start()
        else:
            # Timer has expired while system was off
            print(f"[Timer Recovery] Timer expired for {entity_id} while offline. Customer: {customer_name}")
            completed_flag = "1" if wa_completion_sent else "0"
            run_state = "Completed" if is_lg_machine else "Idle"

            cust_name_str = customer_name if customer_name else "-"
            state = f"{entity_id}|Ready|{run_state}|0:00|-|-|{completed_flag}|{cust_name_str}"

            lg_manager.latest_state[entity_id] = state
            broadcast(state)

    print(f"[Timer] Resumed {resumed_count} active timer(s) and restored customer allocations from database")


def start_machine_monitoring(entity_id, customer_name=None, customer_phone=None,
                              source='customer', duration_seconds=300):
    """Start monitoring a machine (v2 monitoring-only, no relay).

    Mode-aware behavior:
    - Bypass mode: Instantly set to OCCUPIED (no timer, no countdown)
    - PAT/WideQ/Hybrid: Traditional booking window with countdown and offline fallback
    """
    print(f"[Monitor] Starting monitoring for {entity_id} (customer={customer_name}, phone={customer_phone}, duration={duration_seconds}s)")

    is_tuya = tuya_manager.resolve_tuya_device(entity_id) is not None
    if is_tuya:
        duration_minutes = duration_seconds // 60
        res = tuya_manager.start_dryer(entity_id, duration_minutes)
        if not res.get("success"):
            print(f"[Tuya] Failed to start smartplug {entity_id}: {res.get('error')}")
            return f"failed_to_start_smartplug: {res.get('error')}", 500

    # Check monitoring mode
    config = lg_manager.load_lg_config()
    monitoring_mode = config.get("monitoring_mode", "hybrid")

    # Log usage (all modes)
    database.log_usage(entity_id, "MONITOR_START", source=source)
    now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    broadcast(f"LOG|{now_str}|{entity_id}|MONITOR_START|{entity_id}|{source}")

    # Determine if machine is offline or manual fallback
    is_lg_machine = entity_id in lg_manager.get_discovered_devices()
    existing_state = lg_manager.latest_state.get(entity_id, "")
    is_currently_offline = (
        not is_lg_machine or
        "OFFLINE" in existing_state or
        "Offline" in existing_state or
        lg_manager.thinq_degraded
    )

    # For offline machines or manual wash, set default duration (40m for cuci, 45m for pengering)
    if is_currently_offline and duration_seconds <= 300:
        if 'cuci' in entity_id.lower() or 'wash' in entity_id.lower():
            duration_seconds = 40 * 60
        elif 'pengering' in entity_id.lower() or 'dry' in entity_id.lower() or 'kering' in entity_id.lower():
            duration_seconds = 45 * 60

    duration_minutes = duration_seconds // 60
    end_time = datetime.now() + timedelta(seconds=duration_seconds)

    # Initialize state tracker for the new transaction
    is_running_now = is_currently_offline and duration_minutes > 5
    run_state_init = "Running (Offline)" if is_running_now else "Idle"

    with state_transitions_lock:
        state_transitions[entity_id] = {
            "last_state": run_state_init,
            "wa_start_sent": True if is_running_now else False,
            "wa_completion_sent": False
        }

    with machine_status_lock:
        machine_status[entity_id] = end_time

    if customer_name:
        set_customer_info(entity_id, customer_name, customer_phone)

    # Save to database with full checkpoint
    database.save_active_timer(
        entity_id, end_time, source=source, duration_minutes=duration_minutes,
        customer_name=customer_name, customer_phone=customer_phone,
        last_remain_seconds=duration_seconds,
        is_running=1 if is_running_now else 0,
        run_state=run_state_init,
        wa_start_sent=1 if is_running_now else 0,
        wa_completion_sent=0
    )

    m = duration_seconds // 60
    s = duration_seconds % 60
    control_time = f"{m}:{s:02d}"

    cust_name_str = customer_name if customer_name else "-"

    if is_running_now:
        state = f"{entity_id}|Running|Running (Offline)|{control_time}|-|-|0|{cust_name_str}"
    else:
        if is_lg_machine:
            state = f"{entity_id}|Ready|Idle|--:--|-|-|0|{control_time}"
        else:
            siklus_label = f"{duration_minutes} Menit"
            state = f"{entity_id}|Ready|{siklus_label}|{control_time}|-|-|0|{cust_name_str}"

    lg_manager.latest_state[entity_id] = state
    broadcast(state)

    # Start countdown broadcast with periodic checkpointing
    _start_countdown_broadcast(entity_id, end_time, duration_minutes)

    # Set smart polling next time (15s for offline machine to auto-detect online, or 180s for booking)
    poll_interval = 15 if is_currently_offline else 180
    lg_manager.set_next_poll_time(entity_id, poll_interval)

    # Send cucian masuk WA notification (in background)
    if customer_phone:
        threading.Thread(
            target=wa_bridge.send_wa_cucian_masuk,
            args=(customer_phone, customer_name or "Pelanggan", entity_id),
            daemon=True
        ).start()

    return "monitoring_started", 200


def stop_machine_monitoring(entity_id, source='admin'):
    """Manually stop monitoring a machine and release it.

    Returns:
        tuple (message, status_code)
    """
    print(f"[Monitor] Stopping monitoring for {entity_id} (source={source})")

    # If Tuya device, turn it off physically
    if tuya_manager.resolve_tuya_device(entity_id) is not None:
        tuya_manager.stop_dryer(entity_id)

    database.log_usage(entity_id, "MONITOR_STOP", source=source)
    now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    broadcast(f"LOG|{now_str}|{entity_id}|MONITOR_STOP|{entity_id}|{source}")

    _release_machine(entity_id)

    return "monitoring_stopped", 200


def finish_and_notify(entity_id, send_wa=True, wa_message=None):
    """Manually stop monitoring and release a machine (Selesaikan).

    Sends completion WA to customer if send_wa is True and phone number is available.

    Returns:
        tuple (message, status_code)
    """
    info = get_customer_info(entity_id)
    customer_name = info.get("name", "Pelanggan")
    customer_phone = info.get("phone")

    print(f"[Monitor] Finishing machine {entity_id} for {customer_name} (send_wa={send_wa}, phone={customer_phone})")

    if send_wa and customer_phone:
        if wa_message:
            threading.Thread(
                target=wa_bridge.send_wa_message,
                args=(customer_phone, wa_message),
                daemon=True
            ).start()
        else:
            threading.Thread(
                target=wa_bridge.send_wa_cucian_selesai,
                args=(customer_phone, customer_name, entity_id),
                daemon=True
            ).start()

    database.log_usage(entity_id, "MONITOR_STOP", source='kasir')
    now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    broadcast(f"LOG|{now_str}|{entity_id}|MONITOR_STOP|{entity_id}|kasir")

    _release_machine(entity_id)
    return "monitoring_stopped", 200


def replace_customer(entity_id, new_customer_name, new_customer_phone=None,
                     send_wa_to_previous=False, wa_message=None):
    """Replace the customer on an occupied/active machine.

    Used when kasir wants to assign a new customer to a machine that still
    has a previous customer.

    Args:
        entity_id: Machine identifier
        new_customer_name: New customer's name
        new_customer_phone: New customer's phone (optional)
        send_wa_to_previous: Whether to send WA to previous customer
        wa_message: Custom WA message (None = use template)

    Returns:
        tuple (message, status_code)
    """
    prev_info = get_customer_info(entity_id)
    prev_name = prev_info.get("name", "")
    prev_phone = prev_info.get("phone", "")

    print(f"[Monitor] Replacing customer on {entity_id}: {prev_name} -> {new_customer_name} (send_wa_prev={send_wa_to_previous}, prev_phone={prev_phone})")

    # Send WA to previous customer if requested
    if send_wa_to_previous and prev_phone:
        if wa_message:
            threading.Thread(
                target=wa_bridge.send_wa_message,
                args=(prev_phone, wa_message),
                daemon=True
            ).start()
        else:
            threading.Thread(
                target=wa_bridge.send_wa_cucian_selesai,
                args=(prev_phone, prev_name or "Pelanggan", entity_id),
                daemon=True
            ).start()

    database.log_usage(entity_id, "CUSTOMER_REPLACE", source='kasir')
    now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    broadcast(f"LOG|{now_str}|{entity_id}|CUSTOMER_REPLACE|{prev_name}->{new_customer_name}|kasir")

    # Release old customer state
    _release_machine(entity_id)

    # Start fresh monitoring for new customer
    return start_machine_monitoring(
        entity_id,
        customer_name=new_customer_name,
        customer_phone=new_customer_phone,
        source='kasir'
    )


def resolve_entity(machine_name):
    """Resolve a machine name to an identifier in discovered devices (LG ThinQ + Manual).
    Handles underscores and case-insensitivity.
    """
    # Normalisasi input: ubah spasi jadi underscore dan lowercase
    clean_input = machine_name.replace(' ', '_').lower().strip()
    
    # Gabungkan semua mesin (LG + Manual) untuk resolusi nama
    all_machines = lg_manager.get_discovered_devices() + lg_manager.get_manual_dryers()
    
    for m in all_machines:
        # Bandingkan dengan versi normalisasi dari daftar devices
        if m.replace(' ', '_').lower().strip() == clean_input:
            return m
            
    # If in bypass/simulation mode, dynamically accept and add the machine!
    try:
        config = lg_manager.load_lg_config()
        if config.get("monitoring_mode") == "bypass":
            with lg_manager.discovered_devices_lock:
                if machine_name not in lg_manager.discovered_devices:
                    lg_manager.discovered_devices.append(machine_name)
            return machine_name
    except Exception as e:
        print(f"[Resolve] Bypass dynamic resolve error: {e}")
        
    return None
