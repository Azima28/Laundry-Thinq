import tinytuya
import json
import os

# Tuya Cloud API Credentials
ACCESS_ID = "gst7mf5yytp73c9cvqjq"
ACCESS_SECRET = "3d909f01f5ad4d96aae95a7b454d8957"
APP_UID = "az1733062861059ZHSHA"  # App Account UID

def sync_keys():
    print("==================================================")
    print("          TUYA / BARDI KEY SYNCHRONIZER           ")
    print("==================================================")
    print(f"[Cloud] Menghubungkan ke Tuya Cloud API...")
    
    # Initialize the tinytuya Cloud client (Western America region)
    try:
        c = tinytuya.Cloud(
            apiRegion="us",
            apiKey=ACCESS_ID,
            apiSecret=ACCESS_SECRET
        )
    except Exception as e:
        print(f"[Error] Gagal inisialisasi cloud client: {e}")
        return

    # Fetch device list linked to the App UID
    print(f"[Cloud] Mengambil daftar perangkat untuk UID: {APP_UID}...")
    res = c.cloudrequest(f"/v1.0/users/{APP_UID}/devices")
    
    if isinstance(res, dict) and res.get("success"):
        devices = res["result"]
        print(f"[Sukses] Menemukan {len(devices)} perangkat linked.\n")
        
        # Save results to local devices.json in the same folder
        current_dir = os.path.dirname(os.path.realpath(__file__))
        json_path = os.path.join(current_dir, "devices.json")
        
        # Structure the config
        config_data = {
            "api_credentials": {
                "access_id": ACCESS_ID,
                "access_secret": ACCESS_SECRET,
                "app_uid": APP_UID
            },
            "devices": devices
        }
        
        with open(json_path, "w") as f:
            json.dump(config_data, f, indent=4)
            
        print(f"[File] Konfigurasi perangkat berhasil disimpan ke:")
        print(f"       -> {json_path}")
        print("\nDetail Perangkat:")
        for idx, dev in enumerate(devices, 1):
            print(f" {idx}. {dev.get('name')} | ID: {dev.get('id')} | Key: {dev.get('local_key')} | {'ONLINE' if dev.get('online') else 'OFFLINE'}")
        print("==================================================")
            
    else:
        print(f"[Gagal] Cloud API menolak permintaan: {res.get('msg')}")
        print("Raw Response:", json.dumps(res, indent=2))

if __name__ == "__main__":
    sync_keys()
