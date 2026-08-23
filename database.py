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

def get_db_connection(row_factory=False):
    """Get thread-safe, high-concurrency SQLite connection with 30s busy timeout and WAL mode."""
    conn = sqlite3.connect(DB_PATH, timeout=30.0)
    try:
        conn.execute("PRAGMA busy_timeout = 30000")
        conn.execute("PRAGMA journal_mode = WAL")
        conn.execute("PRAGMA synchronous = NORMAL")
    except Exception:
        pass
    if row_factory:
        conn.row_factory = sqlite3.Row
    return conn

def init_db():
    """Inisialisasi database dan buat tabel jika belum ada"""
    conn = get_db_connection()
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
    # Users table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT NOT NULL UNIQUE,
            password TEXT NOT NULL,
            role TEXT NOT NULL,
            is_active INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    # Orders table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS orders (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            customer_name TEXT NOT NULL,
            customer_phone TEXT,
            order_date TEXT NOT NULL,
            total_amount INTEGER NOT NULL,
            status TEXT NOT NULL,
            user_id INTEGER NOT NULL,
            is_paid INTEGER NOT NULL DEFAULT 0,
            paid_amount INTEGER NOT NULL DEFAULT 0,
            payment_method TEXT NOT NULL DEFAULT 'cash',
            qris_url TEXT,
            qris_id TEXT,
            payment_timestamp TEXT,
            assigned_machine_id INTEGER,
            machine_started_at TEXT
        )
    ''')
    # Order items table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS order_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            order_id INTEGER NOT NULL,
            item_id INTEGER NOT NULL,
            item_name TEXT NOT NULL,
            quantity INTEGER NOT NULL,
            price INTEGER NOT NULL,
            note TEXT,
            FOREIGN KEY (order_id) REFERENCES orders (id),
            FOREIGN KEY (item_id) REFERENCES transactions (id)
        )
    ''')
    # Product / Service Catalog (transactions)
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS transactions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            nama TEXT NOT NULL,
            harga INTEGER NOT NULL,
            stock INTEGER,
            is_unlimited_stock INTEGER NOT NULL DEFAULT 0,
            is_staff_restockable INTEGER NOT NULL DEFAULT 0,
            type INTEGER NOT NULL DEFAULT 0,
            machine_type TEXT,
            machine_id INTEGER,
            parent_id INTEGER,
            is_used INTEGER NOT NULL DEFAULT 0,
            duration_days INTEGER DEFAULT 0,
            created_at TEXT NOT NULL
        )
    ''')
    # Expenses table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS expenses (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            amount INTEGER NOT NULL,
            date TEXT NOT NULL,
            created_at TEXT NOT NULL
        )
    ''')
    # Customers table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS customers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            phone TEXT,
            address TEXT,
            created_at TEXT NOT NULL
        )
    ''')
    # Machine usage history
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS machine_usage_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            order_id INTEGER NOT NULL,
            machine_id INTEGER NOT NULL,
            machine_name TEXT NOT NULL,
            customer_name TEXT,
            status TEXT NOT NULL,
            error_message TEXT,
            started_at TEXT NOT NULL,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (order_id) REFERENCES orders (id)
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

        conn = get_db_connection()
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
        conn = get_db_connection(row_factory=True)
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
        conn = get_db_connection()
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
        conn = get_db_connection()
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
        conn = get_db_connection()
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
        conn = get_db_connection(row_factory=True)
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
        conn = get_db_connection()
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

        conn = get_db_connection()
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
        conn = get_db_connection()
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
        conn = get_db_connection(row_factory=True)
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
        conn = get_db_connection(row_factory=True)
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

def remove_active_timer(entity_id):
    """Remove an active timer from database (called when timer ends or machine is stopped).

    Args:
        entity_id: Machine entity ID
    """
    try:
        conn = get_db_connection()
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
        conn = get_db_connection()
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
        conn = get_db_connection()
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
        conn = get_db_connection(row_factory=True)
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
        conn = get_db_connection()
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
        conn = get_db_connection()
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
        conn = get_db_connection()
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
        conn = get_db_connection()
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
        conn = get_db_connection()
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

        conn = get_db_connection()
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
        conn = get_db_connection(row_factory=True)
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
        conn = get_db_connection()
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
        conn = get_db_connection()
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
        conn = get_db_connection()
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

        conn = get_db_connection()
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

# ----------------------
# SECURE AUTHENTICATION & USER MANAGEMENT
# ----------------------
import hashlib
import secrets
import hmac
import math

def hash_password(password):
    """Hash password using PBKDF2-HMAC-SHA256 with a unique random salt."""
    if not password:
        return ""
    salt = secrets.token_hex(16)
    iterations = 100000
    hash_bytes = hashlib.pbkdf2_hmac('sha256', password.encode('utf-8'), salt.encode('utf-8'), iterations)
    hash_hex = hash_bytes.hex()
    return f"pbkdf2:sha256:{iterations}${salt}${hash_hex}"

def verify_password(stored_password, provided_password):
    """Verify a provided password against stored password (handles PBKDF2 hashes & legacy plain-text).

    Returns:
        tuple (is_valid: bool, needs_upgrade: bool)
    """
    if not stored_password or not provided_password:
        return False, False

    if stored_password.startswith("pbkdf2:sha256:"):
        try:
            parts = stored_password.split("$")
            if len(parts) == 3:
                iter_part, salt, expected_hash = parts
                iterations = int(iter_part.split(":")[2])
                computed_hash = hashlib.pbkdf2_hmac(
                    'sha256', provided_password.encode('utf-8'), salt.encode('utf-8'), iterations
                ).hex()
                return hmac.compare_digest(computed_hash, expected_hash), False
        except Exception as e:
            print(f"[Auth] Error verifying hashed password: {e}")
            return False, False

    # Legacy plain-text fallback (auto-upgrade trigger)
    if stored_password == provided_password:
        return True, True

    return False, False

def generate_auth_token(user_id, username, role, expires_in_days=30):
    """Generate signed authentication token with HMAC-SHA256 signature."""
    now_ts = int(datetime.datetime.now().timestamp())
    exp_ts = now_ts + (expires_in_days * 86400)
    payload_str = f"{user_id}:{username}:{role}:{exp_ts}"
    sig = hmac.new(_key.encode('utf-8'), payload_str.encode('utf-8'), hashlib.sha256).hexdigest()
    raw_token = f"{payload_str}:{sig}"
    return base64.urlsafe_b64encode(raw_token.encode('utf-8')).decode('utf-8')

def verify_auth_token(token_str):
    """Verify signed auth token.

    Returns:
        dict: {"user_id": int, "username": str, "role": str} or None
    """
    if not token_str:
        return None
    try:
        if token_str.startswith("Bearer "):
            token_str = token_str[7:].strip()
        decoded = base64.urlsafe_b64decode(token_str.encode('utf-8')).decode('utf-8')
        parts = decoded.split(":")
        if len(parts) != 5:
            return None
        user_id_str, username, role, exp_ts_str, sig = parts
        payload_str = f"{user_id_str}:{username}:{role}:{exp_ts_str}"
        expected_sig = hmac.new(_key.encode('utf-8'), payload_str.encode('utf-8'), hashlib.sha256).hexdigest()
        if not hmac.compare_digest(sig, expected_sig):
            return None
        if int(exp_ts_str) < int(datetime.datetime.now().timestamp()):
            return None  # Expired
        return {"user_id": int(user_id_str), "username": username, "role": role}
    except Exception as e:
        print(f"[Auth] Error verifying auth token: {e}")
        return None

def verify_user_login(username, password):
    """Authenticate a user, automatic plain-text to hash migration, and generate token."""
    if not username or not password:
        return None, "Username dan password tidak boleh kosong"

    conn = get_db_connection(row_factory=True)
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM users WHERE LOWER(username) = ? AND is_active = 1", (username.strip().lower(),))
    row = cursor.fetchone()

    if not row:
        conn.close()
        return None, "Username atau password salah"

    user_dict = dict(row)
    stored_password = user_dict.get("password", "")
    is_valid, needs_upgrade = verify_password(stored_password, password)

    if not is_valid:
        conn.close()
        return None, "Username atau password salah"

    # Upgrade to hash if legacy plain-text
    if needs_upgrade:
        try:
            new_hash = hash_password(password)
            cursor.execute("UPDATE users SET password = ? WHERE id = ?", (new_hash, user_dict["id"]))
            conn.commit()
            print(f"[Auth] Automatically upgraded legacy password to hash for user: {username}")
        except Exception as e:
            print(f"[Auth] Failed to upgrade password: {e}")

    conn.close()
    token = generate_auth_token(user_dict["id"], user_dict["username"], user_dict["role"])
    return {
        "id": user_dict["id"],
        "username": user_dict["username"],
        "role": user_dict["role"],
        "is_active": user_dict["is_active"] == 1,
        "token": token
    }, None

def check_admin_exists():
    """Check if at least one admin exists in database."""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT COUNT(*) FROM users WHERE role = 'admin' AND is_active = 1")
        count = cursor.fetchone()[0]
        conn.close()
        return count > 0
    except Exception as e:
        print(f"[Auth] Error checking admin: {e}")
        return False

def create_initial_admin(username, password):
    """Create initial admin user during setup wizard."""
    if not username or not password:
        return None, "Username dan password tidak boleh kosong"
    if check_admin_exists():
        return None, "Admin sudah terdaftar"

    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        hashed = hash_password(password)
        created_at = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        cursor.execute('''
            INSERT INTO users (username, password, role, is_active, created_at)
            VALUES (?, ?, 'admin', 1, ?)
        ''', (username.strip(), hashed, created_at))
        conn.commit()
        admin_id = cursor.lastrowid
        conn.close()
        token = generate_auth_token(admin_id, username.strip(), 'admin')
        return {
            "id": admin_id,
            "username": username.strip(),
            "role": "admin",
            "token": token
        }, None
    except Exception as e:
        return None, str(e)

def create_user_account(username, password, role='user'):
    """Create a new user account with hashed password."""
    if not username or not password:
        return None, "Username dan password tidak boleh kosong"
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT id FROM users WHERE LOWER(username) = ?", (username.strip().lower(),))
        if cursor.fetchone():
            conn.close()
            return None, f"Username '{username}' sudah digunakan"

        hashed = hash_password(password)
        created_at = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        cursor.execute('''
            INSERT INTO users (username, password, role, is_active, created_at)
            VALUES (?, ?, ?, 1, ?)
        ''', (username.strip(), hashed, role, created_at))
        conn.commit()
        user_id = cursor.lastrowid
        conn.close()
        return {
            "id": user_id,
            "username": username.strip(),
            "role": role,
            "is_active": True
        }, None
    except Exception as e:
        return None, str(e)

def verify_admin_password(password):
    """Verify if the provided password matches any active admin."""
    if not password:
        return False
    try:
        conn = get_db_connection(row_factory=True)
        cursor = conn.cursor()
        cursor.execute("SELECT * FROM users WHERE role = 'admin' AND is_active = 1")
        admins = cursor.fetchall()
        for admin in admins:
            stored_pwd = admin["password"]
            is_valid, needs_upgrade = verify_password(stored_pwd, password)
            if is_valid:
                if needs_upgrade:
                    try:
                        new_hash = hash_password(password)
                        cursor.execute("UPDATE users SET password = ? WHERE id = ?", (new_hash, admin["id"]))
                        conn.commit()
                    except Exception:
                        pass
                conn.close()
                return True
        conn.close()
        return False
    except Exception as e:
        print(f"[Auth] Error verifying admin password: {e}")
        return False

def change_user_password(user_id, old_password, new_password, is_admin_override=False):
    """Change password for a user with old password verification."""
    if not new_password or len(new_password.strip()) < 4:
        return False, "Password baru minimal 4 karakter"
    try:
        conn = get_db_connection(row_factory=True)
        cursor = conn.cursor()
        cursor.execute("SELECT * FROM users WHERE id = ?", (user_id,))
        row = cursor.fetchone()
        if not row:
            conn.close()
            return False, "User tidak ditemukan"

        if not is_admin_override:
            stored_pwd = row["password"]
            is_valid, _ = verify_password(stored_pwd, old_password)
            if not is_valid:
                conn.close()
                return False, "Password lama salah"

        new_hash = hash_password(new_password)
        cursor.execute("UPDATE users SET password = ? WHERE id = ?", (new_hash, user_id))
        conn.commit()
        conn.close()
        return True, None
    except Exception as e:
        return False, str(e)

def get_all_active_users():
    """Get all active users without exposing passwords."""
    try:
        conn = get_db_connection(row_factory=True)
        cursor = conn.cursor()
        cursor.execute("SELECT id, username, role, is_active, created_at FROM users WHERE is_active = 1 ORDER BY id ASC")
        rows = cursor.fetchall()
        conn.close()
        return [dict(r) for r in rows]
    except Exception as e:
        print(f"[Auth] Error getting users: {e}")
        return []

# ----------------------
# SERVER-SIDE ORDERS & PRICING ENGINE
# ----------------------

def calculate_order_totals(items):
    """Calculate verified subtotal and total for a list of items using catalog in database."""
    if not items:
        return {"total_amount": 0, "items": []}

    conn = get_db_connection(row_factory=True)
    cursor = conn.cursor()

    validated_items = []
    total_amount = 0

    for it in items:
        item_id = int(it.get("item_id", 0))
        qty = float(it.get("quantity", 1))
        note = it.get("note", "")

        cursor.execute("SELECT * FROM transactions WHERE id = ?", (item_id,))
        trx = cursor.fetchone()
        if not trx:
            continue

        item_name = trx["nama"]
        unit_price = int(trx["harga"])
        trx_type = int(trx["type"]) if "type" in trx.keys() else 0

        # Type 2 is iron / gosok (supports fractional weight)
        if trx_type == 2:
            subtotal = int(round(unit_price * qty))
            line_qty = int(math.ceil(qty)) if qty > 0 else 1
        else:
            line_qty = int(qty)
            subtotal = int(unit_price * line_qty)

        total_amount += subtotal
        validated_items.append({
            "item_id": item_id,
            "item_name": item_name,
            "quantity": line_qty,
            "weight": qty if trx_type == 2 else None,
            "price": subtotal,
            "unit_price": unit_price,
            "note": note,
            "duration_days": trx["duration_days"] if "duration_days" in trx.keys() else 0,
            "machine_type": trx["machine_type"] if "machine_type" in trx.keys() else None
        })

    conn.close()
    return {
        "total_amount": total_amount,
        "items": validated_items
    }

def create_order(customer_name, customer_phone, items, user_id=1,
                 payment_method='Tunai / Cash', paid_amount=None, is_paid=None,
                 assigned_machine_id=None, order_date=None):
    """Atomically calculate, validate, and insert a new order and order_items in database."""
    calc = calculate_order_totals(items)
    total_amount = calc["total_amount"]
    validated_items = calc["items"]

    if not customer_name or not customer_name.strip():
        return None, "Nama pelanggan tidak boleh kosong"
    if not validated_items:
        return None, "Order harus memiliki minimal satu item yang valid"

    now_iso = order_date if order_date else datetime.datetime.now().isoformat()

    # Determine payment state
    if paid_amount is None:
        if payment_method in ('Tunai / Cash', 'QRIS Dinamis'):
            paid_amount = total_amount
            is_paid_val = 1
        elif 'DP' in payment_method:
            paid_amount = int(paid_amount or 0)
            is_paid_val = 1 if paid_amount >= total_amount else 0
        else:
            paid_amount = 0
            is_paid_val = 0
    else:
        paid_amount = int(paid_amount)
        is_paid_val = 1 if (is_paid is True or paid_amount >= total_amount) else 0

    payment_timestamp = now_iso if (paid_amount > 0 or is_paid_val == 1) else None

    conn = get_db_connection(row_factory=True)
    cursor = conn.cursor()

    try:
        cursor.execute('''
            INSERT INTO orders (
                customer_name, customer_phone, order_date, total_amount,
                status, user_id, is_paid, paid_amount, payment_method,
                payment_timestamp, assigned_machine_id
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            encrypt_val(customer_name.strip()),
            encrypt_val(customer_phone.strip() if customer_phone else ""),
            now_iso,
            total_amount,
            'Pending',
            user_id,
            is_paid_val,
            paid_amount,
            payment_method,
            payment_timestamp,
            assigned_machine_id
        ))
        order_id = cursor.lastrowid

        # Insert line items & decrement stock
        for it in validated_items:
            cursor.execute('''
                INSERT INTO order_items (order_id, item_id, item_name, quantity, price, note)
                VALUES (?, ?, ?, ?, ?, ?)
            ''', (
                order_id,
                it["item_id"],
                it["item_name"],
                it["quantity"],
                it["price"],
                encrypt_val(it["note"]) if it["note"] else ""
            ))
            # Decrement stock if finite
            cursor.execute('''
                UPDATE transactions
                SET stock = MAX(0, stock - ?)
                WHERE id = ? AND is_unlimited_stock = 0 AND stock IS NOT NULL
            ''', (it["quantity"], it["item_id"]))

        conn.commit()

        result_order = {
            "id": order_id,
            "customer_name": customer_name.strip(),
            "customer_phone": customer_phone.strip() if customer_phone else "",
            "order_date": now_iso,
            "total_amount": total_amount,
            "status": "Pending",
            "user_id": user_id,
            "is_paid": is_paid_val == 1,
            "paid_amount": paid_amount,
            "payment_method": payment_method,
            "payment_timestamp": payment_timestamp,
            "assigned_machine_id": assigned_machine_id,
            "items": validated_items
        }
        conn.close()
        print(f"[DB] Order #{order_id} created successfully for {customer_name} (Total: Rp {total_amount})")
        return result_order, None
    except Exception as e:
        conn.rollback()
        conn.close()
        print(f"[DB] Error creating order: {e}")
        return None, str(e)

