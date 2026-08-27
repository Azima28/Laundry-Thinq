# wa_bridge.py - Bridge antara Python server dan Node.js WhatsApp service
# Mengelola pengiriman pesan WA, antrian offline (outbox), dan template pesan.

import requests
import threading
import time
import json
from datetime import datetime

import database

# Default config (akan di-override dari config.json)
WA_SERVICE_URL = "http://localhost:3000"
WA_MASTER_ENABLED = True
WA_MACHINE_NOTIFICATIONS_ENABLED = True

# WA message templates (default)
WA_TEMPLATES = {
    "cucian_masuk": "Halo Kak {name}, cucian anda sudah masuk ke mesin cuci.",
    "cucian_mulai": "Halo Kak {name}, cucianmu di {mesin} sudah mulai diproses ya. Estimasi selesai sekitar {estimasi} (± jam {jam_selesai}). Kami akan kirim pesan lagi kalau sudah selesai!",
    "cucian_selesai": "Halo Kak {name}, cucianmu sudah selesai! Silakan diambil ya. Terima kasih!",
}

# Lock for thread safety
_outbox_lock = threading.Lock()
_outbox_running = False


def load_wa_config():
    """Load WA configuration from config.json."""
    global WA_SERVICE_URL, WA_TEMPLATES, WA_MASTER_ENABLED, WA_MACHINE_NOTIFICATIONS_ENABLED
    try:
        import lg_manager
        config = lg_manager.load_lg_config()
        WA_SERVICE_URL = config.get("wa_service_url", WA_SERVICE_URL)
        WA_MASTER_ENABLED = config.get("wa_master_enabled", True)
        WA_MACHINE_NOTIFICATIONS_ENABLED = config.get("wa_machine_notifications_enabled", True)
        templates = config.get("wa_templates", {})
        if templates:
            WA_TEMPLATES.update(templates)
    except Exception as e:
        print(f"[WA] Error loading WA config: {e}")


def get_wa_status():
    """Check WhatsApp service connection status."""
    try:
        resp = requests.get(f"{WA_SERVICE_URL}/status", timeout=5)
        if resp.status_code == 200:
            return resp.json()
    except Exception:
        pass
    return {"connected": False, "error": "WA service not reachable"}


def _normalize_phone(phone):
    """Normalize phone number to international format (62xxx)."""
    if not phone:
        return None
    phone = phone.strip().replace("+", "").replace("-", "").replace(" ", "")
    if phone.startswith("0"):
        phone = "62" + phone[1:]
    if not phone.startswith("62"):
        phone = "62" + phone
    return phone


def send_wa_message(phone, message, save_to_outbox=True):
    """Send WhatsApp message via Node.js service.

    If sending fails and save_to_outbox is True, the message is saved
    to the wa_outbox table for later retry.

    Returns:
        dict: {"success": bool, "error": str or None}
    """
    if not WA_MASTER_ENABLED:
        print(f"[WA] WhatsApp master is disabled in settings. Skipping message to {phone}")
        return {"success": True, "skipped": True, "error": None}

    phone = _normalize_phone(phone)
    if not phone:
        return {"success": False, "error": "No phone number provided"}

    if not message or not message.strip():
        print(f"[WA] Skipping empty message to {phone}")
        return {"success": True, "error": None}

    try:
        resp = requests.post(
            f"{WA_SERVICE_URL}/send",
            json={"phone": phone, "message": message},
            timeout=15
        )
        if resp.status_code == 200:
            data = resp.json()
            if data.get("success"):
                print(f"[WA] Message sent to {phone}")
                return {"success": True, "error": None}
            else:
                error = data.get("error", "Unknown error from WA service")
                print(f"[WA] WA service returned error: {error}")
                if save_to_outbox:
                    database.save_wa_outbox(phone, message)
                return {"success": False, "error": error}
        else:
            print(f"[WA] WA service HTTP error: {resp.status_code}")
            if save_to_outbox:
                database.save_wa_outbox(phone, message)
            return {"success": False, "error": f"HTTP {resp.status_code}"}
    except requests.exceptions.ConnectionError:
        print(f"[WA] WA service not reachable, saving to outbox")
        if save_to_outbox:
            database.save_wa_outbox(phone, message)
        return {"success": False, "error": "WA service not reachable"}
    except Exception as e:
        print(f"[WA] Error sending message: {e}")
        if save_to_outbox:
            database.save_wa_outbox(phone, message)
        return {"success": False, "error": str(e)}


def send_wa_cucian_masuk(phone, nama, mesin):
    """Send WA notification: machine cycle has been set/started in dashboard.

    Checks if a notification of this type has already been sent to this phone
    recently (within 1 hour) to avoid spamming customers who have multiple active machines.
    """
    if not phone or not WA_MASTER_ENABLED or not WA_MACHINE_NOTIFICATIONS_ENABLED:
        return {"success": True, "skipped": True}

    # Skip if they have already received a start WA for this session in the last 1 hour
    if database.has_phone_received_event_recently(phone, "cucian_masuk", 3600):
        print(f"[WA] Skipping duplicate 'cucian_masuk' WA for {mesin} -> {phone} (already sent recently)")
        return {"success": True, "skipped": True}

    sequence = database.get_current_wash_sequence(phone, nama)
    if sequence > 1:
        print(f"[WA] Skipping 'cucian_masuk' WA for {mesin} because sequence is {sequence} (> 1)")
        return {"success": True, "skipped": True}

    template = WA_TEMPLATES.get("cucian_masuk", "")
    if not template or not template.strip():
        template = "Halo Kak {name}, cucian anda sudah masuk ke mesin cuci."

    message = template.replace("{name}", nama).replace("{mesin}", mesin.replace("_", " ")).replace("{sequence}", str(sequence))

    result = send_wa_message(phone, message)
    if result and result.get("success"):
        database.log_wa_sent(mesin, "cucian_masuk", phone)
    return result


