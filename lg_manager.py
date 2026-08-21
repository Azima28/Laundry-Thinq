import os
import json
import asyncio
import threading
import time
from datetime import datetime
import requests
import uuid
import base64
from wideq.core_async import ClientAsync
from wideq.factory import get_lge_device
from config import MONITORING_INTERVAL
import database
from sse_manager import broadcast, latest_state

def get_message_id():
    return base64.urlsafe_b64encode(uuid.uuid4().bytes).decode('ascii').rstrip('=')

def get_pat_headers(pat, country):
    return {
        "Authorization": f"Bearer {pat}",
        "x-message-id": get_message_id(),
        "x-country": country,
        "x-client-id": "laundry-app-desktop-client",
        "x-api-key": "v6GFvkweNo7DK7yD3ylIZ9w52aKBU0eJ7wLXkSR3",
    }


def _get_customer_name(target_name):
    try:
        import machine_manager
        info = machine_manager.get_customer_info(target_name)
        if info and info.get("name"):
            return info.get("name")
    except Exception:
        pass
    return None


import sys

def get_base_path():
    import sys
    # Jika di-bundle sebagai executable (Nuitka / PyInstaller)
    # Nuitka onefile membongkar payload ke folder temp, sys.executable menunjuk ke folder temp tersebut.
    # Namun sys.argv[0] tetap menunjuk ke path asli dari executable yang dijalankan.
    if len(sys.argv) > 0 and sys.argv[0]:
        argv_lower = sys.argv[0].lower()
        if not (argv_lower.endswith('.py') or argv_lower.endswith('.pyw')):
            return os.path.dirname(os.path.abspath(sys.argv[0]))
    return os.path.dirname(os.path.abspath(__file__))

CONFIG_JSON_PATH = os.path.join(get_base_path(), "config.json")

# Dynamic device list - auto-populated from LG ThinQ
discovered_devices = []
discovered_devices_lock = threading.Lock()
pat_devices_cache = None

# Completion tracker - stores state transitions to log only once per cycle
# Format: { "machine_name": { "last_log": timestamp, "was_completed": bool } }
completion_tracker = {}
completion_tracker_lock = threading.Lock()
COMPLETION_DEDUPE_SECONDS = 300  # 5 minutes

# Smart polling tracking
# Format: { "machine_name": next_poll_timestamp }
per_machine_next_poll = {}
per_machine_next_poll_lock = threading.Lock()

def set_next_poll_time(entity_id, delay_seconds):
    """Set the next poll time for a machine."""
    with per_machine_next_poll_lock:
        per_machine_next_poll[entity_id] = time.time() + delay_seconds
        print(f"[SmartPoll] Force next poll for {entity_id} in {delay_seconds}s")

# ThinQ degradation / auto-bypass tracking
consecutive_failures = 0
MAX_FAILURES_BEFORE_DEGRADED = 3
thinq_degraded = False

def register_success():
    global consecutive_failures, thinq_degraded
    consecutive_failures = 0
    thinq_degraded = False

def register_failure():
    global consecutive_failures, thinq_degraded
    consecutive_failures += 1
    if consecutive_failures >= MAX_FAILURES_BEFORE_DEGRADED:
        if not thinq_degraded:
            print(f"[LG] ThinQ connection degraded! Reached {consecutive_failures} failures.")
        thinq_degraded = True

def auto_register_machines(devices_info):
    """Automatically register discovered ThinQ devices in sqlite database if not already present."""
    import sqlite3
    from datetime import datetime
    try:
        conn = sqlite3.connect("laundry.db")
        cursor = conn.cursor()
        
        # Ensure machines table exists
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='machines'")
        if not cursor.fetchone():
            conn.close()
            return

        # Fetch existing machines to check duplicates
        cursor.execute("SELECT url FROM machines")
        existing_urls = {row[0] for row in cursor.fetchall()}
        
        has_new = False
        for dev in devices_info:
            target_name = dev.name.replace(' ', '_')
            if target_name not in existing_urls:
                display_name = dev.name
                # Auto-detect category
                dev_lower = dev.name.lower()
                key = 'cuci'
                if any(x in dev_lower for x in ['dryer', 'pengering', 'dry', 'drying', 'pengeringan']):
                    key = 'pengering'
                
                created_at = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
                
                cursor.execute(
                    "INSERT INTO machines (name, url, key, created_at) VALUES (?, ?, ?, ?)",
                    (display_name, target_name, key, created_at)
                )
                print(f"[LG] Auto-registered new machine in DB: {display_name} ({target_name}, type: {key})")
                has_new = True
                
        if has_new:
            conn.commit()
            
    except Exception as e:
        print(f"[LG] Error auto-registering machines: {e}")
    finally:
        try:
            conn.close()
        except:
            pass

