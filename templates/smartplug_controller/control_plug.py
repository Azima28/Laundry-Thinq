import tinytuya
import json
import sys
import os
import threading
import time

# Global variables for state tracking
last_known_state = None
lock = threading.Lock()
running = True
selected_device_id = None
selected_device_name = None

def get_device_state(cloud_client, device_id):
    try:
        res = cloud_client.cloudrequest(f"/v1.0/devices/{device_id}")
        if isinstance(res, dict) and res.get("success"):
            status_list = res["result"].get("status", [])
            # Search for switch code (could be 'switch_1', 'switch', or 'gas_sensor_state' depending on category)
            for status in status_list:
                if status.get("code") in ["switch_1", "switch", "gas_sensor_state"]:
                    return status.get("value")
    except Exception:
        pass
    return None

def get_switch_code(cloud_client, device_id):
    """Detect which function code represents the switch/state code"""
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
    return "switch_1" # Default fallback

def status_monitor_thread(cloud_client, device_id, code_name):
    global last_known_state, running
    
    # Get initial state
    initial_state = get_device_state(cloud_client, device_id)
    with lock:
        last_known_state = initial_state
        state_str = str(last_known_state) if last_known_state is not None else "TIDAK DIKETAHUI"
        if last_known_state is True: state_str = "NYALA (ON)"
        elif last_known_state is False: state_str = "MATI (OFF)"
        
        print(f"\n[Status Awal] {selected_device_name} saat ini: {state_str}")
        print("Masukkan perintah (on/off/exit): ", end="", flush=True)

    while running:
        time.sleep(2)
        if not running:
            break
            
        current_state = get_device_state(cloud_client, device_id)
        if current_state is not None:
            with lock:
                if current_state != last_known_state:
                    last_known_state = current_state
                    state_str = str(current_state)
                    if current_state is True: state_str = "NYALA (ON)"
                    elif current_state is False: state_str = "MATI (OFF)"
                    
                    # Print status update and rewrite the prompt cleanly
                    print(f"\n[Status Update] {selected_device_name} berubah menjadi: {state_str}")
                    print("Masukkan perintah (on/off/exit): ", end="", flush=True)

def main():
    global last_known_state, running, selected_device_id, selected_device_name
    
    current_dir = os.path.dirname(os.path.realpath(__file__))
    json_path = os.path.join(current_dir, "devices.json")
    
    # Check if config file exists
    if not os.path.exists(json_path):
        print("==================================================")
        print("[Error] File 'devices.json' tidak ditemukan!")
        print("Silakan jalankan script sinkronisasi terlebih dahulu:")
        print("       python sync_keys.py")
        print("==================================================")
        sys.exit(1)
        
    # Read devices.json
    try:
        with open(json_path, "r") as f:
            config = json.load(f)
    except Exception as e:
        print(f"[Error] Gagal membaca 'devices.json': {e}")
        sys.exit(1)
        
    creds = config.get("api_credentials", {})
    devices = config.get("devices", [])
    
    if not devices:
        print("[Error] Tidak ada perangkat yang tersimpan di devices.json!")
        sys.exit(1)
        
    # Connect to Cloud Client
    try:
        c = tinytuya.Cloud(
            apiRegion="us",
            apiKey=creds.get("access_id"),
            apiSecret=creds.get("access_secret")
        )
    except Exception as e:
        print(f"[Error] Gagal inisialisasi cloud client: {e}")
        sys.exit(1)
        
    # Let user select the device
    print("==================================================")
    print("      BARDI SMARTPLUG & SENSOR CONTROLLER (CLI)   ")
    print("==================================================")
    print("Pilih perangkat yang ingin Anda kendalikan:")
    for idx, dev in enumerate(devices, 1):
        print(f" {idx}. {dev.get('name')} (ID: {dev.get('id')[:6]}...) | {'ONLINE' if dev.get('online') else 'OFFLINE'}")
    print("==================================================")
    
    while True:
        try:
            choice = input(f"Pilih perangkat (1-{len(devices)}): ").strip()
            if not choice:
                continue
            choice_idx = int(choice) - 1
            if 0 <= choice_idx < len(devices):
                dev = devices[choice_idx]
                selected_device_id = dev.get("id")
                selected_device_name = dev.get("name")
                break
            else:
                print(f"[Peringatan] Masukkan angka antara 1 sampai {len(devices)}!")
        except ValueError:
            print("[Peringatan] Harap masukkan angka yang valid!")
            
    print(f"\n[System] Menghubungkan ke {selected_device_name}...")
    
    # Detect the switch/state code dynamically
    switch_code = get_switch_code(c, selected_device_id)
    
    print("==================================================")
    print(f"Mengendalikan: {selected_device_name}")
    print("Gunakan perintah berikut:")
    print(" - Ketik 'on'  : Menyalakan perangkat")
    print(" - Ketik 'off' : Mematikan perangkat")
    print(" - Ketik 'exit': Keluar dari program")
    print("==================================================")

    # Start background polling thread
    monitor = threading.Thread(
        target=status_monitor_thread, 
        args=(c, selected_device_id, switch_code), 
        daemon=True
    )
    monitor.start()

    while True:
        try:
            command = input().strip().lower()
            
            if not command:
                with lock:
                    print("Masukkan perintah (on/off/exit): ", end="", flush=True)
                continue
                
            if command == "exit":
                print("Mengakhiri program. Sampai jumpa!")
                running = False
                break
                
            elif command == "on":
                print(f"[Cloud] Mengirim perintah ON ke {selected_device_name}...")
                payload = {
                    "commands": [
                        {
                            "code": switch_code,
                            "value": True
                        }
                    ]
                }
                res = c.sendcommand(selected_device_id, payload)
                
                if res.get("success"):
                    print("[Sukses] Perintah ON terkirim.")
                    with lock:
                        last_known_state = True
                else:
                    print(f"[Gagal] Cloud menolak perintah: {res.get('msg')}")
                    
            elif command == "off":
                print(f"[Cloud] Mengirim perintah OFF ke {selected_device_name}...")
                payload = {
                    "commands": [
                        {
                            "code": switch_code,
                            "value": False
                        }
                    ]
                }
                res = c.sendcommand(selected_device_id, payload)
                
                if res.get("success"):
                    print("[Sukses] Perintah OFF terkirim.")
                    with lock:
                        last_known_state = False
                else:
                    print(f"[Gagal] Cloud menolak perintah: {res.get('msg')}")
            
            else:
                print("[Peringatan] Perintah tidak dikenal! Gunakan 'on', 'off', atau 'exit'.")
            
            with lock:
                print("Masukkan perintah (on/off/exit): ", end="", flush=True)
                
        except KeyboardInterrupt:
            print("\nProgram dihentikan paksa (Ctrl+C). Keluar...")
            running = False
            break
        except Exception as e:
            print(f"[Error] Terjadi kesalahan: {e}")
            with lock:
                print("Masukkan perintah (on/off/exit): ", end="", flush=True)

if __name__ == "__main__":
    main()
