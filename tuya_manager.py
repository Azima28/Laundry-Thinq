import os
import json
import sqlite3
import sys
from datetime import datetime
import tinytuya
import lg_manager

def get_base_path():
    if len(sys.argv) > 0 and sys.argv[0]:
        argv_lower = sys.argv[0].lower()
        if not (argv_lower.endswith('.py') or argv_lower.endswith('.pyw')):
            return os.path.dirname(os.path.abspath(sys.argv[0]))
    return os.path.dirname(os.path.abspath(__file__))

DEVICES_JSON_PATH = os.path.join(get_base_path(), "smartplug_controller", "devices.json")

def load_tuya_credentials():
    """Load Tuya credentials from config.json, with fallback to devices.json."""
    config = lg_manager.load_lg_config()
    
    access_id = config.get("tuya_access_id")
    access_secret = config.get("tuya_access_secret")
    app_uid = config.get("tuya_app_uid")
    endpoint = config.get("tuya_endpoint", "https://openapi.tuyaus.com")
    
    # Fallback to devices.json
    if not (access_id and access_secret and app_uid) and os.path.exists(DEVICES_JSON_PATH):
        try:
            with open(DEVICES_JSON_PATH, "r", encoding="utf-8") as f:
                data = json.load(f)
                creds = data.get("api_credentials", {})
                access_id = access_id or creds.get("access_id")
                access_secret = access_secret or creds.get("access_secret")
                app_uid = app_uid or creds.get("app_uid")
        except Exception as e:
            print(f"[Tuya] Error reading fallback credentials: {e}")
            
    return {
        "access_id": access_id,
        "access_secret": access_secret,
        "app_uid": app_uid,
        "endpoint": endpoint
    }

def load_devices_list():
    """Load devices from devices.json."""
    if os.path.exists(DEVICES_JSON_PATH):
        try:
            with open(DEVICES_JSON_PATH, "r", encoding="utf-8") as f:
                data = json.load(f)
                return data.get("devices", [])
        except Exception as e:
            print(f"[Tuya] Error loading devices list: {e}")
    return []

def get_cz_devices():
    """Get list of Bardi devices filtered by category 'cz' (Smart Plugs)."""
    devices = load_devices_list()
    return [d for d in devices if d.get("category") == "cz"]

def save_tuya_devices_list(creds, devices):
    """Save credentials and devices list to devices.json."""
    try:
        os.makedirs(os.path.dirname(DEVICES_JSON_PATH), exist_ok=True)
        config_data = {
            "api_credentials": {
                "access_id": creds.get("access_id"),
                "access_secret": creds.get("access_secret"),
                "app_uid": creds.get("app_uid")
            },
            "devices": devices
        }
        with open(DEVICES_JSON_PATH, "w", encoding="utf-8") as f:
            json.dump(config_data, f, indent=4, ensure_ascii=False)
        print(f"[Tuya] Devices and credentials saved to {DEVICES_JSON_PATH}")
        return True
    except Exception as e:
        print(f"[Tuya] Error saving devices list: {e}")
        return False

def sync_tuya_keys(access_id, access_secret, app_uid, endpoint="https://openapi.tuyaus.com"):
    """Fetch all devices from Tuya Cloud API and save them locally."""
    print(f"[Tuya] Connecting to Tuya Cloud API (region us)...")
    try:
        c = tinytuya.Cloud(
            apiRegion="us",
            apiKey=access_id,
            apiSecret=access_secret
        )
        res = c.cloudrequest(f"/v1.0/users/{app_uid}/devices")
        if isinstance(res, dict) and res.get("success"):
            devices = res.get("result", [])
            creds = {
                "access_id": access_id,
                "access_secret": access_secret,
                "app_uid": app_uid
            }
            save_tuya_devices_list(creds, devices)
            
            # Save into config.json as well to stay in sync
            config = lg_manager.load_lg_config()
            config["tuya_access_id"] = access_id
            config["tuya_access_secret"] = access_secret
            config["tuya_app_uid"] = app_uid
            config["tuya_endpoint"] = endpoint
            lg_manager.save_lg_config(config)
            
            # Auto-register newly synced plugs
            auto_register_cz_devices()
            
            # Return only category 'cz' devices for client representation
            cz_devs = [d for d in devices if d.get("category") == "cz"]
            return {"success": True, "devices": cz_devs}
        else:
            msg = res.get("msg") if isinstance(res, dict) else "Unknown error"
            return {"success": False, "error": msg}
    except Exception as e:
        print(f"[Tuya] Sync keys failed: {e}")
        return {"success": False, "error": str(e)}

def resolve_tuya_device(entity_id):
    """Find a Tuya device that matches the entity_id (case-insensitive name comparison)."""
    devices = load_devices_list()
    normalized_ent = entity_id.lower().replace("_", " ").strip()
    for dev in devices:
        name = dev.get("name", "")
        if name.lower().replace("_", " ").strip() == normalized_ent:
            return dev
    return None

