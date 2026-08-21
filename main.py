from flask import Flask, Response, render_template, jsonify, request
import requests
try:
    from waitress import serve as waitress_serve
except Exception:
    waitress_serve = None

import json
import threading
import socket
import os
import asyncio
from datetime import datetime
from zeroconf import ServiceInfo, Zeroconf

# Import Managers
import sse_manager
import machine_manager
import lg_manager
import database
import wa_bridge
import tuya_manager

# Import Configuration
from config import (
    HOST, LOCAL_ADDRESS, PERINTAH_HIDUP, PERINTAH_MATI,
    DASHBOARD_PORT, API_PORT, DEBUG, WORKER_THREADS,
    SSE_KEEP_ALIVE_TIMEOUT
)

# WideQ Core for Auth routes
from wideq.core_async import ClientAsync

# -------------------
# FLASK APP SETUP
# -------------------
app = Flask(__name__)
app.config['TEMPLATES_AUTO_RELOAD'] = True

api_app = Flask('machines_api', static_folder='static')

# -------------------
# DASHBOARD ROUTES
# -------------------
@app.route('/')
def index():
    return jsonify({"success": False, "error": "Web interface is disabled. Please use the desktop application."}), 403

@app.route('/events')
def sse_events():
    headers = {
        "Cache-Control": "no-cache",
        "X-Accel-Buffering": "no",
        "Content-Type": "text/event-stream; charset=utf-8"
    }
    return Response(sse_manager.get_sse_stream(SSE_KEEP_ALIVE_TIMEOUT), 
                    mimetype="text/event-stream", headers=headers)

# -------------------
# API ROUTES
# -------------------
@api_app.route('/')
def machines_json():
    result = {}
    try:
        db_machines = database.get_all_machines()
    except Exception as e:
        print(f"[API] Error reading machines: {e}")
        db_machines = []
        
    # In case DB is empty (first run), fallback to default simulation list
    if not db_machines:
        defaults = [
            {"name": "Mesin Cuci 1", "url": "Mesin_Cuci_1", "key": "cuci"},
            {"name": "Mesin Cuci 2", "url": "Mesin_Cuci_2", "key": "cuci"},
            {"name": "Mesin Cuci 3", "url": "Mesin_Cuci_3", "key": "cuci"},
            {"name": "Mesin Cuci 4", "url": "Mesin_Cuci_4", "key": "cuci"},
            {"name": "Mesin Cuci 5", "url": "Mesin_Cuci_5", "key": "cuci"},
        ]
        db_machines = defaults
        
    for m in db_machines:
        sensor = m.get("name").replace(' ', '_')
        url = m.get("url", "-")
        key = m.get("key", "cuci")
        is_manual = (url == "-")
        
        raw = sse_manager.latest_state.get(sensor, f"{sensor}|Ready|Idle|--:--|-|-|0")
        parts = raw.split('|')
        while len(parts) < 7: parts.append('-')
        
        status_ready = machine_manager.get_machine_status(sensor)
        customer = machine_manager.get_customer_info(sensor)
        
        result[sensor] = {
            "name": m.get("name"),
            "url": url,
            "key": key,
            "is_manual": is_manual,
            "state": parts[1],
            "run_state": parts[2],
            "remain_time": parts[3],
            "current_course": parts[4],
            "error_message": parts[5] if len(parts) > 5 else "-",
            "is_completed": parts[6] == "1" if len(parts) > 6 else False,
            "status": status_ready,
            "customer_name": customer.get("name"),
            "customer_phone": customer.get("phone"),
            "wa_sent": machine_manager.is_wa_completion_sent(sensor),
            "other_machines": machine_manager.get_other_active_machines(sensor),
            "is_last_machine": machine_manager.is_last_machine_for_customer(sensor),
        }
    return Response(json.dumps(result, indent=2, ensure_ascii=False), mimetype='application/json')

@app.route('/api/logs')
def api_logs():
    try:
        limit = request.args.get('limit', 100, type=int)
        logs = database.get_recent_logs(
            limit=limit, 
            machine=request.args.get('machine'),
            action=request.args.get('action'),
            date=request.args.get('date'),
            source=request.args.get('source')
        )
        return Response(json.dumps(logs, indent=2), mimetype='application/json')
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/api/system')
def api_system():
    """Return system configuration info for the About page."""
    # Auto-detect local IP
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        local_ip = s.getsockname()[0]
        s.close()
    except Exception:
        local_ip = "127.0.0.1"
    
    from config import DASHBOARD_PORT, API_PORT, HOST, DB_PATH
    hostname = socket.gethostname()
    local_domain = f"{hostname}.local" if not hostname.endswith(".local") else hostname
    
    return jsonify({
        "dashboard_port": DASHBOARD_PORT,
        "api_port": API_PORT,
        "local_ip": local_ip,
        "hostname": hostname,
        "local_url": f"http://{local_domain}:{DASHBOARD_PORT}",
        "host": HOST,
        "db_path": DB_PATH,
        "devices": lg_manager.get_discovered_devices(),
        "dryers": lg_manager.get_manual_dryers()
    })

@app.route('/api/config', methods=['GET', 'POST'])
def api_config():
    """Get or save editable config settings."""
    if request.method == 'POST':
        data = request.get_json()
        config = lg_manager.load_lg_config()
        
        # Update editable fields
        if 'monitoring_interval' in data:
            config['monitoring_interval'] = int(data['monitoring_interval'])
        if 'request_timeout' in data:
            config['request_timeout'] = int(data['request_timeout'])
        if 'worker_threads' in data:
            config['worker_threads'] = int(data['worker_threads'])
        if 'sse_keep_alive_timeout' in data:
            config['sse_keep_alive_timeout'] = int(data['sse_keep_alive_timeout'])
        if 'wa_service_url' in data:
            config['wa_service_url'] = data['wa_service_url']
        if 'wa_templates' in data:
            config['wa_templates'] = data['wa_templates']
            
        # Chatbot configurations
        if 'chatbot_enabled' in data:
            config['chatbot_enabled'] = bool(data['chatbot_enabled'])
        if 'chatbot_price_list' in data:
            config['chatbot_price_list'] = str(data['chatbot_price_list'])
        if 'chatbot_hours' in data:
            config['chatbot_hours'] = str(data['chatbot_hours'])
        if 'chatbot_welcome_message' in data:
            config['chatbot_welcome_message'] = str(data['chatbot_welcome_message'])
        if 'chatbot_welcome_cooldown' in data:
            config['chatbot_welcome_cooldown'] = int(data['chatbot_welcome_cooldown'])
        if 'chatbot_staff_cooldown' in data:
            config['chatbot_staff_cooldown'] = int(data['chatbot_staff_cooldown'])
        if 'chatbot_menu' in data:
            config['chatbot_menu'] = data['chatbot_menu']
        
        lg_manager.save_lg_config(config)
        # Reload WA config
        wa_bridge.load_wa_config()
        return jsonify({"message": "Config saved", "success": True})
    
    # GET - return current config
    config = lg_manager.load_lg_config()
    default_prices = (
        "Daftar harga laundry kami:\n"
        "- Cuci Kering Setrika: Rp 8.000/kg\n"
        "- Cuci Kering saja: Rp 6.000/kg\n"
        "- Setrika saja: Rp 5.000/kg\n"
        "- Karpet/Bedcover: Mulai Rp 15.000/pcs"
    )
    default_hours = (
        "Jam buka toko kami:\n"
        "Setiap Hari: 07:00 - 21:00 WIB\n\n"
        "Alamat: Jl. Raya Laundry No. 123 (Dekat Indomaret)\n"
        "Google Maps: https://maps.google.com/?q=Azima+Laundry"
    )
    default_welcome = "Halo! Selamat datang di Azima Laundry. 😊 Ada yang bisa kami bantu?"
    default_menu = [
        {
            "id": "status_cucian",
            "label": "👕 Cek Status Cucian Saya",
            "type": "api",
            "action": "status_cucian",
            "mark_read": True
        },
        {
            "id": "harga",
            "label": "💰 Daftar Harga & Layanan",
            "type": "poll",
            "poll_title": "Pilih jenis layanan yang ingin dilihat harganya:",
            "mark_read": True,
            "children": [
                {
                    "id": "harga_kiloan",
                    "label": "🧺 Cuci Kiloan",
                    "type": "text",
                    "response": "📋 *HARGA CUCI KILOAN*\n\n🧺 Cuci + Kering: Rp 7.000/kg\n🧺 Cuci + Kering + Setrika: Rp 10.000/kg\n\nMinimum 3 kg.",
                    "mark_read": True
                },
                {
                    "id": "harga_satuan",
                    "label": "👔 Cuci Satuan",
                    "type": "text",
                    "response": "📋 *HARGA CUCI SATUAN*\n\n👔 Kemeja: Rp 8.000\n👖 Celana: Rp 8.000\n🧥 Jaket: Rp 15.000",
                    "mark_read": True
                }
            ]
        },
        {
            "id": "jam_operasional",
            "label": "📅 Jam Operasional & Lokasi",
            "type": "text",
            "response": default_hours,
            "mark_read": True
        },
        {
            "id": "hubungi_staff",
            "label": "📞 Hubungi Staff (Kasir)",
            "type": "staff",
            "response": "Baik Kak, pesan Anda telah kami teruskan ke staf kasir kami. Staf kami akan segera membalas chat Anda secara manual. Terima kasih! 😊",
            "mark_read": False
        }
    ]
    
    return jsonify({
        "monitoring_interval": config.get("monitoring_interval", 30),
        "request_timeout": config.get("request_timeout", 5),
        "worker_threads": config.get("worker_threads", 32),
        "sse_keep_alive_timeout": config.get("sse_keep_alive_timeout", 15),
        "wa_service_url": config.get("wa_service_url", "http://localhost:3000"),
        "wa_templates": config.get("wa_templates", wa_bridge.WA_TEMPLATES),
        "chatbot_enabled": config.get("chatbot_enabled", True),
        "chatbot_price_list": config.get("chatbot_price_list", default_prices),
        "chatbot_hours": config.get("chatbot_hours", default_hours),
        "chatbot_welcome_message": config.get("chatbot_welcome_message", default_welcome),
        "chatbot_welcome_cooldown": config.get("chatbot_welcome_cooldown", 0),
        "chatbot_staff_cooldown": config.get("chatbot_staff_cooldown", 30),
        "chatbot_menu": config.get("chatbot_menu", default_menu),
    })

