import sqlite3
import datetime
import os
from config import DB_PATH
import base64

_key = "AzimaSecretKey2026"

def encrypt_val(val):
    if not val:
        return val
    val_str = str(val)
    if val_str.strip() == "":
        return val_str
    val_bytes = val_str.encode('utf-8')
    key_bytes = _key.encode('utf-8')
    key_len = len(key_bytes)
    xor_bytes = bytearray(val_bytes[i] ^ key_bytes[i % key_len] for i in range(len(val_bytes)))
    return base64.b64encode(xor_bytes).decode('utf-8')

def decrypt_val(val):
    if not val:
        return val
    val_str = str(val)
    if val_str.strip() == "":
        return val_str
    try:
        xor_bytes = base64.b64decode(val_str.encode('utf-8'))
        key_bytes = _key.encode('utf-8')
        key_len = len(key_bytes)
        decrypted_bytes = bytearray(xor_bytes[i] ^ key_bytes[i % key_len] for i in range(len(xor_bytes)))
        return decrypted_bytes.decode('utf-8')
    except Exception:
        return val_str

def init_db():
    """Inisialisasi database dan buat tabel jika belum ada"""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS usage_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            entity_id TEXT NOT NULL,
            short_name TEXT NOT NULL,
            action TEXT NOT NULL,
            source TEXT DEFAULT 'customer',
            timestamp DATETIME NOT NULL
        )
    ''')
    # Machine completion logs table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS machine_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            machine TEXT NOT NULL,
            completed_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    # Active timers table (for persistence across restarts)
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS active_timers (
            entity_id TEXT PRIMARY KEY,
            end_time DATETIME NOT NULL,
            started_at DATETIME NOT NULL,
            last_saved_time DATETIME,
            last_remain_seconds INTEGER,
            source TEXT DEFAULT 'customer',
            duration_minutes INTEGER DEFAULT 5,
            customer_name TEXT,
            customer_phone TEXT,
            is_running INTEGER DEFAULT 0,
            run_state TEXT DEFAULT 'Idle',
            wa_start_sent INTEGER DEFAULT 0,
            wa_completion_sent INTEGER DEFAULT 0
        )
    ''')
    # WhatsApp outbox table (offline queue for pending messages)
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS wa_outbox (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            phone TEXT NOT NULL,
            message TEXT NOT NULL,
            status TEXT DEFAULT 'pending',
            retry_count INTEGER DEFAULT 0,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            sent_at DATETIME
        )
    ''')
    # WhatsApp sent log (deduplication)
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS wa_sent_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            machine TEXT NOT NULL,
            event_type TEXT NOT NULL,
            phone TEXT NOT NULL,
            sent_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    # Add source column to existing tables if not present
    try:
        cursor.execute("ALTER TABLE usage_logs ADD COLUMN source TEXT DEFAULT 'customer'")
        conn.commit()
    except sqlite3.OperationalError:
        pass  # Column already exists
    # Add columns to active_timers if not present (automatic migration)
    timer_columns = [
        'customer_name TEXT',
        'customer_phone TEXT',
        'last_saved_time DATETIME',
        'last_remain_seconds INTEGER',
        'is_running INTEGER DEFAULT 0',
        'run_state TEXT DEFAULT "Idle"',
        'wa_start_sent INTEGER DEFAULT 0',
        'wa_completion_sent INTEGER DEFAULT 0'
    ]
    for col in timer_columns:
        try:
            cursor.execute(f"ALTER TABLE active_timers ADD COLUMN {col}")
            conn.commit()
        except sqlite3.OperationalError:
            pass  # Column already exists
            
    # Create machines table if not present
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS machines (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT UNIQUE NOT NULL,
            url TEXT NOT NULL,
            key TEXT NOT NULL,
            sort_order INTEGER DEFAULT 0,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    conn.commit()

    # Alter table if already exists to add sort_order
    try:
        cursor.execute("ALTER TABLE machines ADD COLUMN sort_order INTEGER DEFAULT 0")
        conn.commit()
    except sqlite3.OperationalError:
        pass

    # Seed default machines if table is empty
    cursor.execute("SELECT COUNT(*) FROM machines")
    count = cursor.fetchone()[0]
    if count == 0:
        default_machines = [
            ("Mesin Cuci 1", "Mesin_Cuci_1", "cuci"),
            ("Mesin Cuci 2", "Mesin_Cuci_2", "cuci"),
            ("Mesin Cuci 3", "Mesin_Cuci_3", "cuci"),
            ("Mesin Cuci 4", "Mesin_Cuci_4", "cuci"),
            ("Mesin Cuci 5", "Mesin_Cuci_5", "cuci"),
        ]
        cursor.executemany(
            "INSERT INTO machines (name, url, key) VALUES (?, ?, ?)",
            default_machines
        )
        conn.commit()

    conn.close()
    print(f"[DB] Database initialized at {DB_PATH}")


def log_usage(entity_id, action, source='customer'):
    """Simpan log penggunaan ke database
    
    Args:
        entity_id: ID entitas mesin
        action: Aksi yang dilakukan (ON/OFF/ERROR)
        source: Sumber aksi ('customer' atau 'admin')
    """
    try:
        short_name = entity_id.split('.', 1)[1] if '.' in entity_id else entity_id
        timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute('''
            INSERT INTO usage_logs (entity_id, short_name, action, source, timestamp)
            VALUES (?, ?, ?, ?, ?)
        ''', (entity_id, short_name, action.upper(), source, timestamp))
        conn.commit()
        conn.close()
        print(f"[DB] Log saved: {short_name} -> {action.upper()} (source: {source})")
    except Exception as e:
        print(f"[DB] Error saving log: {e}")

def get_recent_logs(limit=100, machine=None, action=None, date=None, source=None):
    """Ambil log terbaru dengan filter opsional"""
    try:
        conn = sqlite3.connect(DB_PATH)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        
        query = 'SELECT * FROM usage_logs WHERE 1=1'
        params = []
        
        if machine and machine != 'all':
            query += ' AND (short_name = ? OR entity_id = ?)'
            params.extend([machine, machine])
            
        if action and action != 'all':
            query += ' AND action = ?'
            params.append(action.upper())
            
        if source and source != 'all':
            query += ' AND source = ?'
            params.append(source.lower())
            
        if date:
            # Match date part of the timestamp (YYYY-MM-DD)
            query += ' AND date(timestamp) = ?'
            params.append(date)
            
        query += ' ORDER BY timestamp DESC LIMIT ?'
        params.append(limit)
        
        cursor.execute(query, params)
        rows = cursor.fetchall()
        # Convert to a list of dicts to be serializable and clean
        logs = [dict(row) for row in rows]
        conn.close()
        return logs
    except Exception as e:
        print(f"[DB] Error fetching logs: {e}")
        return []

def get_daily_stats():
    """Mengambil jumlah penggunaan harian untuk 30 hari terakhir (aksi ON saja)"""
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        # Mengambil tanggal dan jumlah ON untuk 30 hari terakhir
        query = '''
            SELECT date(timestamp) as day, COUNT(*) as count 
            FROM usage_logs 
            WHERE action = 'ON' AND date(timestamp) >= date('now', 'localtime', '-29 days')
            GROUP BY day
            ORDER BY day ASC
        '''
        cursor.execute(query)
        stats = cursor.fetchall()
        conn.close()
        return stats
    except Exception as e:
        print(f"[DB] Error fetching daily stats: {e}")
        return []

def get_machine_usage_stats():
    """Mengambil total penggunaan per mesin (aksi ON saja)"""
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        query = '''
            SELECT short_name, COUNT(*) as count 
            FROM usage_logs 
            WHERE action = 'ON'
            GROUP BY short_name
            ORDER BY count DESC
        '''
        cursor.execute(query)
        stats = cursor.fetchall()
        conn.close()
        return stats
    except Exception as e:
        print(f"[DB] Error fetching machine usage stats: {e}")
        return []

# ----------------------
# MACHINE COMPLETION LOGS
# ----------------------

def log_machine_completion(machine):
    """Log a machine completion event."""
    try:
        timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute('''
            INSERT INTO machine_logs (machine, completed_at, created_at)
            VALUES (?, ?, ?)
        ''', (machine, timestamp, timestamp))
        conn.commit()
        conn.close()
        print(f"[DB] Machine log saved: {machine} completed at {timestamp}")
    except Exception as e:
        print(f"[DB] Error saving machine log: {e}")

def get_machine_logs(limit=100, machine=None, date=None, month=None):
    """Get machine completion logs with optional filters."""
    try:
        conn = sqlite3.connect(DB_PATH)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        
        query = 'SELECT * FROM machine_logs WHERE 1=1'
        params = []
        
        if machine and machine != 'all':
            query += ' AND machine = ?'
            params.append(machine)
            
        if date:
            query += ' AND date(completed_at) = ?'
            params.append(date)
            
        if month:
            # month format: YYYY-MM
            query += " AND strftime('%Y-%m', completed_at) = ?"
            params.append(month)
            
        query += ' ORDER BY completed_at DESC LIMIT ?'
        params.append(limit)
        
        cursor.execute(query, params)
        rows = cursor.fetchall()
        logs = [dict(row) for row in rows]
        conn.close()
        return logs
    except Exception as e:
        print(f"[DB] Error fetching machine logs: {e}")
        return []

def get_machine_log_stats(machine=None, date=None):
    """Get machine log statistics with optional machine and date filter."""
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        
        # Base date for calculations (defaults to today)
        ref_date = f"'{date}'" if date else "date('now', 'localtime')"
        ref_month = f"strftime('%Y-%m', '{date}')" if date else "strftime('%Y-%m', 'now', 'localtime')"
        
        # Build machine filter
        machine_filter = ""
        params = []
        if machine and machine != 'all':
            machine_filter = " AND machine = ?"
            params = [machine]
        
        # Today / Selected Date count
        cursor.execute(f'''
            SELECT COUNT(*) FROM machine_logs 
            WHERE date(completed_at) = {ref_date}{machine_filter}
        ''', params)
        today = cursor.fetchone()[0]
        
        # Weekly count relative to ref_date
        cursor.execute(f'''
            SELECT COUNT(*) FROM machine_logs 
            WHERE date(completed_at) >= date({ref_date}, 'weekday 0', '-7 days')
            AND date(completed_at) <= date({ref_date}, 'weekday 0', '-1 day'){machine_filter}
        ''', params)
        week = cursor.fetchone()[0]
        
        # Monthly count relative to ref_date
        cursor.execute(f'''
            SELECT COUNT(*) FROM machine_logs 
            WHERE strftime('%Y-%m', completed_at) = {ref_month}{machine_filter}
        ''', params)
        month = cursor.fetchone()[0]
        
        # Per machine count (always relative to ref_date / month if needed, but usually overall for the selected period)
        by_machine = {}
        if not machine or machine == 'all':
            cursor.execute(f'''
                SELECT machine, COUNT(*) as count FROM machine_logs 
                WHERE date(completed_at) = {ref_date}
                GROUP BY machine ORDER BY count DESC
            ''')
            by_machine = dict(cursor.fetchall())
        
        conn.close()
        return {
            "today": today,
            "week": week,
            "month": month,
            "by_machine": by_machine
        }
    except Exception as e:
        print(f"[DB] Error fetching machine log stats: {e}")
        return {"today": 0, "week": 0, "month": 0, "by_machine": {}}

# ----------------------
# ACTIVE TIMERS (Persistence & Checkpoint Recovery)
# ----------------------

def save_active_timer(entity_id, end_time, source='customer', duration_minutes=5,
                      customer_name=None, customer_phone=None, last_remain_seconds=None,
                      is_running=0, run_state="Idle", wa_start_sent=0, wa_completion_sent=0,
                      started_at=None):
    """Save an active timer to database with full state checkpointing for persistence across restarts.

    Args:
        entity_id: Machine entity ID
        end_time: datetime object when the timer should end
        source: 'customer' or 'admin'
        duration_minutes: Original duration in minutes (for display)
        customer_name: Customer name (for WA notifications)
        customer_phone: Customer phone number (for WA notifications)
        last_remain_seconds: Current remaining seconds recorded (state menit/detik)
        is_running: 1 if running/offline run cycle, 0 if booking/idle
        run_state: Machine state description (e.g. 'Running (Offline)', 'Washing')
        wa_start_sent: 1 if start WA was sent
        wa_completion_sent: 1 if completion WA was sent
        started_at: Custom start timestamp or current datetime
    """
    try:
        now_dt = datetime.datetime.now()
        started_at_str = started_at if started_at else now_dt.strftime("%Y-%m-%d %H:%M:%S")
        last_saved_time_str = now_dt.strftime("%Y-%m-%d %H:%M:%S")
        end_time_str = end_time.strftime("%Y-%m-%d %H:%M:%S") if isinstance(end_time, datetime.datetime) else str(end_time)

        if last_remain_seconds is None and isinstance(end_time, datetime.datetime):
            last_remain_seconds = max(0, int((end_time - now_dt).total_seconds()))
        elif last_remain_seconds is None:
            last_remain_seconds = duration_minutes * 60

        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute('''
            INSERT OR REPLACE INTO active_timers (
                entity_id, end_time, started_at, last_saved_time, last_remain_seconds,
                source, duration_minutes, customer_name, customer_phone,
                is_running, run_state, wa_start_sent, wa_completion_sent
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            entity_id, end_time_str, started_at_str, last_saved_time_str, int(last_remain_seconds),
            source, duration_minutes, encrypt_val(customer_name), encrypt_val(customer_phone),
            1 if is_running else 0, run_state, 1 if wa_start_sent else 0, 1 if wa_completion_sent else 0
        ))
        conn.commit()
        conn.close()
        print(f"[DB] Active timer saved: {entity_id} -> {last_saved_time_str} (ends: {end_time_str}, remain: {last_remain_seconds}s, state: {run_state}, running: {is_running}, cust: {customer_name})")
    except Exception as e:
        print(f"[DB] Error saving active timer: {e}")