def get_switch_code(cloud_client, device_id):
    """Detect which function code represents the switch."""
    try:
        res = cloud_client.cloudrequest(f"/v1.0/devices/{device_id}")
        if isinstance(res, dict) and res.get("success"):
            status_list = res["result"].get("status", [])
            codes = [status.get("code") for status in status_list]
            for c in ["switch_1", "switch", "gas_sensor_state"]:
                if c in codes:
                    return c
    except Exception:
        pass
    return "switch_1"

def get_local_outlet(dev):
    """Instantiate a local tinytuya OutletDevice configured for offline LAN socket control."""
    if not dev or not dev.get("id") or not dev.get("local_key"):
        return None
    try:
        ip = dev.get("ip") or dev.get("local_ip")
        version = float(dev.get("version", 3.3))
        d = tinytuya.OutletDevice(
            dev_id=dev["id"],
            address=ip,
            local_key=dev["local_key"],
            version=version
        )
        d.set_socketPersistent(False)
        d.set_socketTimeout(2.0)
        return d
    except Exception as e:
        print(f"[Tuya Local] Error initializing local outlet device: {e}")
        return None

def start_dryer_local(dev, duration_minutes):
    """Priority 1: Attempt to start dryer via local Wi-Fi (Offline TCP LAN)."""
    outlet = get_local_outlet(dev)
    if not outlet:
        return False, "No local key/device configuration"
    try:
        res = outlet.turn_on(switch=1)
        if isinstance(res, dict) and not res.get("Error"):
            print(f"[Tuya Local] Successfully turned ON {dev.get('name')} via Local LAN (0ms offline)")
            return True, None
        return False, res.get("Error", "Local command failed")
    except Exception as e:
        return False, str(e)

def stop_dryer_local(dev):
    """Priority 1: Attempt to stop dryer via local Wi-Fi (Offline TCP LAN)."""
    outlet = get_local_outlet(dev)
    if not outlet:
        return False, "No local key/device configuration"
    try:
        res = outlet.turn_off(switch=1)
        if isinstance(res, dict) and not res.get("Error"):
            print(f"[Tuya Local] Successfully turned OFF {dev.get('name')} via Local LAN (0ms offline)")
            return True, None
        return False, res.get("Error", "Local command failed")
    except Exception as e:
        return False, str(e)

def get_dryer_status_local(dev):
    """Priority 1: Attempt to read status via local Wi-Fi (Offline TCP LAN)."""
    outlet = get_local_outlet(dev)
    if not outlet:
        return None
    try:
        data = outlet.status()
        if isinstance(data, dict) and "dps" in data:
            dps = data["dps"]
            switch_val = bool(dps.get("1") or dps.get("switch_1") or False)
            power_val = float(dps.get("19", 0)) / 10.0 if "19" in dps else 0.0
            return {
                "success": True,
                "online": True,
                "switch": switch_val,
                "countdown": 0,
                "power": power_val,
                "mode": "local_lan"
            }
        return None
    except Exception:
        return None

def start_dryer(entity_id, duration_minutes):
    """Turn Bardi smart plug ON: Local LAN First -> Fallback to Cloud."""
    dev = resolve_tuya_device(entity_id)
    if not dev:
        print(f"[Tuya] Device matching {entity_id} not found in devices.json")
        return {"success": False, "error": "Device not found"}

    # --- 1. LOCAL LAN FIRST (OFFLINE 0ms) ---
    ok_local, err_local = start_dryer_local(dev, duration_minutes)
    if ok_local:
        return {"success": True, "mode": "local_lan"}

    print(f"[Tuya] Local LAN failed ({err_local}), falling back to Tuya Cloud API...")

    # --- 2. FALLBACK: TUYA CLOUD API ---
    creds = load_tuya_credentials()
    if not (creds["access_id"] and creds["access_secret"]):
        return {"success": False, "error": f"Local LAN failed ({err_local}) and Tuya Cloud credentials not configured"}

    try:
        c = tinytuya.Cloud(
            apiRegion="us",
            apiKey=creds["access_id"],
            apiSecret=creds["access_secret"]
        )
        device_id = dev["id"]
        switch_code = get_switch_code(c, device_id)
        duration_seconds = duration_minutes * 60

        payload = {
            "commands": [
                {
                    "code": switch_code,
                    "value": True
                },
                {
                    "code": "countdown_1",
                    "value": duration_seconds
                },
                {
                    "code": "relay_status",
                    "value": "off"
                }
            ]
        }

        print(f"[Tuya Cloud] Starting dryer {entity_id} ({device_id}) for {duration_minutes} min...")
        res = c.sendcommand(device_id, payload)
        if isinstance(res, dict) and res.get("success"):
            return {"success": True, "mode": "cloud"}
        else:
            msg = res.get("msg") if isinstance(res, dict) else "Cloud command rejected"
            return {"success": False, "error": msg}
    except Exception as e:
        print(f"[Tuya] Error starting dryer {entity_id}: {e}")
        return {"success": False, "error": str(e)}