@app.route('/api/stats')
def api_stats():
    daily_raw = database.get_daily_stats()
    machine_raw = database.get_machine_usage_stats()
    # Format daily (fill 30 days) omitted for brevity as it was already working
    return jsonify({"daily": dict(daily_raw), "machines": dict(machine_raw)})

@app.route('/api/machine-logs')
def api_machine_logs():
    """Get machine completion logs with optional filters."""
    logs = database.get_machine_logs(
        limit=request.args.get('limit', 200, type=int),
        machine=request.args.get('machine'),
        date=request.args.get('date'),
        month=request.args.get('month')
    )
    return Response(json.dumps(logs, indent=2, ensure_ascii=False), mimetype='application/json')

@app.route('/api/machine-logs/stats')
def api_machine_logs_stats():
    """Get machine log statistics with optional filter."""
    stats = database.get_machine_log_stats(
        machine=request.args.get('machine'),
        date=request.args.get('date')
    )
    return jsonify(stats)

@app.route('/api/machine/attributes/<name>')
def api_machine_attributes(name):
    """Fetch raw machine attributes directly from LG ThinQ."""
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    try:
        attrs = loop.run_until_complete(lg_manager.get_machine_attributes(name))
        return jsonify(attrs)
    finally:
        loop.close()

# -------------------
# v2: MONITORING CONTROL ROUTES (No relay/ESP)
# -------------------
@app.route('/api/machine/start', methods=['POST'])
def api_machine_start():
    """Start monitoring a machine (v2 monitoring-only).
    
    Expects JSON body:
    {
        "entity_id": "Mesin_Cuci_2",
        "customer_name": "Agus",           // optional
        "customer_phone": "08123456789",   // optional
        "duration": 5,                     // minutes, default 5
        "bypass_cooldown": false           // optional
    }
    """
    data = request.get_json()
    if not data:
        return jsonify({"error": "No JSON body"}), 400
    
    entity = machine_manager.resolve_entity(data.get('entity_id', ''))
    if not entity:
        return jsonify({"error": "Invalid machine"}), 400
    
    # Check cooldown
    if not data.get('bypass_cooldown') and machine_manager.get_machine_status(entity) == "unready":
        return jsonify({"error": "Machine in cooldown", "bypass_available": True}), 423
    
    duration_minutes = data.get('duration', 5)
    res, code = machine_manager.start_machine_monitoring(
        entity,
        customer_name=data.get('customer_name'),
        customer_phone=data.get('customer_phone'),
        source=data.get('source', 'customer'),
        duration_seconds=duration_minutes * 60
    )
    return jsonify({"message": res}), code


@app.route('/api/machine/stop', methods=['POST'])
def api_machine_stop():
    """Stop monitoring a machine and release it (v2).
    
    Expects JSON body:
    {
        "entity_id": "Mesin_Cuci_2"
    }
    """
    data = request.get_json()
    if not data:
        return jsonify({"error": "No JSON body"}), 400
    
    entity = machine_manager.resolve_entity(data.get('entity_id', ''))
    if not entity:
        return jsonify({"error": "Invalid machine"}), 400
    
    res, code = machine_manager.stop_machine_monitoring(entity, source=data.get('source', 'admin'))
    return jsonify({"message": res}), code


@app.route('/api/machine/replace', methods=['POST'])
def api_machine_replace():
    """Replace customer on an occupied/active machine.
    
    Expects JSON body:
    {
        "entity_id": "Mesin_Cuci_2",
        "new_customer_name": "Yanti",
        "new_customer_phone": "08123456789",
        "send_wa_to_previous": true,
        "wa_message": null
    }
    """
    data = request.get_json()
    if not data:
        return jsonify({"error": "No JSON body"}), 400
    
    entity = machine_manager.resolve_entity(data.get('entity_id', ''))
    if not entity:
        return jsonify({"error": "Invalid machine"}), 400
    
    new_name = data.get('new_customer_name', 'Pelanggan')
    new_phone = data.get('new_customer_phone')
    send_wa = data.get('send_wa_to_previous', False)
    wa_msg = data.get('wa_message')
    
    res, code = machine_manager.replace_customer(
        entity,
        new_customer_name=new_name,
        new_customer_phone=new_phone,
        send_wa_to_previous=send_wa,
        wa_message=wa_msg
    )
    return jsonify({"message": res}), code


@app.route('/api/machine/finish', methods=['POST'])
def api_machine_finish():
    """Manually stop monitoring and release a machine (Selesaikan).
    
    Expects JSON body:
    {
        "entity_id": "Mesin_Cuci_2",
        "send_wa": true,
        "wa_message": null
    }
    """
    data = request.get_json()
    if not data:
        return jsonify({"error": "No JSON body"}), 400
    
    entity = machine_manager.resolve_entity(data.get('entity_id', ''))
    if not entity:
        return jsonify({"error": "Invalid machine"}), 400
    
    send_wa = data.get('send_wa', True)
    wa_msg = data.get('wa_message')
    
    res, code = machine_manager.finish_and_notify(
        entity,
        send_wa=send_wa,
        wa_message=wa_msg
    )
    return jsonify({"message": res}), code


@app.route('/api/wa/send-custom', methods=['POST'])
def api_wa_send_custom():
    """Send a custom WA message to a phone number.
    
    Expects JSON body:
    {
        "phone": "08123456789",
        "message": "Custom message text"
    }
    """
    data = request.get_json()
    if not data:
        return jsonify({"error": "No JSON body"}), 400
    
    phone = data.get('phone')
    message = data.get('message')
    if not phone or not message:
        return jsonify({"error": "Phone and message are required"}), 400
    
    result = wa_bridge.send_wa_message(phone, message)
    return jsonify(result), 200 if result.get('success') else 500


# -------------------
# LG AUTH ROUTES
# -------------------
@api_app.route('/api/lg/status')
def lg_status():
    config = lg_manager.load_lg_config()
    return jsonify({
        "connected": bool(config.get("pat_token")),
        "country": config.get("country", "ID"),
        "language": config.get("language", "id-ID"),
        "pat_token": config.get("pat_token", ""),
        "interval_idle": config.get("interval_idle", 300),
        "interval_booking": config.get("interval_booking", 180),
        "interval_running_high": config.get("interval_running_high", 300),
        "interval_running_low": config.get("interval_running_low", 120)
    })

@api_app.route('/api/lg/devices')
def lg_devices():
    devices = lg_manager.get_discovered_devices()
    return jsonify({"devices": devices})

