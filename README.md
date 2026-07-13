# Mesin Cuci Monitor — Realtime Dashboard & API

Aplikasi monitoring realtime untuk mesin cuci yang terintegrasi dengan Home Assistant.

## 📋 Fitur

- **Dashboard Realtime**: tampilan live dengan kartu sensor yang update otomatis via SSE (Server-Sent Events)
- **API JSON**: endpoint `/machines` menampilkan status semua mesin dalam format JSON yang mudah dibaca
- **Dual-Port Architecture**: Dashboard di port 5000, API di port 5001
- **Mudah dikonfigurasi**: semua setting ada di file `config.py`
- **Offline-friendly**: bisa berjalan tanpa Home Assistant dengan `SKIP_SNAPSHOT=True` dan `SKIP_WS=True`

## 🚀 Quick Start

### 1. Install Dependencies

```bash
pip install -r requirements.txt
```

### 2. Konfigurasi Home Assistant (opsional)

Edit `config.py`:

```python
TOKEN = "your_ha_token_here"
WS_URL = "ws://your_ha_host:8123/api/websocket"
REST_URL = "http://your_ha_host:8123/api/states/"
```

> **Catatan**: Token dapat dihasilkan dari Settings → Developers Tools → Create Token di Home Assistant.

Untuk mendapatkan entity IDs sensor mesin Anda, gunakan:

```bash
curl -X GET -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  http://your_ha_host:8123/api/states/
```

Kemudian cari sensor yang relevan (mis. `sensor.mesin_cuci_2_remaining_time`).

### 3. Konfigurasi Mesin Cuci

Edit `config.py` untuk menambahkan mesin Anda. Contoh:

```python
TARGET = "sensor"
MESIN = [
    "mesin_cuci_bukaan_depan",
    "mesin_cuci_2",
    "mesin_cuci_3",
]
```

Aplikasi akan otomatis menghasilkan `SENSORS = ["sensor.mesin_cuci_bukaan_depan", "sensor.mesin_cuci_2", ...]`.

### 4. Jalankan Aplikasi

```bash
python main.py
```

Aplikasi akan menampilkan:

```
[App] Fetching initial snapshot...
[App] Starting Machines API on http://127.0.0.1:5001 (root path)
[App] Starting Dashboard (waitress) on http://127.0.0.1:5000
```

### 5. Akses

- **Dashboard**: http://127.0.0.1:5000/
- **API JSON**: http://127.0.0.1:5001/

## ⚙️ Konfigurasi Lengkap

File `config.py` berisi semua opsi:

| Setting | Default | Deskripsi |
|---------|---------|-----------|
| `TOKEN` | (HA Token) | Bearer token Home Assistant |
| `WS_URL` | `ws://localhost:8123/api/websocket` | WebSocket URL HA |
| `REST_URL` | `http://localhost:8123/api/states/` | REST API URL HA |
| `TARGET` | `"sensor"` | Domain entity (sensor, binary_sensor, dll) |
| `MESIN` | `[...]` | Daftar mesin tanpa domain prefix |
| `HOST` | `127.0.0.1` | Host server (localhost) |
| `DASHBOARD_PORT` | `5000` | Port dashboard |
| `API_PORT` | `5001` | Port API JSON |
| `DEBUG` | `True` | Mode debug (verbose logs) |
| `SKIP_SNAPSHOT` | `True` | Lewati REST snapshot saat startup |
| `SKIP_WS` | `True` | Lewati WebSocket ke HA |
| `SSE_KEEP_ALIVE_TIMEOUT` | `15` | Timeout keep-alive SSE (detik) |
| `REQUEST_TIMEOUT` | `5` | Timeout request HTTP (detik) |

### Mode Development (offline)

```python
DEBUG = True
SKIP_SNAPSHOT = True
SKIP_WS = True
```

Aplikasi akan berjalan dengan default values dan tidak mencoba koneksi ke HA.

### Mode Production (dengan HA)

```python
DEBUG = False
SKIP_SNAPSHOT = False
SKIP_WS = False
# Pastikan TOKEN, WS_URL, REST_URL benar
```

## 📊 Struktur Direktori

```
laundry/
├── main.py                    # Aplikasi utama
├── config.py                  # Konfigurasi (edit ini untuk setup)
├── requirements.txt           # Python dependencies
├── README.md                  # File ini
├── templates/
│   └── index.html            # Dashboard HTML
└── static/
    └── styles.css            # CSS dashboard
```

## 🔌 API Endpoints

### GET `/`

Halaman dashboard HTML dengan SSE realtime.

### GET `/events`

Server-Sent Events stream. Browser akan otomatis berlangganan perubahan sensor.

Setiap event berisi:

```
data: sensor.mesin_cuci_2|on|Membilas|0:07:00|Speed Wash
```

Format: `entity_id|state|run_state|remain_time|current_course`

### GET `/machines`

JSON dengan status semua mesin:

```json
{
  "sensor.mesin_cuci_2": {
    "state": "on",
    "run_state": "Membilas",
    "remain_time": "0:07:00",
    "current_course": "Speed Wash"
  },
  "sensor.mesin_cuci_3": {
    "state": "off",
    "run_state": "-",
    "remain_time": "0:00:00",
    "current_course": "-"
  }
}
```

## 🔍 Troubleshooting

### Error: "Connection refused" saat startup

Home Assistant tidak tersedia di `WS_URL` atau `REST_URL`.

**Solusi**:
- Pastikan HA berjalan dan accessible dari machine ini.
- Atau, set `SKIP_SNAPSHOT=True` dan `SKIP_WS=True` di `config.py` untuk menjalankan offline.

### Error: "AssertionError: Connection is a hop-by-hop header"

(Sudah diperbaiki di versi terbaru). Jika masih muncul, pastikan Anda menggunakan `waitress >= 2.1.2`.

### Dashboard tidak update/SSE tidak bekerja

1. Buka browser DevTools (F12), tab Network, cari request `/events`.
2. Pastikan status `200 OK` dan connection `streaming`.
3. Jika fail, cek apakah app berjalan dengan benar (`python main.py`).
4. Jika WS tidak terhubung ke HA, cek `SKIP_WS` (harus `False` untuk koneksi HA).

### Saya ingin menambah/menghapus mesin

Edit `config.py`, ubah list `MESIN`:

```python
MESIN = [
    "mesin_cuci_1",
    "mesin_cuci_2",
    "mesin_cuci_3",
]
```

Restart aplikasi (`Ctrl+C` lalu `python main.py`).

## 📝 Catatan

- **Entity IDs HA**: Pastikan nama mesin di `MESIN` list sesuai dengan entity IDs HA yang sebenarnya (tanpa domain prefix).
- **Token expiry**: Token HA punya masa berlaku. Jika expired, buat token baru di Home Assistant.
- **Firewall**: Pastikan port 5000 dan 5001 accessible dari client yang ingin mengakses.
- **Production Deployment**: Gunakan reverse proxy (nginx, Caddy) atau cloud tunnel (Cloudflare, ngrok) untuk expose ke internet secara aman.

## 📄 License

MIT (atau sesuai preferensi Anda)