def stop_dryer(entity_id):
    """Turn Bardi smart plug OFF: Local LAN First -> Fallback to Cloud."""
    dev = resolve_tuya_device(entity_id)
    if not dev:
        print(f"[Tuya] Device matching {entity_id} not found in devices.json")
        return {"success": False, "error": "Device not found"}

    # --- 1. LOCAL LAN FIRST (OFFLINE 0ms) ---
    ok_local, err_local = stop_dryer_local(dev)
    if ok_local:
        return {"success": True, "mode": "local_lan"}

    print(f"[Tuya] Local LAN failed ({err_local}), falling back to Tuya Cloud API...")

    # --- 2. FALLBACK: TUYA CLOUD API ---
    creds = load_tuya_credentials()
    if not (creds["access_id"] and creds["access_secret"]):
        return {"success": False, "error": f"Local LAN failed ({err_local}) and Tuya Cloud credentials not configured"}

    try:
        c = tinytuya.Cloud(
            apiRegion="us",
            apiKey=creds["access_id"],
            apiSecret=creds["access_secret"]
        )
        device_id = dev["id"]
        switch_code = get_switch_code(c, device_id)

        payload = {
            "commands": [
                {
                    "code": switch_code,
                    "value": False
                },
                {
                    "code": "countdown_1",
                    "value": 0
                }
            ]
        }

        print(f"[Tuya Cloud] Stopping dryer {entity_id} ({device_id})...")
        res = c.sendcommand(device_id, payload)
        if isinstance(res, dict) and res.get("success"):
            return {"success": True, "mode": "cloud"}
        else:
            msg = res.get("msg") if isinstance(res, dict) else "Cloud command rejected"
            return {"success": False, "error": msg}
    except Exception as e:
        print(f"[Tuya] Error stopping dryer {entity_id}: {e}")
        return {"success": False, "error": str(e)}

def get_dryer_status(entity_id):
    """Query smart plug status: Local LAN First -> Fallback to Cloud."""
    dev = resolve_tuya_device(entity_id)
    if not dev:
        return {"success": False, "error": "Device not found", "online": False}

    # --- 1. LOCAL LAN FIRST (OFFLINE) ---
    local_stat = get_dryer_status_local(dev)
    if local_stat:
        return local_stat

    # --- 2. FALLBACK: TUYA CLOUD API ---
    creds = load_tuya_credentials()
    if not (creds["access_id"] and creds["access_secret"]):
        return {"success": False, "error": "Tuya credentials not configured", "online": False}

    try:
        c = tinytuya.Cloud(
            apiRegion="us",
            apiKey=creds["access_id"],
            apiSecret=creds["access_secret"]
        )
        device_id = dev["id"]
        res = c.cloudrequest(f"/v1.0/devices/{device_id}")

        if isinstance(res, dict) and res.get("success"):
            result = res.get("result", {})
            online = result.get("online", False)
            status_list = result.get("status", [])

            switch_val = False
            countdown_val = 0
            power_val = 0.0

            for status in status_list:
                code = status.get("code")
                val = status.get("value")
                if code in ["switch_1", "switch"]:
                    switch_val = bool(val)
                elif code == "countdown_1":
                    countdown_val = int(val)
                elif code == "cur_power":
                    power_val = float(val)

            return {
                "success": True,
                "online": online,
                "switch": switch_val,
                "countdown": countdown_val,
                "power": power_val,
                "mode": "cloud"
            }
        else:
            return {"success": False, "online": False, "error": "Status request failed"}
    except Exception as e:
        print(f"[Tuya] Error querying dryer status for {entity_id}: {e}")
        return {"success": False, "online": False, "error": str(e)}

def auto_register_cz_devices():
    """Automatically register Bardi plugs (category cz) into SQLite database if not present."""
    from config import DB_PATH
    cz_devices = get_cz_devices()
    if not cz_devices:
        return 0
        
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        
        # Get existing machine urls
        cursor.execute("SELECT url FROM machines")
        existing_urls = {row[0] for row in cursor.fetchall()}
        
        added_count = 0
        now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        
        for dev in cz_devices:
            raw_name = dev.get("name", "Pengering Bardi")
            target_url = raw_name.replace(" ", "_")
            
            if target_url not in existing_urls:
                cursor.execute(
                    "INSERT INTO machines (machine_type, name, url, key, created_at, sort_order) VALUES (?, ?, ?, ?, ?, ?)",
                    ("pengering", raw_name, target_url, "pengering", now_str, 0)
                )
                existing_urls.add(target_url)
                added_count += 1
                print(f"[Tuya] Auto-registered new dryer machine: {raw_name} -> {target_url}")
                
        conn.commit()
        conn.close()
        return added_count
    except Exception as e:
        print(f"[Tuya] Error auto-registering Bardi devices: {e}")
        return 0
