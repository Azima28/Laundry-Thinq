# config.py - Centralized config loader from config.json
import os
import json

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

def resolve_appdata_file(filename, subfolder=None):
    """Resolve file path in %APPDATA%\SmartLaundry to prevent UAC write permission errors in Program Files."""
    if sys.platform == 'win32':
        appdata = os.environ.get('APPDATA')
        if appdata:
            data_dir = os.path.join(appdata, 'SmartLaundry')
            if subfolder:
                data_dir = os.path.join(data_dir, subfolder)
            os.makedirs(data_dir, exist_ok=True)
            target = os.path.join(data_dir, filename)

            # Auto copy initial bundle file to AppData if not present
            base_file = os.path.join(get_base_path(), subfolder, filename) if subfolder else os.path.join(get_base_path(), filename)
            if not os.path.exists(target) and os.path.exists(base_file):
                try:
                    import shutil
                    shutil.copy2(base_file, target)
                    print(f"[Config] Initialized {filename} at {target}")
                except Exception as e:
                    print(f"[Config] Error copying {filename}: {e}")
            return target

    if subfolder:
        return os.path.join(get_base_path(), subfolder, filename)
    return os.path.join(get_base_path(), filename)

CONFIG_JSON_PATH = resolve_appdata_file("config.json")
DEVICES_JSON_PATH = resolve_appdata_file("devices.json", "smartplug_controller")

import base64

def xor_encrypt_decrypt(data_str, key="AzimaSecretKey2026"):
    """Simple XOR cipher for data obfuscation and base64 encoding."""
    data_bytes = data_str.encode('utf-8')
    key_bytes = key.encode('utf-8')
    key_len = len(key_bytes)
    xor_bytes = bytearray(data_bytes[i] ^ key_bytes[i % key_len] for i in range(len(data_bytes)))
    return base64.b64encode(xor_bytes).decode('utf-8')

def xor_decrypt(encoded_str, key="AzimaSecretKey2026"):
    """Decrypt XOR cipher base64 encoded data. Falls back to plain text if not encrypted."""
    try:
        xor_bytes = base64.b64decode(encoded_str.encode('utf-8'))
        key_bytes = key.encode('utf-8')
        key_len = len(key_bytes)
        decrypted_bytes = bytearray(xor_bytes[i] ^ key_bytes[i % key_len] for i in range(len(xor_bytes)))
        return decrypted_bytes.decode('utf-8')
    except Exception:
        # Fallback if string is not base64 encoded
        return encoded_str

def _load_config():
    """Load configuration from config.json, automatically decrypting if encrypted."""
    if os.path.exists(CONFIG_JSON_PATH):
        try:
            with open(CONFIG_JSON_PATH, "r", encoding="utf-8") as f:
                content = f.read().strip()
            if not content:
                return {}
            # If it starts with '{', it is legacy unencrypted json
            if content.startswith("{"):
                return json.loads(content)
            # Decrypt and parse
            decrypted_text = xor_decrypt(content)
            return json.loads(decrypted_text)
        except Exception as e:
            print(f"[Config] Error loading config.json: {e}")
    return {}

def save_config(config):
    """Save config.json with encryption and update cached config."""
    try:
        plain_text = json.dumps(config, indent=4, ensure_ascii=False)
        encrypted_text = xor_encrypt_decrypt(plain_text)
        with open(CONFIG_JSON_PATH, "w", encoding="utf-8") as f:
            f.write(encrypted_text)
        global _config
        _config = config
        return True
    except Exception as e:
        print(f"[Config] Error saving config.json: {e}")
        return False

# Load config once at module import
_config = _load_config()

# Export all settings as module-level constants for backward compatibility
MONITORING_INTERVAL = _config.get("monitoring_interval", 30)
PERINTAH_HIDUP = _config.get("perintah_hidup", "on")
PERINTAH_MATI = _config.get("perintah_mati", "off")

HOST = _config.get("host", "0.0.0.0")
LOCAL_ADDRESS = _config.get("local_address", "")
DASHBOARD_PORT = _config.get("dashboard_port", 5000)
API_PORT = _config.get("api_port", 5001)
DEBUG = _config.get("debug", True)
WORKER_THREADS = _config.get("worker_threads", 32)

SSE_KEEP_ALIVE_TIMEOUT = _config.get("sse_keep_alive_timeout", 15)
REQUEST_TIMEOUT = _config.get("request_timeout", 5)

def _resolve_db_path():
    raw_path = _config.get("db_path", "")
    if raw_path and os.path.isabs(raw_path):
        return raw_path

    if sys.platform == 'win32':
        appdata = os.environ.get('APPDATA')
        if appdata:
            data_dir = os.path.join(appdata, 'SmartLaundry')
            os.makedirs(data_dir, exist_ok=True)
            return os.path.join(data_dir, 'laundry.db')

    return os.path.join(get_base_path(), "laundry.db")

DB_PATH = _resolve_db_path()

def get_config():
    """Get fresh config (for runtime changes)."""
    return _load_config()

def reload_config():
    """Reload config from file."""
    global _config
    _config = _load_config()
    return _config