def get_discovered_devices():
    """Return list of discovered LG ThinQ device names."""
    with discovered_devices_lock:
        return list(discovered_devices)

def get_manual_dryers():
    """Return list of manual dryer names from config."""
    config = load_lg_config()
    return list(config.get("dryer_triggers", {}).keys())

def load_triggers():
    """Load machine triggers from config.json (ThinQ machines)."""
    config = load_lg_config()
    return config.get("machine_triggers", {})

def load_dryer_triggers():
    """Load dryer triggers from config.json (Manual machines)."""
    config = load_lg_config()
    return config.get("dryer_triggers", {})

def get_trigger_url(device_name):
    """Get trigger URL for a device (checks both ThinQ and Manual triggers)."""
    # Check manual dryers first
    dryers = load_dryer_triggers()
    if device_name in dryers:
        url = dryers.get(device_name, "")
        return url if url else None

    # Then check ThinQ machines
    triggers = load_triggers()
    url = triggers.get(device_name, "")
    return url if url else None

def save_triggers(triggers):
    """Save machine triggers to config.json."""
    config = load_lg_config()
    config["machine_triggers"] = triggers
    return save_lg_config(config)

def sync_triggers(devices):
    """Sync config.json triggers with discovered devices. Add new devices with empty URLs."""
    triggers = load_triggers()
    updated = False
    for device in devices:
        if device not in triggers:
            triggers[device] = ""
            updated = True
    if updated:
        save_triggers(triggers)
        print(f"[LG] config.json triggers updated with new devices")
    return triggers

def load_lg_config():
    import config
    cfg = config.get_config()
    if not cfg:
        return {"country": "ID", "language": "id-ID", "refresh_token": None}
    return cfg

def save_lg_config(config_dict):
    import config
    return config.save_config(config_dict)

def reload_devices_from_db():
    """Memuat ulang daftar perangkat LG ThinQ dari database lokal machines."""
    global discovered_devices
    try:
        machines_data = database.get_all_machines()
        lg_devs = []
        for m in machines_data:
            url = m.get("url")
            # Jika mesin adalah mesin ThinQ LG (bukan manual "-"), simpan nama target
            if url and url != "-":
                lg_devs.append(url)
        with discovered_devices_lock:
            discovered_devices = lg_devs
        print(f"[LG] Reloaded {len(lg_devs)} ThinQ devices from database: {lg_devs}")
    except Exception as e:
        print(f"[LG] Error reloading devices from DB: {e}")

