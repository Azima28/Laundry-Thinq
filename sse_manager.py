import threading
import queue

# Subscribers for WS -> Flask client communication (per-client queue)
subscribers = set()
subscribers_lock = threading.Lock()

# Global state for initial snapshots
latest_state = {}
_last_logged_broadcast = {}

def broadcast(data):
    """Send data to all connected SSE clients."""
    # Debug log only when data changes to prevent console flood
    if not data.startswith("LOG|"):
        key = data.split("|")[0] if "|" in data else data
        if _last_logged_broadcast.get(key) != data:
            _last_logged_broadcast[key] = data
            print(f"[SSE] Update: {data}")

    with subscribers_lock:
        for q in list(subscribers):
            try:
                q.put(data)
            except Exception:
                pass

def get_sse_stream(keep_alive_timeout=15):
    """Generator for Flask SSE stream."""
    q = queue.Queue()
    with subscribers_lock:
        subscribers.add(q)
    try:
        # Send initial snapshots to new client
        for sensor, val in latest_state.items():
            yield f"data: {val}\n\n"

        while True:
            try:
                data = q.get(timeout=keep_alive_timeout)
                yield f"data: {data}\n\n"
            except queue.Empty:
                # SSE comment as keep-alive
                yield ": ping\n\n"
    finally:
        with subscribers_lock:
            subscribers.discard(q)