@api_app.route('/api/lg/settings', methods=['GET', 'POST'])
def lg_settings():
    config = lg_manager.load_lg_config()
    if request.method == 'POST':
        data = request.get_json()
        config["country"] = data.get("country", config.get("country", "ID"))
        config["language"] = data.get("language", config.get("language", "id-ID"))
        if "pat_token" in data:
            config["pat_token"] = data.get("pat_token")
        
        # Save interval settings
        for key in ["interval_idle", "interval_booking", "interval_running_high", "interval_running_low"]:
            if key in data:
                try:
                    config[key] = int(data[key])
                except:
                    pass
                    
        lg_manager.save_lg_config(config)
        return jsonify({"message": "Saved"})
        
    config["interval_idle"] = config.get("interval_idle", 300)
    config["interval_booking"] = config.get("interval_booking", 180)
    config["interval_running_high"] = config.get("interval_running_high", 300)
    config["interval_running_low"] = config.get("interval_running_low", 120)
    return jsonify(config)

# Legacy API endpoint (backward compatibility with Flutter app)
@api_app.route('/<machine>/<action>', defaults={'nama': 'customer'}, methods=['GET', 'POST'])
@api_app.route('/<machine>/<action>/<nama>', methods=['GET', 'POST'])
def machine_action(machine, action, nama):
    entity = machine_manager.resolve_entity(machine)
    if not entity: return jsonify({"error": "unknown machine"}), 404

    if action.lower() == PERINTAH_HIDUP.lower():
        if machine_manager.get_machine_status(entity) == "unready":
            return "unready", 423
        
        res, code = machine_manager.start_machine_monitoring(
            entity, source=nama, duration_seconds=300
        )
        return res, code
    elif action.lower() == PERINTAH_MATI.lower():
        res, code = machine_manager.stop_machine_monitoring(entity, source=nama)
        return res, code
    else:
        return "invalid action", 400


# -------------------
# v2: WHATSAPP ROUTES
# -------------------
@app.route('/api/wa/status')
def api_wa_status():
    """Check WhatsApp service connection status."""
    return jsonify(wa_bridge.get_wa_status())


@app.route('/api/wa/open-gui')
def api_wa_open_gui():
    """Proxy to WhatsApp Node.js service to focus/open the WhatsApp Web GUI window."""
    try:
        resp = requests.get(f"{wa_bridge.WA_SERVICE_URL}/open-gui", timeout=10)
        return Response(resp.text, mimetype='application/json'), resp.status_code
    except Exception as e:
        return jsonify({"error": f"Failed to reach WhatsApp service: {str(e)}"}), 503


@app.route('/api/wa/qr')
def api_wa_qr():
    """Proxy to WhatsApp Node.js service to fetch current QR code."""
    try:
        resp = requests.get(f"{wa_bridge.WA_SERVICE_URL}/qr", timeout=5)
        if resp.status_code == 200:
            return Response(resp.text, mimetype='application/json')
        return jsonify({"error": f"Node service status {resp.status_code}"}), resp.status_code
    except Exception as e:
        return jsonify({"error": f"Failed to reach WhatsApp service: {str(e)}"}), 503

@app.route('/api/wa/test-poll')
def api_wa_test_poll():
    """Proxy to trigger a test poll sent from Node.js."""
    phone = request.args.get('phone', '')
    try:
        resp = requests.get(f"{wa_bridge.WA_SERVICE_URL}/test-poll", params={'phone': phone}, timeout=10)
        return Response(resp.text, mimetype='application/json'), resp.status_code
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/api/wa/test-poll-result')
def api_wa_test_poll_result():
    """Proxy to fetch the latest test poll vote from Node.js memory."""
    try:
        resp = requests.get(f"{wa_bridge.WA_SERVICE_URL}/test-poll-result", timeout=5)
        return Response(resp.text, mimetype='application/json'), resp.status_code
    except Exception as e:
        return jsonify({"error": str(e)}), 500


def _format_chatbot_remain_time(run_state, remain_time, parts):
    actual_time = remain_time
    if (not actual_time or actual_time == "--:--") and len(parts) > 7:
        val = parts[7]
        import re
        if val and re.match(r'^\d+:\d+$', val):
            actual_time = val
            
    if not actual_time or actual_time == "--:--":
        if len(parts) > 1 and parts[1] in ("OFFLINE", "ERROR"):
            return "sisa waktu terputus / offline ⚠️"
        return "sisa waktu tidak diketahui ⏳"
        
    run_state_lower = (run_state or "").lower()
    
    # Case 1: Manual/Bypass/Degraded Countdown (or if we fell back to control_time which is MM:SS)
    if "menit" in run_state_lower or (len(parts) > 7 and actual_time == parts[7]):
        if ":" in actual_time:
            parts_time = actual_time.split(":")
            return f"sisa {parts_time[0]} Menit"
        return f"sisa {actual_time} Menit"
        
    # Case 2: LG ThinQ IoT Mode (where remain_time is HH:MM)
    if ":" in actual_time:
        parts_time = actual_time.split(":")
        try:
            h = int(parts_time[0])
            m = int(parts_time[1])
            total_min = h * 60 + m
            if total_min == 0:
                return "Selesai"
            return f"sisa {total_min} Menit"
        except ValueError:
            pass
            
    try:
        minutes = int(actual_time)
        return f"sisa {minutes} Menit"
    except ValueError:
        pass
        
    return f"sisa {actual_time} Menit"


def _is_order_fully_completed(order, all_timers, cursor):
    oid = order['id']
    status_lower = (order['status'] or "").lower()
    if status_lower in ('completed', 'selesai', 'done', 'finished'):
        return True
        
    # Query order items
    cursor.execute("""
        SELECT oi.item_name, oi.quantity, t.machine_type 
        FROM order_items oi
        LEFT JOIN transactions t ON oi.item_id = t.id
        WHERE oi.order_id = ?
    """, (oid,))
    items = cursor.fetchall()
    
    total_cuci = 0
    total_kering = 0
    for item in items:
        name = (item['item_name'] or "").lower()
        m_type = (item['machine_type'] or "").lower()
        qty = item['quantity'] or 0
        if m_type == 'cuci' or 'cuci' in name or 'wash' in name:
            total_cuci += qty
        elif m_type == 'pengering' or 'kering' in name or 'dry' in name or 'pengering' in name:
            total_kering += qty
            
    # Query history
    cursor.execute("""
        SELECT h.machine_name, m.machine_type, h.started_at 
        FROM machine_usage_history h
        LEFT JOIN machines m ON h.machine_id = m.id
        WHERE h.order_id = ? AND h.status = 'Success'
    """, (oid,))
    history = cursor.fetchall()
    
    runs_cuci = 0
    runs_kering = 0
    for row in history:
        m_name = (row['machine_name'] or "").lower()
        m_type = (row['machine_type'] or "").lower()
        if m_type == 'cuci' or 'cuci' in m_name or 'wash' in m_name:
            runs_cuci += 1
        elif m_type == 'pengering' or 'kering' in m_name or 'dry' in m_name or 'pengering' in m_name:
            runs_kering += 1
            
    # Calculate active timers
    active_cuci = 0
    active_kering = 0
    for timer in all_timers:
        entity_id = timer['entity_id']
        machine_clean_name = entity_id.replace('_', ' ')
        
        # Check matching history rows
        is_timer_for_this_order = False
        if timer['started_at']:
            active_start = timer['started_at'].replace(' ', 'T')
            for hr in history:
                if hr['started_at'] and hr['started_at'].startswith(active_start) and (hr['machine_name'].lower() == entity_id.lower().replace('_', ' ') or hr['machine_name'].lower() == machine_clean_name.lower()):
                    is_timer_for_this_order = True
                    break
                    
        if is_timer_for_this_order:
            cursor.execute("SELECT machine_type FROM machines WHERE name = ? OR name = ?", (entity_id, machine_clean_name))
            m_row = cursor.fetchone()
            m_type = m_row['machine_type'].lower() if m_row and m_row['machine_type'] else ""
            if m_type == 'cuci' or 'cuci' in entity_id.lower() or 'wash' in entity_id.lower():
                active_cuci += 1
            elif m_type == 'pengering' or 'kering' in entity_id.lower() or 'dry' in entity_id.lower() or 'pengering' in entity_id.lower():
                active_kering += 1
                
    completed_cuci = max(0, runs_cuci - active_cuci)
    completed_kering = max(0, runs_kering - active_kering)
    
    queue_cuci = max(0, total_cuci - completed_cuci - active_cuci)
    queue_kering = max(0, total_kering - completed_kering - active_kering)
    
    is_done = True
    if total_cuci > 0 and (completed_cuci < total_cuci or active_cuci > 0 or queue_cuci > 0):
        is_done = False
    if total_kering > 0 and (completed_kering < total_kering or active_kering > 0 or queue_kering > 0):
        is_done = False
        
    return is_done