def update_active_timer_checkpoint(entity_id, remain_seconds, run_state=None, is_running=None,
                                   wa_start_sent=None, wa_completion_sent=None, end_time=None):
    """Fast periodic checkpoint of remaining time and timestamp to SQLite database."""
    try:
        now_str = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()

        updates = ["last_saved_time = ?", "last_remain_seconds = ?"]
        params = [now_str, max(0, int(remain_seconds))]

        if run_state is not None:
            updates.append("run_state = ?")
            params.append(str(run_state))
        if is_running is not None:
            updates.append("is_running = ?")
            params.append(1 if is_running else 0)
        if wa_start_sent is not None:
            updates.append("wa_start_sent = ?")
            params.append(1 if wa_start_sent else 0)
        if wa_completion_sent is not None:
            updates.append("wa_completion_sent = ?")
            params.append(1 if wa_completion_sent else 0)
        if end_time is not None:
            end_time_str = end_time.strftime("%Y-%m-%d %H:%M:%S") if isinstance(end_time, datetime.datetime) else str(end_time)
            updates.append("end_time = ?")
            params.append(end_time_str)

        params.append(entity_id)
        query = f"UPDATE active_timers SET {', '.join(updates)} WHERE entity_id = ?"
        cursor.execute(query, params)
        conn.commit()
        conn.close()
    except Exception as e:
        print(f"[DB] Error updating active timer checkpoint for {entity_id}: {e}")

