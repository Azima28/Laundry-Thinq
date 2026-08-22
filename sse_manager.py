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
    # Log significant state changes to console (suppress 1-second countdown tick spam)
    if not data.startswith("LOG|") and "|" in data:
        parts = data.split("|")
        log_key = f"{parts[0]}_{parts[1] if len(parts)>1 else ''}_{parts[2] if len(parts)>2 else ''}_{parts[7] if len(parts)>7 else ''}"
        if _last_logged_broadcast.get(parts[0]) != log_key:
            _last_logged_broadcast[parts[0]] = log_key
            print(f"[SSE] State Change: {data}")

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