def _calculate_queue_position(current_order, target_type, all_active_orders, all_timers, cursor):
    sorted_orders = sorted(all_active_orders, key=lambda x: x['order_date'] or "")
    total_queue_before = 0
    
    for order in sorted_orders:
        if order['id'] == current_order['id']:
            break
            
        oid = order['id']
        cursor.execute("""
            SELECT oi.item_name, oi.quantity, t.machine_type 
            FROM order_items oi
            LEFT JOIN transactions t ON oi.item_id = t.id
            WHERE oi.order_id = ?
        """, (oid,))
        items = cursor.fetchall()
        
        total_items = 0
        for item in items:
            name = (item['item_name'] or "").lower()
            m_type = (item['machine_type'] or "").lower()
            qty = item['quantity'] or 0
            if target_type == 'cuci':
                if m_type == 'cuci' or 'cuci' in name or 'wash' in name:
                    total_items += qty
            else:
                if m_type == 'pengering' or 'kering' in name or 'dry' in name or 'pengering' in name:
                    total_items += qty
                    
        if total_items == 0:
            continue
            
        cursor.execute("""
            SELECT h.machine_name, m.machine_type, h.started_at 
            FROM machine_usage_history h
            LEFT JOIN machines m ON h.machine_id = m.id
            WHERE h.order_id = ? AND h.status = 'Success'
        """, (oid,))
        history = cursor.fetchall()
        
        runs = 0
        for row in history:
            m_name = (row['machine_name'] or "").lower()
            m_type = (row['machine_type'] or "").lower()
            if target_type == 'cuci':
                if m_type == 'cuci' or 'cuci' in m_name or 'wash' in m_name:
                    runs += 1
            else:
                if m_type == 'pengering' or 'kering' in m_name or 'dry' in m_name or 'pengering' in m_name:
                    runs += 1
                    
        # Active
        active = 0
        for timer in all_timers:
            entity_id = timer['entity_id']
            machine_clean_name = entity_id.replace('_', ' ')
            is_timer_for_this_order = False
            if timer['started_at']:
                active_start = timer['started_at'].replace(' ', 'T')
                for hr in history:
                    if hr['started_at'] and hr['started_at'].startswith(active_start) and (hr['machine_name'].lower() == entity_id.lower().replace('_', ' ') or hr['machine_name'].lower() == machine_clean_name.lower()):
                        is_timer_for_this_order = True
                        break
            if is_timer_for_this_order:
                cursor.execute("SELECT machine_type FROM machines WHERE name = ? OR name = ?", (entity_id, machine_clean_name))
                m_row = cursor.fetchone()
                m_type = m_row['machine_type'].lower() if m_row and m_row['machine_type'] else ""
                if target_type == 'cuci':
                    if m_type == 'cuci' or 'cuci' in entity_id.lower() or 'wash' in entity_id.lower():
                        active += 1
                else:
                    if m_type == 'pengering' or 'kering' in entity_id.lower() or 'dry' in entity_id.lower() or 'pengering' in entity_id.lower():
                        active += 1
                        
        completed = max(0, runs - active)
        queue = max(0, total_items - completed - active)
        total_queue_before += queue
        
    return total_queue_before + 1


def _get_total_washes_ordered_before(order_id, target_type, cursor):
    cursor.execute("""
        SELECT oi.quantity, oi.item_name, t.machine_type
        FROM order_items oi
        JOIN orders o ON oi.order_id = o.id
        LEFT JOIN transactions t ON oi.item_id = t.id
        WHERE o.id < ?
    """, (order_id,))
    rows = cursor.fetchall()
    total = 0
    for r in rows:
        name = (r['item_name'] or "").lower()
        m_type = (r['machine_type'] or "").lower()
        qty = r['quantity'] or 0
        if target_type == 'cuci':
            if m_type == 'cuci' or 'cuci' in name or 'wash' in name:
                total += qty
        else:
            if m_type == 'pengering' or 'kering' in name or 'dry' in name or 'pengering' in name:
                total += qty
    return total

def _get_total_runs_started(target_type, cursor):
    cursor.execute("""
        SELECT h.machine_name, m.machine_type
        FROM machine_usage_history h
        LEFT JOIN machines m ON h.machine_id = m.id
        WHERE h.status = 'Success'
    """)
    rows = cursor.fetchall()
    total = 0
    for r in rows:
        m_name = (r['machine_name'] or "").lower()
        m_type = (r['machine_type'] or "").lower()
        if target_type == 'cuci':
            if m_type == 'cuci' or 'cuci' in m_name or 'wash' in m_name:
                total += 1
        else:
            if m_type == 'pengering' or 'kering' in m_name or 'dry' in m_name or 'pengering' in m_name:
                total += 1
    return total


def _check_if_timer_is_completed(timer, cursor):
    entity_id = timer['entity_id']
    machine_clean_name = entity_id.replace('_', ' ')
    
    import machine_manager
    timer_status = machine_manager.get_machine_status(entity_id).lower()
    if timer_status == 'unready':
        return False
        
    state_str = lg_manager.latest_state.get(entity_id, "")
    parts = state_str.split('|') if state_str else []
    
    state = parts[1] if len(parts) > 1 else "Ready"
    run_state = parts[2] if len(parts) > 2 else "Idle"
    completed_flag = parts[6] if len(parts) > 6 else "0"
    
    if completed_flag == "1" or run_state == "Completed":
        return True
        
    state_upper = state.upper()
    run_state_clean = run_state.strip()
    is_running = False
    if state_upper in ('RUNNING', 'RUN'):
        is_running = True
    elif run_state_clean and run_state_clean not in ('Idle', 'Completed', 'Ready', '-', 'unknown', ''):
        is_running = True
        
    if not is_running:
        return True
        
    return False


