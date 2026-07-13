from http.server import BaseHTTPRequestHandler, HTTPServer

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"halo dari hostname")

server = HTTPServer(("0.0.0.0", 80), Handler)
print("Server aktif via hostname")
server.serve_forever()