def get_active_timer(entity_id):
    """Get active timer for a specific entity.

    Returns:
        dict with timer and customer fields or None if not found
    """
    try:
        conn = sqlite3.connect(DB_PATH)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        cursor.execute('SELECT * FROM active_timers WHERE entity_id = ?', (entity_id,))
        row = cursor.fetchone()
        conn.close()
        if row:
            d = dict(row)
            d["customer_name"] = decrypt_val(d.get("customer_name"))
            d["customer_phone"] = decrypt_val(d.get("customer_phone"))
            return d
        return None
    except Exception as e:
        print(f"[DB] Error getting active timer: {e}")
        return None

def get_all_active_timers():
    """Get all active timers from database.

    Returns:
        list of dicts with all timer fields
    """
    try:
        conn = sqlite3.connect(DB_PATH)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        cursor.execute('SELECT * FROM active_timers')
        rows = cursor.fetchall()
        conn.close()
        res = []
        for row in rows:
            d = dict(row)
            d["customer_name"] = decrypt_val(d.get("customer_name"))
            d["customer_phone"] = decrypt_val(d.get("customer_phone"))
            res.append(d)
        return res
    except Exception as e:
        print(f"[DB] Error getting all active timers: {e}")
        return []
        return []

def remove_active_timer(entity_id):
    """Remove an active timer from database (called when timer ends or machine is stopped).
    
    Args:
        entity_id: Machine entity ID
    """
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute('DELETE FROM active_timers WHERE entity_id = ?', (entity_id,))
        conn.commit()
        conn.close()
        print(f"[DB] Active timer removed: {entity_id}")
    except Exception as e:
        print(f"[DB] Error removing active timer: {e}")