@api_app.route('/api/wa/chatbot/status-cucian')
def api_wa_chatbot_status_cucian():
    """Endpoint for WhatsApp chatbot to fetch active laundry status by phone number or Order ID."""
    phone = request.args.get('phone')
    order_id = request.args.get('order_id')
    
    if not phone and not order_id:
        return jsonify({"error": "Missing phone or order_id parameter"}), 400
        
    import sqlite3
    import wa_bridge
    from config import DB_PATH
    
    conn = None
    try:
        conn = sqlite3.connect(DB_PATH)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        
        # Load all active timers to be used across scenarios
        cursor.execute("SELECT * FROM active_timers")
        all_timers = cursor.fetchall()
        
        # Scenario A: Check by Order ID (Nomor Nota)
        if order_id:
            order_id = str(order_id).strip()
            order_id_digits = ''.join(c for c in order_id if c.isdigit())
            if not order_id_digits:
                return jsonify({"message": "Nomor Nota tidak valid. Silakan masukkan angka saja (Contoh: *STATUS 123*)."})
                
            cursor.execute("SELECT * FROM orders WHERE id = ?", (order_id_digits,))
            order = cursor.fetchone()
            if not order:
                return jsonify({"message": f"Maaf Kak, Nomor Nota *#{order_id_digits}* tidak ditemukan di sistem kami. Silakan hubungi kasir untuk konfirmasi."})
                
            customer_name = order['customer_name'] or "Pelanggan"
            order_status = order['status'] or "pending"
            
            status_map = {
                'pending': 'Menunggu Antrean ⏳',
                'processing': 'Sedang Diproses 🧺',
                'completed': 'Selesai (Siap Diambil) ✅',
                'picked_up': 'Sudah Diambil 🛒',
                'done': 'Selesai (Siap Diambil) ✅'
            }
            status_indo = status_map.get(order_status.lower(), order_status)
            
            # Fetch ordered quantities
            cursor.execute("""
                SELECT oi.item_name, oi.quantity, t.machine_type 
                FROM order_items oi
                LEFT JOIN transactions t ON oi.item_id = t.id
                WHERE oi.order_id = ?
            """, (order_id_digits,))
            order_items = cursor.fetchall()
            
            total_cuci = 0
            total_kering = 0
            for item in order_items:
                name = (item['item_name'] or "").lower()
                m_type = (item['machine_type'] or "").lower()
                qty = item['quantity'] or 0
                if m_type == 'cuci' or 'cuci' in name or 'wash' in name:
                    total_cuci += qty
                elif m_type == 'pengering' or 'kering' in name or 'dry' in name or 'pengering' in name:
                    total_kering += qty
            
            # Fetch usage history
            cursor.execute("""
                SELECT h.machine_name, m.machine_type 
                FROM machine_usage_history h
                LEFT JOIN machines m ON h.machine_id = m.id
                WHERE h.order_id = ? AND h.status = 'Success'
            """, (order_id_digits,))
            usage_history = cursor.fetchall()
            
            runs_cuci = 0
            runs_kering = 0
            used_machines = []
            for row in usage_history:
                m_name = (row['machine_name'] or "").lower()
                m_type = (row['machine_type'] or "").lower()
                used_machines.append(row['machine_name'])
                if m_type == 'cuci' or 'cuci' in m_name or 'wash' in m_name:
                    runs_cuci += 1
                elif m_type == 'pengering' or 'kering' in m_name or 'dry' in m_name or 'pengering' in m_name:
                    runs_kering += 1
                    
            # Calculate active and compile status list
            active_cuci = 0
            active_kering = 0
            running_machines_status = []
            
            for timer in all_timers:
                entity_id = timer['entity_id']
                machine_clean_name = entity_id.replace('_', ' ')
                
                if entity_id in used_machines or machine_clean_name in used_machines:
                    # Check if this active timer belongs to THIS order by looking up machine_usage_history
                    cursor.execute("""
                        SELECT started_at FROM machine_usage_history 
                        WHERE order_id = ? AND (LOWER(machine_name) = ? OR LOWER(machine_name) = ?)
                    """, (order_id_digits, entity_id.lower().replace('_', ' '), machine_clean_name.lower()))
                    hist_rows = cursor.fetchall()
                    is_timer_for_this_order = False
                    if timer['started_at']:
                        active_start = timer['started_at'].replace(' ', 'T')
                        for hr in hist_rows:
                            if hr['started_at'] and hr['started_at'].startswith(active_start):
                                is_timer_for_this_order = True
                                break
                                
                    if is_timer_for_this_order:
                        state_str = lg_manager.latest_state.get(entity_id, "")
                        parts = state_str.split('|') if state_str else []
                        run_state = parts[2] if len(parts) > 2 else "Idle"
                        remain_time = parts[3] if len(parts) > 3 else "--:--"
                        completed_flag = parts[6] if len(parts) > 6 else "0"
                        
                        status_label = "Menunggu/Siap Mulai"
                        icon = "⏳"
                        is_completed = (completed_flag == "1" or run_state == "Completed")
                        
                        if not is_completed:
                            # Query machine type
                            cursor.execute("SELECT machine_type FROM machines WHERE name = ? OR name = ?", (entity_id, machine_clean_name))
                            m_row = cursor.fetchone()
                            m_type = m_row['machine_type'].lower() if m_row and m_row['machine_type'] else ""
                            
                            if m_type == 'cuci' or 'cuci' in entity_id.lower() or 'wash' in entity_id.lower():
                                active_cuci += 1
                            elif m_type == 'pengering' or 'kering' in entity_id.lower() or 'dry' in entity_id.lower() or 'pengering' in entity_id.lower():
                                active_kering += 1
                                
                            rem_text = _format_chatbot_remain_time(run_state, remain_time, parts)
                            status_label = f"Sedang berjalan ({rem_text})"
                            icon = "🔵"
                        else:
                            status_label = "Selesai (Siap Diambil)"
                            icon = "✅"
                            
                        running_machines_status.append(f"{icon} *{machine_clean_name}* ({status_label})")
                    
            # Calculations
            completed_cuci = max(0, runs_cuci - active_cuci)
            completed_kering = max(0, runs_kering - active_kering)
            
            queue_cuci = max(0, total_cuci - completed_cuci - active_cuci)
            queue_kering = max(0, total_kering - completed_kering - active_kering)
            
            # Format Reply
            is_done = True
            if total_cuci > 0 and (completed_cuci < total_cuci or active_cuci > 0 or queue_cuci > 0):
                is_done = False
            if total_kering > 0 and (completed_kering < total_kering or active_kering > 0 or queue_kering > 0):
                is_done = False
                
            if is_done:
                status_indo = "Selesai (Siap Diambil) ✅"
                
            raw_date = order['order_date'] or ""
            date_part = raw_date[:10] if len(raw_date) >= 10 else raw_date
            formatted_date = date_part
            if len(date_part) == 10 and date_part[4] == '-' and date_part[7] == '-':
                pts = date_part.split('-')
                formatted_date = f"{pts[2]}/{pts[1]}"
                
            reply_msg = (
                "=========================\n"
                "🧺 *STATUS CUCIAN* 🧺\n"
                "=========================\n"
                f"Halo Kak *{customer_name}*, berikut status Pesanan *#{order_id_digits}* (Tanggal: *{formatted_date}*) Anda:\n\n"
                f"📌 *Status Utama:* *{status_indo}*\n"
            )
            
            detail_lines = []
            if total_cuci > 0:
                detail_lines.append(f"• *Cuci ({total_cuci}x):* Selesai *{completed_cuci}* | Aktif *{active_cuci}* | Antrean *{queue_cuci}*")
            if total_kering > 0:
                detail_lines.append(f"• *Kering ({total_kering}x):* Selesai *{completed_kering}* | Aktif *{active_kering}* | Antrean *{queue_kering}*")
            
            if detail_lines:
                reply_msg += "\n*📋 Rincian Proses:*\n" + "\n".join(detail_lines)
                
            if running_machines_status:
                machines_text = "\n".join(running_machines_status)
                reply_msg += f"\n\n*⚡ Mesin Aktif:*\n{machines_text}"
            
            reply_msg += (
                "\n\n=========================\n"
                "🙏 Terima kasih! 😊"
            )
            conn.close()
            return jsonify({"message": reply_msg})
            
        # Scenario B: Check by Phone Number
        if phone:
            service_type = request.args.get('service_type', 'laundry').lower()
            normalized_phone = wa_bridge._normalize_phone(phone)
            if not normalized_phone:
                return jsonify({"message": "Nomor HP tidak valid."})
                
            matched_timers = []
            if service_type == 'laundry':
                for timer in all_timers:
                    timer_phone = timer['customer_phone']
                    if timer_phone:
                        if wa_bridge._normalize_phone(timer_phone) == normalized_phone:
                            matched_timers.append(timer)
                        
            cursor.execute("SELECT * FROM orders WHERE LOWER(status) != 'picked_up'")
            all_active_orders = cursor.fetchall()
            
            matched_orders = []
            for order in all_active_orders:
                order_phone = order['customer_phone']
                if order_phone and wa_bridge._normalize_phone(order_phone) == normalized_phone:
                    # Check items for matching service_type
                    cursor.execute("""
                        SELECT oi.item_name, t.type, t.machine_type
                        FROM order_items oi
                        LEFT JOIN transactions t ON oi.item_id = t.id
                        WHERE oi.order_id = ?
                    """, (order['id'],))
                    items = cursor.fetchall()
                    
                    has_matching_item = False
                    for item in items:
                        name = (item['item_name'] or "").lower()
                        m_type = (item['machine_type'] or "").lower()
                        t_type = item['type'] if 'type' in item.keys() else 0
                        is_iron = (t_type == 2 or m_type == 'gosok' or 'gosok' in name or 'setrika' in name or 'iron' in name)
                        
                        if service_type == 'gosok' and is_iron:
                            has_matching_item = True
                            break
                        elif service_type == 'laundry' and not is_iron:
                            has_matching_item = True
                            break
                    if has_matching_item:
                        matched_orders.append(order)
                        
            if matched_orders:
                # Find the most recent order date (YYYY-MM-DD)
                valid_dates = [
                    order['order_date'][:10] 
                    for order in matched_orders 
                    if (order['order_date'] and len(order['order_date']) >= 10)
                ]
                most_recent_date = max(valid_dates) if valid_dates else None
                
                # Filter orders based on calculated completion:
                filtered_orders = []
                for order in matched_orders:
                    is_completed = _is_order_fully_completed(order, all_timers, cursor)
                    order_date_str = order['order_date'][:10] if (order['order_date'] and len(order['order_date']) >= 10) else ""
                    
                    if not is_completed:
                        filtered_orders.append(order)
                    else:
                        if most_recent_date and order_date_str == most_recent_date:
                            filtered_orders.append(order)
                matched_orders = filtered_orders
            
            if not matched_timers and not matched_orders:
                if service_type == 'gosok':
                    reply_msg = (
                        "Halo Kak, sistem tidak menemukan pesanan setrika aktif yang terhubung dengan nomor WhatsApp ini.\n\n"
                        "👉 Jika Kakak memiliki **Nomor Nota**, silakan ketik **STATUS [Nomor Nota]** (contoh: *STATUS 123*) untuk mengecek status pesanan Kakak secara langsung!"
                    )
                else:
                    reply_msg = (
                        "Halo Kak, sistem tidak menemukan cucian aktif atau pesanan berjalan yang terhubung dengan nomor WhatsApp ini.\n\n"
                        "👉 Jika Kakak memiliki **Nomor Nota**, silakan ketik **STATUS [Nomor Nota]** (contoh: *STATUS 123*) untuk mengecek status pesanan Kakak secara langsung!"
                    )
                conn.close()
                return jsonify({"message": reply_msg})
                
            unique_names = []
            seen_names_lower = set()
            for order in matched_orders:
                n = (order['customer_name'] or "").strip()
                if n and n.lower() not in seen_names_lower:
                    seen_names_lower.add(n.lower())
                    unique_names.append(n)
            for timer in matched_timers:
                n = (timer.get('customer_name') or "").strip()
                if n and n.lower() not in seen_names_lower:
                    seen_names_lower.add(n.lower())
                    unique_names.append(n)
            
            if len(unique_names) == 1:
                customer_greeting = f"Kak *{unique_names[0]}*"
            else:
                customer_greeting = "Kak"
                
            status_lines = []
            if matched_orders:
                status_map = {
                    'pending': 'Menunggu Antrean ⏳',
                    'processing': 'Sedang Diproses 🧺',
                    'completed': 'Selesai (Siap Diambil) ✅',
                    'picked_up': 'Sudah Diambil 🛒',
                    'done': 'Selesai (Siap Diambil) ✅'
                }
                
                if service_type == 'gosok':
                    status_map['processing'] = 'Sedang Disetrika 💨'
                    
                for order in matched_orders:
                    oid = order['id']
                    order_status = order['status'] or "pending"
                    status_indo = status_map.get(order_status.lower(), order_status)
                    
                    raw_date = order['order_date'] or ""
                    date_part = raw_date[:10] if len(raw_date) >= 10 else raw_date
                    formatted_date = date_part
                    if len(date_part) == 10 and date_part[4] == '-' and date_part[7] == '-':
                        pts = date_part.split('-')
                        formatted_date = f"{pts[2]}/{pts[1]}"
                        
                    status_lines.append(f"🔸 *Nota #{oid}* - _({formatted_date})_ ➔ *{status_indo}*")
                    
                    if service_type == 'gosok':
                        # Fetch gosok items count
                        cursor.execute("""
                            SELECT oi.item_name, oi.quantity, t.type, t.machine_type
                            FROM order_items oi
                            LEFT JOIN transactions t ON oi.item_id = t.id
                            WHERE oi.order_id = ?
                        """, (oid,))
                        items = cursor.fetchall()
                        
                        o_total_gosok = 0
                        for item in items:
                            name = (item['item_name'] or "").lower()
                            m_type = (item['machine_type'] or "").lower()
                            t_type = item['type'] if 'type' in item.keys() else 0
                            is_iron = (t_type == 2 or m_type == 'gosok' or 'gosok' in name or 'setrika' in name or 'iron' in name)
                            if is_iron:
                                o_total_gosok += item['quantity'] or 0
                                
                        if o_total_gosok > 0:
                            if order_status.lower() in ('completed', 'done', 'picked_up'):
                                status_lines.append(f"   • *{o_total_gosok}/{o_total_gosok} Setrika:* Selesai ✅")
                            elif order_status.lower() in ('processing', 'proses'):
                                status_lines.append(f"   • *Setrika:* Sedang disetrika 💨")
                            else:
                                status_lines.append(f"   • *Setrika:* Menunggu antrean ⏳")
                    else:
                        # Fetch counts
                        cursor.execute("""
                            SELECT oi.item_name, oi.quantity, t.machine_type 
                            FROM order_items oi
                            LEFT JOIN transactions t ON oi.item_id = t.id
                            WHERE oi.order_id = ?
                        """, (oid,))
                        items = cursor.fetchall()
                        
                        o_total_cuci = 0
                        o_total_kering = 0
                        for item in items:
                            name = (item['item_name'] or "").lower()
                            m_type = (item['machine_type'] or "").lower()
                            qty = item['quantity'] or 0
                            if m_type == 'cuci' or 'cuci' in name or 'wash' in name:
                                o_total_cuci += qty
                            elif m_type == 'pengering' or 'kering' in name or 'dry' in name or 'pengering' in name:
                                o_total_kering += qty
                                
                        cursor.execute("""
                            SELECT h.machine_name, m.machine_type 
                            FROM machine_usage_history h
                            LEFT JOIN machines m ON h.machine_id = m.id
                            WHERE h.order_id = ? AND h.status = 'Success'
                        """, (oid,))
                        history = cursor.fetchall()
                        
                        o_runs_cuci = 0
                        o_runs_kering = 0
                        o_used_machines = [row['machine_name'] for row in history]
                        for row in history:
                            m_name = (row['machine_name'] or "").lower()
                            m_type = (row['machine_type'] or "").lower()
                            if m_type == 'cuci' or 'cuci' in m_name or 'wash' in m_name:
                                o_runs_cuci += 1
                            elif m_type == 'pengering' or 'kering' in m_name or 'dry' in m_name or 'pengering' in m_name:
                                o_runs_kering += 1
                                
                        # Calculate active
                        o_active_cuci = 0
                        o_active_kering = 0
                        for timer in all_timers:
                            entity_id = timer['entity_id']
                            machine_clean_name = entity_id.replace('_', ' ')
                            if entity_id in o_used_machines or machine_clean_name in o_used_machines:
                                cursor.execute("""
                                    SELECT started_at FROM machine_usage_history 
                                    WHERE order_id = ? AND (LOWER(machine_name) = ? OR LOWER(machine_name) = ?)
                                """, (oid, entity_id.lower().replace('_', ' '), machine_clean_name.lower()))
                                hist_rows = cursor.fetchall()
                                is_timer_for_this_order = False
                                if timer['started_at']:
                                    active_start = timer['started_at'].replace(' ', 'T')
                                    for hr in hist_rows:
                                        if hr['started_at'] and hr['started_at'].startswith(active_start):
                                            is_timer_for_this_order = True
                                            break
                                            
                                if is_timer_for_this_order:
                                    is_completed = _check_if_timer_is_completed(timer, cursor)
                                    if not is_completed:
                                        cursor.execute("SELECT machine_type FROM machines WHERE name = ? OR name = ?", (entity_id, machine_clean_name))
                                        m_row = cursor.fetchone()
                                        m_type = m_row['machine_type'].lower() if m_row and m_row['machine_type'] else ""
                                        if m_type == 'cuci' or 'cuci' in entity_id.lower() or 'wash' in entity_id.lower():
                                            o_active_cuci += 1
                                        elif m_type == 'pengering' or 'kering' in entity_id.lower() or 'dry' in entity_id.lower() or 'pengering' in entity_id.lower():
                                            o_active_kering += 1
                                            
                        o_completed_cuci = max(0, o_runs_cuci - o_active_cuci)
                        o_completed_kering = max(0, o_runs_kering - o_active_kering)
                        
                        o_queue_cuci = max(0, o_total_cuci - o_completed_cuci - o_active_cuci)
                        o_queue_kering = max(0, o_total_kering - o_completed_kering - o_active_kering)
                        
                        # Fetch active machines detail to merge them
                        active_cuci_details = []
                        active_kering_details = []
                        for timer in all_timers:
                            entity_id = timer['entity_id']
                            machine_clean_name = entity_id.replace('_', ' ')
                            if entity_id in o_used_machines or machine_clean_name in o_used_machines:
                                cursor.execute("""
                                    SELECT started_at FROM machine_usage_history 
                                    WHERE order_id = ? AND (LOWER(machine_name) = ? OR LOWER(machine_name) = ?)
                                """, (oid, entity_id.lower().replace('_', ' '), machine_clean_name.lower()))
                                hist_rows = cursor.fetchall()
                                is_timer_for_this_order = False
                                if timer['started_at']:
                                    active_start = timer['started_at'].replace(' ', 'T')
                                    for hr in hist_rows:
                                        if hr['started_at'] and hr['started_at'].startswith(active_start):
                                            is_timer_for_this_order = True
                                            break
                                if is_timer_for_this_order:
                                    is_completed = _check_if_timer_is_completed(timer, cursor)
                                    if not is_completed:
                                        cursor.execute("SELECT machine_type FROM machines WHERE name = ? OR name = ?", (entity_id, machine_clean_name))
                                        m_row = cursor.fetchone()
                                        m_type = m_row['machine_type'].lower() if m_row and m_row['machine_type'] else ""
                                        state_str = lg_manager.latest_state.get(entity_id, "")
                                        parts = state_str.split('|') if state_str else []
                                        run_state = parts[2] if len(parts) > 2 else "Idle"
                                        remain_time = parts[3] if len(parts) > 3 else "--:--"
                                        rem_text = _format_chatbot_remain_time(run_state, remain_time, parts)
                                        state = parts[1] if len(parts) > 1 else "Ready"
                                        state_upper = state.upper()
                                        run_state_clean = run_state.strip()
                                        is_timer_running = False
                                        if state_upper in ('RUNNING', 'RUN'):
                                            is_timer_running = True
                                        elif run_state_clean and run_state_clean not in ('Idle', 'Completed', 'Ready', '-', 'unknown', ''):
                                            is_timer_running = True
                                            
                                        if "tidak diketahui" in rem_text or "offline" in rem_text or "terputus" in rem_text:
                                            rem_suffix = ""
                                        else:
                                            rem_clean = rem_text.replace('sisa ', '')
                                            rem_suffix = f" - sisa {rem_clean}"
                                            
                                        if m_type == 'cuci' or 'cuci' in entity_id.lower() or 'wash' in entity_id.lower():
                                            active_cuci_details.append((machine_clean_name, rem_suffix, is_timer_running))
                                        elif m_type == 'pengering' or 'kering' in entity_id.lower() or 'dry' in entity_id.lower() or 'pengering' in entity_id.lower():
                                            active_kering_details.append((machine_clean_name, rem_suffix, is_timer_running))

                        # Process Cuci
                        if o_total_cuci > 0:
                            cuci_parts = []
                            if o_completed_cuci > 0:
                                cuci_parts.append(f"*{o_completed_cuci}/{o_total_cuci} Cuci:* Selesai ✅")
                            for idx, (m_name, rem, is_timer_running) in enumerate(active_cuci_details):
                                item_num = o_completed_cuci + idx + 1
                                if is_timer_running:
                                    cuci_parts.append(f"*Cuci {item_num}:* Sedang berjalan ({m_name}){rem} 🔵")
                                else:
                                    cuci_parts.append(f"*Cuci {item_num}:* Booking ({m_name}){rem} ⏳")
                            
                            current_q = _get_total_runs_started('cuci', cursor)
                            total_before = _get_total_washes_ordered_before(oid, 'cuci', cursor)
                            for idx in range(o_queue_cuci):
                                item_num = o_completed_cuci + len(active_cuci_details) + idx + 1
                                your_q = total_before + o_completed_cuci + len(active_cuci_details) + idx + 1
                                q_pos = max(1, your_q - current_q)
                                cuci_parts.append(f"*Cuci {item_num}:* _Masih dalam antrean ke #{q_pos}_ ⏳")
                            
                            for cp in cuci_parts:
                                status_lines.append(f"   • {cp}")
                                
                        # Process Kering
                        if o_total_kering > 0:
                            kering_parts = []
                            if o_completed_kering > 0:
                                kering_parts.append(f"*{o_completed_kering}/{o_total_kering} Kering:* Selesai ✅")
                            for idx, (m_name, rem, is_timer_running) in enumerate(active_kering_details):
                                item_num = o_completed_kering + idx + 1
                                if is_timer_running:
                                    kering_parts.append(f"*Kering {item_num}:* Sedang berjalan ({m_name}){rem} 🌀")
                                else:
                                    kering_parts.append(f"*Kering {item_num}:* Booking ({m_name}){rem} ⏳")
                            
                            current_q = _get_total_runs_started('pengering', cursor)
                            total_before = _get_total_washes_ordered_before(oid, 'pengering', cursor)
                            for idx in range(o_queue_kering):
                                item_num = o_completed_kering + len(active_kering_details) + idx + 1
                                your_q = total_before + o_completed_kering + len(active_kering_details) + idx + 1
                                q_pos = max(1, your_q - current_q)
                                kering_parts.append(f"*Kering {item_num}:* _Masih dalam antrean ke #{q_pos}_ ⏳")
                                
                            for kp in kering_parts:
                                status_lines.append(f"   • {kp}")
            
            # Insert the header at the very beginning of active orders if we have them
            if matched_orders:
                if service_type == 'gosok':
                    status_lines.insert(0, "*📋 DAFTAR NOTA AKTIF SETRIKA:*")
                else:
                    status_lines.insert(0, "*📋 DAFTAR NOTA AKTIF:*")
                
            status_text = "\n".join(status_lines).strip()
            reply_msg = (
                "=========================\n"
                f"    { '💨 *STATUS SETRIKA* 💨' if service_type == 'gosok' else '🧺 *STATUS CUCIAN* 🧺' }\n"
                "=========================\n"
                f"Halo {customer_greeting}, berikut status { 'setrikamu' if service_type == 'gosok' else 'cucianmu' } saat ini:\n\n"
                f"{status_text}\n\n"
                "=========================\n"
                "🙏 Terima kasih! 😊"
            )
            conn.close()
            return jsonify({"message": reply_msg})
            
    except Exception as e:
        if conn:
            conn.close()
        return jsonify({"error": str(e)}), 500