def update_order_payment(order_id, paid_amount, payment_method, is_paid=None):
    """Atomically update order payment status."""
    try:
        conn = get_db_connection(row_factory=True)
        cursor = conn.cursor()
        cursor.execute("SELECT * FROM orders WHERE id = ?", (order_id,))
        order = cursor.fetchone()
        if not order:
            conn.close()
            return None, "Order tidak ditemukan"

        total_amount = int(order["total_amount"])
        paid_amount = int(paid_amount)
        is_paid_val = 1 if (is_paid is True or paid_amount >= total_amount) else 0
        now_iso = datetime.datetime.now().isoformat()

        cursor.execute('''
            UPDATE orders
            SET paid_amount = ?, is_paid = ?, payment_method = ?, payment_timestamp = ?
            WHERE id = ?
        ''', (paid_amount, is_paid_val, payment_method, now_iso, order_id))
        conn.commit()
        conn.close()
        return {
            "id": order_id,
            "paid_amount": paid_amount,
            "is_paid": is_paid_val == 1,
            "payment_method": payment_method,
            "payment_timestamp": now_iso
        }, None
    except Exception as e:
        return None, str(e)

# ----------------------
# EXPENSES & LEDGER (BUKU BESAR) ENGINE
# ----------------------

def create_expense(name, amount, date_str=None):
    """Create a new operational expense."""
    if not name or not name.strip():
        return None, "Nama pengeluaran tidak boleh kosong"
    try:
        amount_int = int(amount)
        if amount_int <= 0:
            return None, "Nominal pengeluaran harus lebih besar dari 0"
    except Exception:
        return None, "Nominal pengeluaran tidak valid"

    now = datetime.datetime.now()
    date_val = date_str if date_str else now.strftime("%Y-%m-%d")
    created_at_val = now.isoformat()

    conn = get_db_connection()
    cursor = conn.cursor()
    try:
        cursor.execute('''
            INSERT INTO expenses (name, amount, date, created_at)
            VALUES (?, ?, ?, ?)
        ''', (name.strip(), amount_int, date_val, created_at_val))
        conn.commit()
        expense_id = cursor.lastrowid
        conn.close()
        return {
            "id": expense_id,
            "name": name.strip(),
            "amount": amount_int,
            "date": date_val,
            "created_at": created_at_val
        }, None
    except Exception as e:
        conn.close()
        return None, str(e)