def discover_thinq_devices(force=False):
    """Mengambil daftar perangkat ThinQ langsung dari LG API (on-demand)."""
    global pat_devices_cache, discovered_devices
    config = load_lg_config()
    pat_token = config.get("pat_token")
    country = config.get("country", "ID")
    if not pat_token:
        print("[LG PAT] discover_thinq_devices: No PAT token in config")
        return []
        
    if not pat_devices_cache or force:
        try:
            print("[LG PAT] Scanning devices from ThinQ API...")
            headers = get_pat_headers(pat_token, country)
            r_route = "https://api-kic.lgthinq.com"
            try:
                route_headers = {
                    "x-message-id": get_message_id(),
                    "x-country": country,
                    "x-service-phase": "OP",
                    "x-api-key": "v6GFvkweNo7DK7yD3ylIZ9w52aKBU0eJ7wLXkSR3",
                }
                r_r = requests.get(f"{r_route}/route", headers=route_headers, timeout=5)
                if r_r.status_code == 200:
                    r_route = r_r.json().get("response", {}).get("apiServer", r_route)
            except Exception as re:
                print(f"[LG PAT] Route scan warning: {re}")
                
            r_devs = requests.get(f"{r_route}/devices", headers=headers, timeout=10)
            if r_devs.status_code == 200:
                devs_data = r_devs.json().get("response", [])
                
                class PatDeviceInfo:
                    def __init__(self, dev_dict):
                        self.id = dev_dict.get("deviceId")
                        dev_info = dev_dict.get("deviceInfo", {})
                        self.name = dev_info.get("alias") or dev_info.get("modelName") or "LG_Device"
                        self.deviceType = dev_info.get("deviceType")
                        
                pat_devices_cache = [PatDeviceInfo(d) for d in devs_data]
                auto_register_machines(pat_devices_cache)
                register_success()
                
                with discovered_devices_lock:
                    discovered_devices = [d.name.replace(' ', '_') for d in pat_devices_cache]
                sync_triggers(discovered_devices)
            else:
                print(f"[LG PAT] Scan failed with code {r_devs.status_code}: {r_devs.text}")
        except Exception as e:
            print(f"[LG PAT] Exception during scan: {e}")
            
    res = []
    if pat_devices_cache:
        for d in pat_devices_cache:
            res.append({
                "deviceId": d.id,
                "alias": d.name,
                "deviceType": d.deviceType
            })
    return res

def _get_fallback_remaining_time(target_name):
    try:
        import machine_manager
        with machine_manager.machine_status_lock:
            end_time = machine_manager.machine_status.get(target_name)
        if end_time:
            from datetime import datetime
            rem = (end_time - datetime.now()).total_seconds()
            if rem > 0:
                m = int(rem) // 60
                s = int(rem) % 60
                return f"{m}:{s:02d}", rem
            else:
                return "0:00", rem
        else:
            # Fallback to database active timer record if memory status was not populated
            import database
            db_timer = database.get_active_timer(target_name)
            if db_timer:
                last_remain = db_timer.get("last_remain_seconds")
                if last_remain is not None and last_remain > 0:
                    from datetime import datetime, timedelta
                    now = datetime.now()
                    new_end = now + timedelta(seconds=last_remain)
                    with machine_manager.machine_status_lock:
                        machine_manager.machine_status[target_name] = new_end
                    m = int(last_remain) // 60
                    s = int(last_remain) % 60
                    return f"{m}:{s:02d}", last_remain
    except Exception as e:
        print(f"[Fallback] Error in _get_fallback_remaining_time for {target_name}: {e}")
    return None, 0

def _update_running_machine_fallback(target_name, status_ready, cust_name):
    if status_ready != "ready" or (cust_name and cust_name not in ("", "-", "None", "null")):
        is_running_state = False
        try:
            import machine_manager
            with machine_manager.state_transitions_lock:
                tracker = machine_manager.state_transitions.get(target_name, {})
                is_running_state = tracker.get("wa_start_sent", False)
        except Exception:
            pass

        # Also check if database indicates active run
        if not is_running_state:
            try:
                import database
                db_t = database.get_active_timer(target_name)
                if db_t and (db_t.get("is_running") or db_t.get("customer_name")):
                    is_running_state = True
            except Exception:
                pass

        if is_running_state:
            fb_time, fb_sec = _get_fallback_remaining_time(target_name)
            if fb_time:
                output = f"{target_name}|Running|Running (Offline)|{fb_time}|-|-|0|{cust_name}"
                latest_state[target_name] = output
                broadcast(output)

                # Update database checkpoint
                try:
                    import database
                    database.update_active_timer_checkpoint(
                        target_name,
                        remain_seconds=fb_sec,
                        run_state="Running (Offline)",
                        is_running=1
                    )
                except Exception:
                    pass

                if fb_sec <= 0:
                    print(f"[Fallback] Backup timer expired for {target_name} while offline, triggering completion.")
                    try:
                        import machine_manager
                        machine_manager.on_thinq_state_change(target_name, "Completed", "0:00", is_completed=True)
                    except Exception as e:
                        print(f"[Fallback] Error triggering completion for {target_name}: {e}")
                return True
    return False