@app.route('/api/wa/send', methods=['POST'])
def api_wa_send():
    """Send a WhatsApp message manually.
    
    Expects JSON body:
    {
        "phone": "08123456789",
        "message": "Hello!"
    }
    """
    data = request.get_json()
    if not data:
        return jsonify({"error": "No JSON body"}), 400
    
    result = wa_bridge.send_wa_message(data.get('phone'), data.get('message'))
    return jsonify(result)


@app.route('/api/wa/outbox')
def api_wa_outbox():
    """Get pending WA messages from outbox."""
    pending = database.get_pending_wa_outbox(limit=50)
    return Response(json.dumps(pending, indent=2, ensure_ascii=False), mimetype='application/json')


@app.route('/api/connectivity')
def api_connectivity():
    """Get connectivity status for Internet, LG ThinQ, Bardi Tuya, and WA Service."""
    # Internet check
    internet_ok = False
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.settimeout(3)
        s.connect(("8.8.8.8", 80))
        s.close()
        internet_ok = True
    except Exception:
        pass
    
    # LG ThinQ check (are we getting data from devices and connection is healthy?)
    thinq_ok = (len(lg_manager.get_discovered_devices()) > 0) and not lg_manager.thinq_degraded

    # Bardi Tuya check
    bardi_creds = tuya_manager.load_tuya_credentials()
    bardi_configured = bool(bardi_creds.get("access_id") and bardi_creds.get("access_secret") and bardi_creds.get("app_uid"))
    bardi_devices = tuya_manager.get_cz_devices()
    bardi_ok = bardi_configured and (len(bardi_devices) > 0)
    
    # WA service check
    wa_status = wa_bridge.get_wa_status()
    wa_ok = wa_status.get("connected", False)
    
    return jsonify({
        "internet": internet_ok,
        "thinq": thinq_ok,
        "thinq_devices": len(lg_manager.get_discovered_devices()),
        "bardi": bardi_ok,
        "bardi_devices": len(bardi_devices),
        "whatsapp": wa_ok,
        "whatsapp_details": wa_status
    })