def send_wa_cucian_mulai(phone, nama, mesin, estimasi_waktu):
    """Send WA notification: washing has started with time estimate.

    Args:
        phone: Customer phone number
        nama: Customer name
        mesin: Machine name (e.g. "Mesin_Cuci_2")
        estimasi_waktu: Estimated time string (e.g. "1:15" for 1 hour 15 min)
    """
    if not phone or not WA_MASTER_ENABLED or not WA_MACHINE_NOTIFICATIONS_ENABLED:
        return {"success": True, "skipped": True}

    sequence = database.get_current_wash_sequence(phone, nama)
    if sequence > 1:
        print(f"[WA] Skipping 'cucian_mulai' WA for {mesin} because sequence is {sequence} (> 1)")
        return {"success": True, "skipped": True}

    # Calculate estimated finish time
    try:
        parts = estimasi_waktu.split(":")
        hours = int(parts[0]) if len(parts) >= 1 else 0
        minutes = int(parts[1]) if len(parts) >= 2 else 0
        total_minutes = hours * 60 + minutes
        finish_time = datetime.now()
        from datetime import timedelta
        finish_time += timedelta(minutes=total_minutes)
        jam_selesai = finish_time.strftime("%H:%M")
    except Exception:
        jam_selesai = "—"

    template = WA_TEMPLATES.get("cucian_mulai", "")
    message = (template
               .replace("{name}", nama)
               .replace("{mesin}", mesin.replace("_", " "))
               .replace("{estimasi}", estimasi_waktu)
               .replace("{jam_selesai}", jam_selesai))

    # Check if we already sent a 'start' notification for this machine recently
    if database.has_wa_been_sent(mesin, "start", phone, cooldown_seconds=300):
        print(f"[WA] Skipping duplicate 'start' WA for {mesin} -> {phone}")
        return

    result = send_wa_message(phone, message)
    if result and result.get("success"):
        database.log_wa_sent(mesin, "start", phone)
    return result


def send_wa_cucian_selesai(phone, nama, mesin):
    """Send WA notification: washing is complete."""
    if not phone or not WA_MASTER_ENABLED or not WA_MACHINE_NOTIFICATIONS_ENABLED:
        return {"success": True, "skipped": True}

    # Check if we already sent a 'complete' notification for this machine recently
    if database.has_wa_been_sent(mesin, "complete", phone, cooldown_seconds=600):
        print(f"[WA] Skipping duplicate 'complete' WA for {mesin} -> {phone}")
        return

    template = WA_TEMPLATES.get("cucian_selesai", "")
    message = (template
               .replace("{name}", nama)
               .replace("{mesin}", mesin.replace("_", " ")))

    result = send_wa_message(phone, message)
    if result and result.get("success"):
        database.log_wa_sent(mesin, "complete", phone)
    return result


def process_outbox():
    """Background thread: process pending WA messages from outbox.
    
    Runs every 30 seconds, attempts to send any pending messages.
    Successfully sent messages are marked as 'sent'.
    """
    global _outbox_running
    if _outbox_running:
        return
    _outbox_running = True

    def _loop():
        global _outbox_running
        print("[WA] Outbox processor started")
        while _outbox_running:
            try:
                pending = database.get_pending_wa_outbox(limit=10)
                if pending:
                    # Check if WA service is reachable first
                    status = get_wa_status()
                    if not status.get("connected"):
                        time.sleep(30)
                        continue

                    for msg in pending:
                        # Check age of the message to prevent sending old/stale messages (e.g. from yesterday)
                        try:
                            created_time = datetime.strptime(msg["created_at"], "%Y-%m-%d %H:%M:%S")
                            age_seconds = (datetime.now() - created_time).total_seconds()
                        except Exception as parse_err:
                            print(f"[WA] Error parsing outbox created_at: {parse_err}")
                            age_seconds = 0

                        if age_seconds > 1800: # 30 minutes threshold
                            print(f"[WA] Discarding expired outbox message {msg['id']} to {msg['phone']} (Created: {msg['created_at']}, Age: {age_seconds:.0f}s)")
                            database.mark_wa_outbox_failed(msg["id"])
                            continue

                        result = send_wa_message(
                            msg["phone"], msg["message"],
                            save_to_outbox=False  # Don't re-queue on failure
                        )
                        if result and result.get("success"):
                            database.mark_wa_outbox_sent(msg["id"])
                        else:
                            database.increment_wa_outbox_retry(msg["id"])
            except Exception as e:
                print(f"[WA] Outbox processor error: {e}")

            time.sleep(30)  # Check every 30 seconds

    threading.Thread(target=_loop, daemon=True).start()


def stop_outbox():
    """Stop the outbox processor thread."""
    global _outbox_running
    _outbox_running = False