def get_expenses_by_date(date_str=None, start_date=None, end_date=None):
    """Get expenses filtered by date or date range."""
    conn = get_db_connection(row_factory=True)
    cursor = conn.cursor()
    try:
        if start_date and end_date:
            cursor.execute("SELECT * FROM expenses WHERE date BETWEEN ? AND ? ORDER BY date DESC, id DESC", (start_date, end_date))
        elif date_str:
            cursor.execute("SELECT * FROM expenses WHERE date = ? ORDER BY id DESC", (date_str,))
        else:
            cursor.execute("SELECT * FROM expenses ORDER BY date DESC, id DESC LIMIT 200")
        rows = cursor.fetchall()
        conn.close()
        return [dict(r) for r in rows]
    except Exception as e:
        conn.close()
        print(f"[DB] Error fetching expenses: {e}")
        return []

def get_ledger_summary(start_date=None, end_date=None):
    """Compute official verified financial ledger summary from database."""
    conn = get_db_connection(row_factory=True)
    cursor = conn.cursor()

    try:
        order_where = []
        order_params = []
        exp_where = []
        exp_params = []

        if start_date and end_date:
            order_where.append("date(order_date) BETWEEN ? AND ?")
            order_params.extend([start_date, end_date])
            exp_where.append("date(date) BETWEEN ? AND ?")
            exp_params.extend([start_date, end_date])
        elif start_date:
            order_where.append("date(order_date) = ?")
            order_params.append(start_date)
            exp_where.append("date(date) = ?")
            exp_params.append(start_date)

        order_sql = "SELECT * FROM orders"
        if order_where:
            order_sql += " WHERE " + " AND ".join(order_where)
        cursor.execute(order_sql, order_params)
        orders = cursor.fetchall()

        exp_sql = "SELECT * FROM expenses"
        if exp_where:
            exp_sql += " WHERE " + " AND ".join(exp_where)
        cursor.execute(exp_sql, exp_params)
        expenses = cursor.fetchall()

        total_orders_amount = 0
        total_income_cash = 0
        total_income_qris = 0
        total_paid_amount = 0
        total_piutang = 0
        total_expenses = sum(int(e["amount"]) for e in expenses)

        for o in orders:
            tot = int(o["total_amount"])
            paid = int(o["paid_amount"])
            method = (o["payment_method"] or "").lower()

            total_orders_amount += tot
            total_paid_amount += paid

            if tot > paid:
                total_piutang += (tot - paid)

            if "qris" in method or "transfer" in method:
                total_income_qris += paid
            else:
                total_income_cash += paid

        net_profit = total_paid_amount - total_expenses

        conn.close()
        return {
            "total_orders_count": len(orders),
            "total_order_amount": total_orders_amount,
            "total_paid_amount": total_paid_amount,
            "total_income_cash": total_income_cash,
            "total_income_qris": total_income_qris,
            "total_piutang": total_piutang,
            "total_expenses": total_expenses,
            "net_profit": net_profit
        }
    except Exception as e:
        conn.close()
        print(f"[DB] Error computing ledger summary: {e}")
        return {
            "total_orders_count": 0,
            "total_order_amount": 0,
            "total_paid_amount": 0,
            "total_income_cash": 0,
            "total_income_qris": 0,
            "total_piutang": 0,
            "total_expenses": 0,
            "net_profit": 0
        }