# -------------------
# mDNS BROADCASTER
# -------------------
def start_mdns_broadcaster(ip, port):
    """Broadcast the service on the local network using mDNS."""
    try:
        hostname = socket.gethostname()
        local_domain = f"{hostname}.local" if not hostname.endswith(".local") else hostname
        
        info = ServiceInfo(
            "_http._tcp.local.",
            f"LG ThinQ Monitoring ({hostname})._http._tcp.local.",
            addresses=[socket.inet_aton(ip)],
            port=port,
            properties={"path": "/"},
            server=f"{local_domain}.",
        )
        
        zeroconf = Zeroconf()
        zeroconf.register_service(info)
        print(f"[mDNS] Meluncurkan broadcast: http://{local_domain}:{port}")
        return zeroconf, info
    except Exception as e:
        print(f"[mDNS] Gagal memulai broadcast: {e}")
        return None, None

# -------------------
# MAIN EXECUTION
# -------------------
def start_parent_watchdog(parent_pid):
    def watchdog_thread():
        print(f"[Watchdog] Memulai pemantauan PID induk: {parent_pid}")
        import ctypes
        import time
        kernel32 = ctypes.windll.kernel32
        PROCESS_QUERY_INFORMATION = 0x0400
        SYNCHRONIZE = 0x00100000
        STILL_ACTIVE = 259
        
        while True:
            handle = kernel32.OpenProcess(PROCESS_QUERY_INFORMATION | SYNCHRONIZE, False, parent_pid)
            if handle == 0:
                print("[Watchdog] Proses induk tidak ditemukan. Mengakhiri python...")
                os._exit(0)
            
            exit_code = ctypes.c_ulong()
            kernel32.GetExitCodeProcess(handle, ctypes.byref(exit_code))
            kernel32.CloseHandle(handle)
            
            if exit_code.value != STILL_ACTIVE:
                print("[Watchdog] Proses induk telah keluar. Mengakhiri python...")
                os._exit(0)
                
            time.sleep(3)
            
    t = threading.Thread(target=watchdog_thread, daemon=True)
    t.start()
                