def _check_all_running_machines_fallback():
    try:
        import machine_manager
        with machine_manager.machine_status_lock:
            active_machines = list(machine_manager.machine_status.keys())

        for target_name in active_machines:
            existing = latest_state.get(target_name, "")
            parts = existing.split("|") if existing else []
            run_st = parts[2] if len(parts) > 2 else ""

            # If the machine is ALREADY reporting live online sensor data from LG ThinQ, DO NOT overwrite with fallback!
            if len(parts) >= 6 and run_st in ("Rinsing", "Spinning", "Washing", "Drying", "Running", "Completed", "Idle") and "Offline" not in run_st:
                continue

            is_running_state = False
            try:
                with machine_manager.state_transitions_lock:
                    tracker = machine_manager.state_transitions.get(target_name, {})
                    is_running_state = tracker.get("wa_start_sent", False)
            except Exception:
                pass

            if is_running_state:
                cust_name = _get_customer_name(target_name) or "-"
                _update_running_machine_fallback(target_name, "unready", cust_name)
    except Exception as e:
        print(f"[Fallback] Error in global fallback check: {e}")

async def lg_polling_loop():
    """Background loop to fetch machine status from LG ThinQ (official PAT API only)."""
    global pat_devices_cache, discovered_devices
    print("[LG] Starting Polling Loop...")
    
    # Load devices list from DB initially
    reload_devices_from_db()
    
    # Cache for official PAT devices list to avoid rate limits
    PAT_DEVICES_FETCH_INTERVAL = 86400  # refresh list once every 24 hours (fallback)
    first_run = True
    
    while True:
        if not first_run:
            await asyncio.sleep(MONITORING_INTERVAL)
        first_run = False
        
        config = load_lg_config()
        
        # --- AUTO BYPASS WHEN DEGRADED ---
        global thinq_degraded
        if thinq_degraded:
            if not hasattr(lg_polling_loop, "degraded_retry_counter"):
                lg_polling_loop.degraded_retry_counter = 0
            lg_polling_loop.degraded_retry_counter += 1
            
            # Check every 2 minutes (120 seconds) based on MONITORING_INTERVAL (default 5s)
            cycles_to_wait = max(1, 120 // MONITORING_INTERVAL)
            
            if lg_polling_loop.degraded_retry_counter % cycles_to_wait != 1:
                # Behave like bypass/simulation mode
                try:
                    db_m = database.get_all_machines()
                    devices_to_poll = [m.get("name").replace(' ', '_') for m in db_m]
                    if not devices_to_poll:
                        devices_to_poll = ["Mesin_Cuci_1", "Mesin_Cuci_2", "Mesin_Cuci_3", "Mesin_Cuci_4", "Mesin_Cuci_5"]
                except Exception:
                    devices_to_poll = ["Mesin_Cuci_1", "Mesin_Cuci_2", "Mesin_Cuci_3", "Mesin_Cuci_4", "Mesin_Cuci_5"]
                sync_triggers(devices_to_poll)
                
                for target_name in devices_to_poll:
                    try:
                        import machine_manager
                        status_ready = machine_manager.get_machine_status(target_name)
                    except Exception:
                        status_ready = "ready"
                        
                    cust_name = _get_customer_name(target_name) or "-"
                    if status_ready == "ready":
                        output = f"{target_name}|Ready|Idle|--:--|-|-|0|{cust_name}"
                        latest_state[target_name] = output
                        broadcast(output)
                    else:
                        _update_running_machine_fallback(target_name, status_ready, cust_name)
                continue

        pat_token = config.get("pat_token")
        if not pat_token:
            print("[LG] No PAT token found in config.json. Please configure PAT Token in Settings.")
            await asyncio.sleep(30)
            continue
            
        # --- OFFICIAL REST PAT API FLOW ---
        try:
            country = config.get("country", "ID")
            headers = get_pat_headers(pat_token, country)
            
            # Fetch route to resolve server URL
            api_server = "https://api-kic.lgthinq.com"
            try:
                route_headers = {
                    "x-message-id": get_message_id(),
                    "x-country": country,
                    "x-service-phase": "OP",
                    "x-api-key": "v6GFvkweNo7DK7yD3ylIZ9w52aKBU0eJ7wLXkSR3",
                }
                r_route = requests.get(f"{api_server}/route", headers=route_headers, timeout=5)
                if r_route.status_code == 200:
                    api_server = r_route.json().get("response", {}).get("apiServer", api_server)
            except Exception as e:
                print(f"[LG PAT] Route API warning: {e}")
            
            # Load or Scan devices on start/request
            if not pat_devices_cache:
                discover_thinq_devices(force=True)
            
            # Filter ThinQ devices based on database
            try:
                db_m = database.get_all_machines()
                db_active_urls = {m.get("url") for m in db_m if m.get("url") and m.get("url") != "-"}
                devices_info = [d for d in (pat_devices_cache or []) if d.name.replace(' ', '_') in db_active_urls]
            except Exception as db_err:
                print(f"[LG PAT] Error filtering registered machines: {db_err}")
                devices_info = pat_devices_cache or []
            
            def poll_pat_device(dev):
                global consecutive_failures, thinq_degraded
                target_name = dev.name.replace(' ', '_')
                current_time = time.time()
                
                # 1. Check if the machine is active / has active timer
                try:
                    import machine_manager
                    status_ready = machine_manager.get_machine_status(target_name)
                except Exception:
                    status_ready = "ready"
                    
                # 2. Smart adaptive polling: check if it's time to poll
                with per_machine_next_poll_lock:
                    next_poll = per_machine_next_poll.get(target_name, 0)
                if current_time < next_poll:
                    return
                    
                try:
                    req_headers = headers.copy()
                    req_headers["x-message-id"] = get_message_id()
                    r_state = requests.get(f"{api_server}/devices/{dev.id}/state", headers=req_headers, timeout=10)
                    if r_state.status_code == 200:
                        # Reset connectivity failures on successful API call
                        register_success()
                        
                        state_resp = r_state.json().get("response", [{}])
                        state_data = state_resp[0] if isinstance(state_resp, list) and state_resp else {}
                        
                        # Parse state and parameters
                        run_state_obj = state_data.get("runState", {})
                        current_state_val = run_state_obj.get("currentState") if isinstance(run_state_obj, dict) else str(run_state_obj)
                        if not current_state_val:
                                current_state_val = "unknown"
                        
                        raw_state_str = str(current_state_val).upper()
                        if raw_state_str in ["POWER_OFF", "POWEROFF", "OFF", "STANDBY"]:
                            state = "Ready"
                            run_state = "Idle"
                        elif raw_state_str in ["RUNNING", "RUN", "WASHING", "RINSING", "SPINNING", "DRYING"]:
                            state = "Running"
                            run_state = current_state_val.capitalize()
                        elif raw_state_str in ["END", "COMPLETE", "COMPLETED"]:
                            state = "Ready"
                            run_state = "Completed"
                        else:
                            state = "Running"
                            run_state = current_state_val.capitalize()
                            
                        timer_data = state_data.get("timer", {})
                        washer_data = state_data.get("washer", {})
                        dryer_data = state_data.get("dryer", {})

                        rem_h = 0
                        rem_m = 0
                        if isinstance(timer_data, dict):
                            rem_h = int(timer_data.get("remainHour", 0) or timer_data.get("remainTimeHour", 0) or 0)
                            rem_m = int(timer_data.get("remainMinute", 0) or timer_data.get("remainTimeMinute", 0) or 0)

                        if not (rem_h or rem_m):
                            if isinstance(washer_data, dict):
                                rem_h = int(washer_data.get("remainHour", 0) or washer_data.get("remainTimeHour", 0) or 0)
                                rem_m = int(washer_data.get("remainMinute", 0) or washer_data.get("remainTimeMinute", 0) or 0)
                            elif isinstance(dryer_data, dict):
                                rem_h = int(dryer_data.get("remainHour", 0) or dryer_data.get("remainTimeHour", 0) or 0)
                                rem_m = int(dryer_data.get("remainMinute", 0) or dryer_data.get("remainTimeMinute", 0) or 0)

                        if not (rem_h or rem_m):
                            rem_h = int(state_data.get("remainHour", 0) or 0)
                            rem_m = int(state_data.get("remainMinute", 0) or state_data.get("remainTime", 0) or 0)

                        remain_time = f"{rem_h}:{rem_m:02d}" if (rem_h or rem_m) else "--:--"
                        
                        if (remain_time == "--:--" or not remain_time) and state == "Running":
                            fb_time, fb_sec = _get_fallback_remaining_time(target_name)
                            if fb_time:
                                remain_time = fb_time
                        
                        current_course = "-"
                        error_msg = "-"
                        
                        is_run_completed = raw_state_str in ["END", "COMPLETE", "COMPLETED"]
                        completed_str = "1" if is_run_completed else "0"
                        
                        with completion_tracker_lock:
                            tracker = completion_tracker.get(target_name, {"last_log": 0, "was_completed": False})
                            now = time.time()
                            if is_run_completed and not tracker.get("was_completed", False):
                                if (now - tracker.get("last_log", 0)) > COMPLETION_DEDUPE_SECONDS:
                                    database.log_machine_completion(target_name)
                                    tracker["last_log"] = now
                                    broadcast(f"ML_LOG|{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}|{target_name}")
                            tracker["was_completed"] = is_run_completed
                            completion_tracker[target_name] = tracker
                            
                        output = f"{target_name}|{state}|{run_state}|{remain_time}|{current_course}|{error_msg}|{completed_str}"
                        
                        cust_name = _get_customer_name(target_name)
                        if cust_name:
                            output = f"{output}|{cust_name}"
                        else:
                            output = f"{output}|-"
                            
                        latest_state[target_name] = output
                        broadcast(output)
                        
                        try:
                            import machine_manager
                            machine_manager.on_thinq_state_change(target_name, run_state, remain_time, is_run_completed)
                        except Exception as wa_err:
                            print(f"[LG PAT] WA notification error for {target_name}: {wa_err}")
                            
                        # Calculate and set the next smart polling time
                        remain_minutes = 999
                        try:
                            parts = remain_time.split(":")
                            if len(parts) >= 2:
                                remain_minutes = int(parts[0]) * 60 + int(parts[1])
                        except:
                            pass
                            
                        # Load dynamic intervals from configuration
                        cfg_idle = int(config.get("interval_idle", 300))
                        cfg_booking = int(config.get("interval_booking", 180))
                        cfg_run_high = int(config.get("interval_running_high", 300))
                        cfg_run_low = int(config.get("interval_running_low", 120))
                        
                        if status_ready == "ready":
                            interval = cfg_idle  # Idle state
                        else:
                            is_running = run_state not in ("Idle", "-", "", "Ready")
                            if not is_running:
                                interval = 15  # Active order but machine idle -> poll every 15s to catch when user presses START!
                            else:
                                if "Offline" in run_state:
                                    interval = 15  # Fallback offline mode -> check every 15s to see if machine comes online!
                                elif remain_minutes > 8:
                                    interval = cfg_run_high  # Running > 8 minutes
                                elif remain_minutes > 4:
                                    interval = cfg_run_low  # Running 4-8 minutes
                                else:
                                    interval = cfg_run_high  # Running <= 4 minutes

                        with per_machine_next_poll_lock:
                            per_machine_next_poll[target_name] = current_time + interval
                        print(f"[SmartPoll PAT] Next poll for {target_name} in {interval}s (state={run_state}, remain={remain_time})")
                    else:
                        cust_name = _get_customer_name(target_name) or "-"
                        if not _update_running_machine_fallback(target_name, status_ready, cust_name):
                            latest_state[target_name] = f"{target_name}|OFFLINE|-|-|-|-|-"
                            broadcast(latest_state[target_name])
                        with per_machine_next_poll_lock:
                            per_machine_next_poll[target_name] = current_time + 15  # Retry offline machine in 15s
                        register_failure()
                except Exception as ex:
                    print(f"[LG PAT] Error polling {target_name}: {ex}")
                    register_failure()
                    cust_name = _get_customer_name(target_name) or "-"
                    if not _update_running_machine_fallback(target_name, status_ready, cust_name):
                        latest_state[target_name] = f"{target_name}|ERROR|-|-|-|-|-"
                        broadcast(latest_state[target_name])
                    with per_machine_next_poll_lock:
                        per_machine_next_poll[target_name] = current_time + 15  # Retry offline machine in 15s
            
            loop = asyncio.get_running_loop()
            tasks = [loop.run_in_executor(None, poll_pat_device, d) for d in devices_info]
            await asyncio.gather(*tasks)
            
            # Global fallback check for any other running machines that were not updated
            _check_all_running_machines_fallback()
            
        except Exception as e:
            now_str = datetime.now().strftime('%H:%M:%S')
            print(f"[LG PAT] [{now_str}] Global poll error: {e}")
            register_failure()
            try:
                _check_all_running_machines_fallback()
            except Exception:
                pass
            
        await asyncio.sleep(MONITORING_INTERVAL)

async def get_machine_attributes(target_name):
    """Fetch raw attributes for a specific machine name via PAT."""
    config = load_lg_config()
    pat_token = config.get("pat_token")
    if not pat_token:
        return {"error": "No credentials found in config.json"}

    try:
        api_server = "https://api-kic.lgthinq.com"
        headers = get_pat_headers(pat_token, config.get("country", "ID"))
        
        # Fetch route to resolve server URL
        try:
            route_headers = {
                "x-message-id": get_message_id(),
                "x-country": config.get("country", "ID"),
                "x-service-phase": "OP",
                "x-api-key": "v6GFvkweNo7DK7yD3ylIZ9w52aKBU0eJ7wLXkSR3",
            }
            r_route = requests.get(f"{api_server}/route", headers=route_headers, timeout=5)
            if r_route.status_code == 200:
                api_server = r_route.json().get("response", {}).get("apiServer", api_server)
        except:
            pass

        r_devs = requests.get(f"{api_server}/devices", headers=headers, timeout=10)
        if r_devs.status_code == 200:
            devs = r_devs.json().get("response", [])
            for d in devs:
                dev_info = d.get("deviceInfo", {})
                alias = dev_info.get("alias") or dev_info.get("modelName") or ""
                if alias.replace(' ', '_') == target_name:
                    dev_id = d.get("deviceId")
                    r_state = requests.get(f"{api_server}/devices/{dev_id}/state", headers=headers, timeout=10)
                    if r_state.status_code == 200:
                        state_resp = r_state.json().get("response", [{}])
                        state_data = state_resp[0] if isinstance(state_resp, list) and state_resp else {}
                        
                        run_state_obj = state_data.get("runState", {})
                        current_state_val = run_state_obj.get("currentState") if isinstance(run_state_obj, dict) else str(run_state_obj)
                        raw_state_str = str(current_state_val).upper()
                        is_run_completed = raw_state_str in ["END", "COMPLETE", "COMPLETED"]
                        
                        return {
                            "device_id": dev_id,
                            "name": alias,
                            "type": dev_info.get("deviceType"),
                            "is_online": True,
                            "is_run_completed": is_run_completed,
                            "features": state_data,
                            "raw_data": state_data,
                            "last_update": datetime.now().strftime("%H:%M:%S")
                        }
                    return {"error": f"Failed to fetch state ({r_state.status_code})"}
            return {"error": f"Device '{target_name}' not found in your LG account"}
        return {"error": f"Failed to fetch devices list ({r_devs.status_code})"}
    except Exception as e:
        return {"error": str(e)}

def start_lg_thread():
    def run_loop():
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        loop.run_until_complete(lg_polling_loop())
        loop.close()
    threading.Thread(target=run_loop, daemon=True).start()