def get_customer_for_machine(entity_id):
    """Get customer name and phone for an active machine timer.
    
    Returns:
        tuple (customer_name, customer_phone) or (None, None)
    """
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute('SELECT customer_name, customer_phone FROM active_timers WHERE entity_id = ?', (entity_id,))
        row = cursor.fetchone()
        conn.close()
        if row:
            return decrypt_val(row[0]), decrypt_val(row[1])
        return None, None
    except Exception as e:
        print(f"[DB] Error getting customer for machine: {e}")
        return None, None

# ----------------------
# WHATSAPP OUTBOX
# ----------------------

def save_wa_outbox(phone, message):
    """Save a pending WA message to outbox for later retry."""
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute('''
            INSERT INTO wa_outbox (phone, message, status, created_at)
            VALUES (?, ?, 'pending', ?)
        ''', (encrypt_val(phone), encrypt_val(message), datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")))
        conn.commit()
        conn.close()
        print(f"[DB] WA outbox saved: {phone}")
    except Exception as e:
        print(f"[DB] Error saving WA outbox: {e}")

def get_pending_wa_outbox(limit=10):
    """Get pending WA messages from outbox."""
    try:
        conn = sqlite3.connect(DB_PATH)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        cursor.execute('''
            SELECT * FROM wa_outbox 
            WHERE status = 'pending' AND retry_count < 5
            ORDER BY created_at ASC LIMIT ?
        ''', (limit,))
        rows = cursor.fetchall()
        conn.close()
        res = []
        for row in rows:
            d = dict(row)
            d["phone"] = decrypt_val(d.get("phone"))
            d["message"] = decrypt_val(d.get("message"))
            res.append(d)
        return res
    except Exception as e:
        print(f"[DB] Error getting pending WA outbox: {e}")
        return []

def mark_wa_outbox_sent(outbox_id):
    """Mark a WA outbox message as sent."""
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute('''
            UPDATE wa_outbox SET status = 'sent', sent_at = ? WHERE id = ?
        ''', (datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"), outbox_id))
        conn.commit()
        conn.close()
    except Exception as e:
        print(f"[DB] Error marking WA outbox sent: {e}")

def mark_wa_outbox_failed(outbox_id):
    """Mark a WA outbox message as failed/expired."""
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute('''
            UPDATE wa_outbox SET status = 'failed' WHERE id = ?
        ''', (outbox_id,))
        conn.commit()
        conn.close()
    except Exception as e:
        print(f"[DB] Error marking WA outbox failed: {e}")

def increment_wa_outbox_retry(outbox_id):
    """Increment retry count for a failed WA outbox message."""
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute('UPDATE wa_outbox SET retry_count = retry_count + 1 WHERE id = ?', (outbox_id,))
        conn.commit()
        conn.close()
    except Exception as e:
        print(f"[DB] Error incrementing WA outbox retry: {e}")

# ----------------------
# WHATSAPP SENT LOG (Deduplication)
# ----------------------

def log_wa_sent(machine, event_type, phone):
    """Log a successfully sent WA message for deduplication."""
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute('''
            INSERT INTO wa_sent_log (machine, event_type, phone, sent_at)
            VALUES (?, ?, ?, ?)
        ''', (machine, event_type, encrypt_val(phone), datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")))
        conn.commit()
        conn.close()
    except Exception as e:
        print(f"[DB] Error logging WA sent: {e}")

def has_wa_been_sent(machine, event_type, phone, cooldown_seconds=300):
    """Check if a WA message of this type was already sent recently.
    
    Returns True if a matching message was sent within cooldown_seconds.
    """
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cutoff = (datetime.datetime.now() - datetime.timedelta(seconds=cooldown_seconds)).strftime("%Y-%m-%d %H:%M:%S")
        cursor.execute('''
            SELECT COUNT(*) FROM wa_sent_log 
            WHERE machine = ? AND event_type = ? AND phone = ? AND sent_at > ?
        ''', (machine, event_type, encrypt_val(phone), cutoff))
        count = cursor.fetchone()[0]
        conn.close()
        return count > 0
    except Exception as e:
        print(f"[DB] Error checking WA sent log: {e}")
        return False


def has_phone_received_event_recently(phone, event_type, cooldown_seconds=3600):
    """Check if this phone number has received a WA message of this event_type within cooldown_seconds."""
    try:
        import wa_bridge
        normalized_phone = wa_bridge._normalize_phone(phone)
        if not normalized_phone:
            return False
            
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cutoff = (datetime.datetime.now() - datetime.timedelta(seconds=cooldown_seconds)).strftime("%Y-%m-%d %H:%M:%S")
        cursor.execute('''
            SELECT COUNT(*) FROM wa_sent_log 
            WHERE event_type = ? AND phone = ? AND sent_at > ?
        ''', (event_type, encrypt_val(normalized_phone), cutoff))
        count = cursor.fetchone()[0]
        conn.close()
        return count > 0
    except Exception as e:
        print(f"[DB] Error checking recent phone WA: {e}")
        return False

def get_all_machines():
    """Ambil semua daftar mesin dari tabel machines, diurutkan berdasarkan sort_order"""
    try:
        conn = sqlite3.connect(DB_PATH)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        cursor.execute("SELECT * FROM machines ORDER BY sort_order ASC, id ASC")
        rows = cursor.fetchall()
        conn.close()
        return [dict(r) for r in rows]
    except Exception as e:
        print(f"[DB] Error fetching machines: {e}")
        return []

def save_machine(name, url, key, machine_id=None):
    """Simpan atau perbarui mesin"""
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        created_at = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        
        if machine_id:
            cursor.execute(
                "UPDATE machines SET name = ?, url = ?, key = ? WHERE id = ?",
                (name, url, key, machine_id)
            )
        else:
            # Cek apakah mesin dengan nama yang sama sudah ada
            cursor.execute("SELECT id FROM machines WHERE name = ?", (name,))
            row = cursor.fetchone()
            if row:
                cursor.execute(
                    "UPDATE machines SET url = ?, key = ? WHERE name = ?",
                    (url, key, name)
                )
            else:
                cursor.execute(
                    "INSERT INTO machines (name, url, key, created_at) VALUES (?, ?, ?, ?)",
                    (name, url, key, created_at)
                )
        conn.commit()
        conn.close()
        return True
    except Exception as e:
        print(f"[DB] Error saving machine: {e}")
        return False

def delete_machine(machine_id):
    """Hapus mesin berdasarkan ID"""
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute("DELETE FROM machines WHERE id = ?", (machine_id,))
        conn.commit()
        conn.close()
        return True
    except Exception as e:
        print(f"[DB] Error deleting machine: {e}")
        return False

def reorder_machines(ids_list):
    """Pembaruan massal sort_order berdasarkan daftar ID yang diurutkan"""
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        for index, machine_id in enumerate(ids_list):
            cursor.execute(
                "UPDATE machines SET sort_order = ? WHERE id = ?",
                (index, machine_id)
            )
        conn.commit()
        conn.close()
        return True
    except Exception as e:
        print(f"[DB] Error reordering machines: {e}")
        return False

def get_current_wash_sequence(phone, name):
    """Retrieve the current sequence number of the wash/dry cycle for this customer."""
    try:
        def _normalize_phone_helper(p):
            if not p:
                return None
            p = str(p).strip().replace("+", "").replace("-", "").replace(" ", "")
            if p.startswith("0"):
                p = "62" + p[1:]
            if not p.startswith("62"):
                p = "62" + p
            return p

        normalized_phone = _normalize_phone_helper(phone) if phone else None
        
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        
        # Get active orders
        cursor.execute("SELECT id, customer_phone, customer_name FROM orders WHERE LOWER(status) != 'completed'")
        orders = cursor.fetchall()
        
        active_order_id = None
        for oid, ophone, oname in orders:
            dec_ophone = decrypt_val(ophone)
            dec_oname = decrypt_val(oname)
            if dec_ophone and normalized_phone:
                if _normalize_phone_helper(dec_ophone) == normalized_phone:
                    active_order_id = oid
                    break
            if dec_oname and name and not normalized_phone:
                if dec_oname.strip().lower() == name.strip().lower() and name.strip().lower() not in ("pelanggan", "guest", "", "-"):
                    active_order_id = oid
                    break
                    
        if not active_order_id:
            conn.close()
            return 1
            
        # Count current runs in history
        cursor.execute("SELECT COUNT(*) FROM machine_usage_history WHERE order_id = ?", (active_order_id,))
        current_runs = cursor.fetchone()[0]
        
        conn.close()
        return max(1, current_runs)
    except Exception as e:
        print(f"[DB] Error getting current wash sequence: {e}")
        return 1