# -------------------
# MACHINE MANAGEMENT API
# -------------------
@api_app.route('/api/machines', methods=['GET'])
def get_machines_list():
    try:
        machines = database.get_all_machines()
        return jsonify(machines)
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@api_app.route('/api/machines', methods=['POST'])
def save_machine_endpoint():
    try:
        data = request.get_json()
        if not data or not data.get("name") or not data.get("key"):
            return jsonify({"error": "Missing name or key parameters"}), 400
            
        name = data.get("name")
        url = data.get("url", "-")
        key = data.get("key", "cuci")
        machine_id = data.get("id")
        
        success = database.save_machine(name, url, key, machine_id)
        if success:
            lg_manager.reload_devices_from_db()
            return jsonify({"success": True, "message": "Machine saved successfully"})
        return jsonify({"error": "Failed to save machine"}), 500
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@api_app.route('/api/machines/<int:machine_id>', methods=['DELETE'])
def delete_machine_endpoint(machine_id):
    try:
        success = database.delete_machine(machine_id)
        if success:
            lg_manager.reload_devices_from_db()
            return jsonify({"success": True, "message": "Machine deleted successfully"})
        return jsonify({"error": "Failed to delete machine"}), 500
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@api_app.route('/api/thinq/discover', methods=['GET'])
def discover_thinq_endpoint():
    try:
        devices = lg_manager.discover_thinq_devices(force=True)
        return jsonify(devices)
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@api_app.route('/api/machines/reorder', methods=['POST'])
def reorder_machines_endpoint():
    try:
        data = request.get_json()
        if not data or not isinstance(data.get("ids"), list):
            return jsonify({"error": "Missing or invalid ids parameter"}), 400
            
        ids = data.get("ids")
        success = database.reorder_machines(ids)
        if success:
            lg_manager.reload_devices_from_db()
            return jsonify({"success": True, "message": "Machines reordered successfully"})
        return jsonify({"error": "Failed to reorder machines"}), 500
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@api_app.route('/api/tuya/settings', methods=['GET', 'POST'])
def api_tuya_settings():
    """Get or save Tuya API configuration credentials."""
    if request.method == 'POST':
        try:
            data = request.get_json() or {}
            access_id = data.get("access_id", "").strip()
            access_secret = data.get("access_secret", "").strip()
            app_uid = data.get("app_uid", "").strip()
            endpoint = data.get("endpoint", "https://openapi.tuyaus.com").strip()
            
            # Save into config.json
            config = lg_manager.load_lg_config()
            config["tuya_access_id"] = access_id
            config["tuya_access_secret"] = access_secret
            config["tuya_app_uid"] = app_uid
            config["tuya_endpoint"] = endpoint
            lg_manager.save_lg_config(config)
            
            # Update devices.json api_credentials block
            creds = {
                "access_id": access_id,
                "access_secret": access_secret,
                "app_uid": app_uid
            }
            devices_list = tuya_manager.load_devices_list()
            tuya_manager.save_tuya_devices_list(creds, devices_list)
            
            return jsonify({"success": True, "message": "Tuya settings saved successfully"})
        except Exception as e:
            return jsonify({"success": False, "error": str(e)}), 500
            
    # GET - return current credentials
    creds = tuya_manager.load_tuya_credentials()
    return jsonify({
        "success": True,
        "access_id": creds.get("access_id") or "",
        "access_secret": creds.get("access_secret") or "",
        "app_uid": creds.get("app_uid") or "",
        "endpoint": creds.get("endpoint") or "https://openapi.tuyaus.com"
    })

@api_app.route('/api/tuya/sync-keys', methods=['POST'])
def sync_tuya_keys():
    """
    Bridge to fetch Bardi/Tuya devices from Tuya Cloud API
    and automatically register category 'cz' devices.
    """
    try:
        data = request.get_json() or {}
        access_id = data.get("access_id")
        access_secret = data.get("access_secret")
        app_uid = data.get("app_uid")
        endpoint = data.get("endpoint", "https://openapi.tuyaus.com")
        
        if not (access_id and access_secret and app_uid):
            return jsonify({"success": False, "error": "Missing access_id, access_secret, or app_uid"}), 400
            
        res = tuya_manager.sync_tuya_keys(access_id, access_secret, app_uid, endpoint)
        if res.get("success"):
            return jsonify({
                "success": True,
                "total_devices": len(res.get("devices", [])),
                "devices": res.get("devices", [])
            })
        else:
            return jsonify({"success": False, "error": res.get("error")}), 400
    except Exception as e:
        import traceback
        return jsonify({"success": False, "error": str(e), "traceback": traceback.format_exc()}), 500

@api_app.route('/api/tuya/devices')
def tuya_devices():
    """
    Returns list of synced Tuya/Bardi devices
    """
    devices = tuya_manager.get_cz_devices()
    return jsonify({"devices": devices})

if __name__ == "__main__":
    print("\n>>> SMART LAUNDRY v2.0 (MONITORING-ONLY + WA) <<<\n")
    
    import sys
    import os
    print(f"[Debug] sys.executable: {sys.executable}")
    print(f"[Debug] __file__: {__file__}")
    print(f"[Debug] cwd: {os.getcwd()}")
    import config
    print(f"[Debug] config.CONFIG_JSON_PATH: {config.CONFIG_JSON_PATH}")
    import lg_manager
    print(f"[Debug] lg_manager.CONFIG_JSON_PATH: {lg_manager.CONFIG_JSON_PATH}")
    parent_pid = None
    for i in range(len(sys.argv)):
        if sys.argv[i] == '--parent-pid' and i + 1 < len(sys.argv):
            try:
                parent_pid = int(sys.argv[i+1])
            except ValueError:
                pass
            break
            
    if parent_pid:
        start_parent_watchdog(parent_pid)

    database.init_db()
    
    # Load WA config
    wa_bridge.load_wa_config()
    
    # Start LG ThinQ polling
    lg_manager.start_lg_thread()
    
    # Resume active timers from database
    machine_manager.resume_active_timers()
    
    # Start WA outbox processor
    wa_bridge.process_outbox()
    
    local_hostname = socket.gethostname()
    display_host = f"{local_hostname}.local" if not local_hostname.endswith(".local") else local_hostname

    # Auto-detect IP jika LOCAL_ADDRESS kosong
    if LOCAL_ADDRESS:
        local_ip = LOCAL_ADDRESS
    else:
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            local_ip = s.getsockname()[0]
            s.close()
        except Exception:
            local_ip = "127.0.0.1"

    print(f"[App] Dashboard: http://127.0.0.1:{DASHBOARD_PORT} (Hanya dapat diakses dari PC Lokal)")
    print(f"[App] API:       http://127.0.0.1:{API_PORT} (Hanya dapat diakses dari PC Lokal)")

    # Start mDNS Broadcaster (Disabled for local-only security)
    zc, zc_info = None, None

    if waitress_serve:
        threading.Thread(target=lambda: waitress_serve(api_app, host=HOST, port=API_PORT, threads=WORKER_THREADS), daemon=True).start()
        waitress_serve(app, host=HOST, port=DASHBOARD_PORT, threads=WORKER_THREADS)
    else:
        threading.Thread(target=lambda: api_app.run(host=HOST, port=API_PORT, debug=False, use_reloader=False, threaded=True), daemon=True).start()
        app.run(host=HOST, debug=DEBUG, use_reloader=DEBUG, port=DASHBOARD_PORT, threaded=True)
