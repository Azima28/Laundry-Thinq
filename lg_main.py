import sys
import os
import json
import asyncio
import logging
from datetime import datetime
from aiohttp import web

# Memastikan kita bisa mengimpor modul 'wideq'
current_dir = os.path.dirname(os.path.abspath(__file__))
parent_dir = os.path.dirname(current_dir)

# Cek di folder saat ini atau di folder induk
if os.path.exists(os.path.join(current_dir, "wideq")):
    sys.path.append(current_dir)
elif os.path.exists(os.path.join(parent_dir, "wideq")):
    sys.path.append(parent_dir)
else:
    # Fallback ke parent jika tidak yakin
    sys.path.append(parent_dir)

from wideq.core_async import ClientAsync
from wideq.factory import get_lge_device

# Global state untuk menyimpan data terbaru dari semua mesin
GLOBAL_STATE = {}

# Set up logging
logging.basicConfig(level=logging.ERROR, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

CONFIG_FILE = os.path.join(current_dir, "config.json")
SETTINGS_FILE = os.path.join(current_dir, "settings.json")

def load_settings():
    """Memuat pengaturan user dari settings.json."""
    defaults = {
        "monitoring_interval": 30,
        "web_server_port": 4000,
        "show_unmapped_data": True
    }
    if os.path.exists(SETTINGS_FILE):
        try:
            with open(SETTINGS_FILE, "r", encoding="utf-8") as f:
                user_settings = json.load(f)
                defaults.update(user_settings)
        except Exception as e:
            print(f"[!] Gagal membaca settings.json: {e}")
    return defaults

async def run_login():
    """Proses login manual untuk mendapatkan token."""
    print("\n" + "="*40)
    print("      PROSES LOGIN LG THINQ")
    print("="*40)
    
    country = input("Masukkan Kode Negara [ID]: ") or "ID"
    language = input("Masukkan Kode Bahasa [id-ID]: ") or "id-ID"
    
    login_url = await ClientAsync.get_login_url(country, language)
    print(f"\nBuka URL ini di browser:\n{login_url}\n")
    
    callback_url = input("Paste URL Redirect ke sini:\n> ").strip()
    if not callback_url: return None

    oauth_info = await ClientAsync.oauth_info_from_url(callback_url, country, language)
    refresh_token = oauth_info.get("refresh_token")
    
    if refresh_token:
        config_data = {"refresh_token": refresh_token, "country": country, "language": language}
        import config as cfg_module
        encrypted_text = cfg_module.xor_encrypt_decrypt(json.dumps(config_data, indent=4))
        with open(CONFIG_FILE, "w", encoding="utf-8") as f:
            f.write(encrypted_text)
        return config_data
    return None

async def handle_status_request(request):
    """Endpoint JSON data semua mesin."""
    return web.json_response(GLOBAL_STATE)

async def start_web_server(port):
    """Menjalankan server web aiohttp."""
    app = web.Application()
    app.router.add_get('/', handle_status_request)
    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, '0.0.0.0', port)
    await site.start()
    return runner

async def run_api_mode(config, settings):
    """Loop utama: Aggregator data di background + Web Server."""
    port = settings.get("web_server_port", 4000)
    interval = settings.get("monitoring_interval", 30)
    
    print(f"\n[*] API SERVER AKTIF")
    print(f"[*] Port: {port} | Refresh: {interval}s")
    print(f"[*] URL: http://localhost:{port}/")
    print(f"[*] Tekan Ctrl+C untuk berhenti.\n")

    runner = await start_web_server(port)
    
    try:
        while True:
            client = await ClientAsync.from_token(
                config["refresh_token"], 
                country=config["country"], 
                language=config["language"]
            )
            try:
                devices_info = client.devices
                
                async def poll_one(dev_info):
                    try:
                        lge_devs = get_lge_device(client, dev_info)
                        if not lge_devs: return dev_info.name, {"error": "Unknown type"}
                        device = lge_devs[0]
                        await device.init_device_info()
                        status = await device.poll()
                        if not status: return dev_info.name, {"error": "Poll failed"}
                        
                        return dev_info.name, {
                            "device_id": dev_info.device_id,
                            "type": dev_info.type.name,
                            "is_online": status.is_on,
                            "is_run_completed": status.is_run_completed,
                            "features": status.device_features,
                            "raw_data": status.as_dict,
                            "last_update": datetime.now().strftime('%H:%M:%S')
                        }
                    except Exception as ex:
                        return dev_info.name, {"error": str(ex)}

                tasks = [poll_one(d) for d in devices_info]
                results = await asyncio.gather(*tasks)
                
                for name, data in results:
                    GLOBAL_STATE[name] = data
                
                print(f"[{datetime.now().strftime('%H:%M:%S')}] Updated {len(results)} devices.")
                
            finally:
                await client.close()
            
            await asyncio.sleep(interval)
            
    except Exception as e:
        print(f"[!] Error: {e}")
    finally:
        await runner.cleanup()

async def main():
    print("      LG ThinQ Standalone API Server")
    print("="*40 + "\n")
    
    config = {}
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                content = f.read().strip()
            if content.startswith("{"):
                config = json.loads(content)
            else:
                import config as cfg_module
                config = json.loads(cfg_module.xor_decrypt(content))
        except: pass

    if not config or not config.get("refresh_token"):
        config = await run_login()
    
    if config:
        settings = load_settings()
        await run_api_mode(config, settings)

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n[*] Selesai.")
        sys.exit(0)
