#!/usr/bin/env python3
"""jiangshan-map local static server: repo root over HTTP + /health probe.

Serves the atlas site exactly as GitHub Pages does (repo root = site root),
plus a /health endpoint for ops-dashboard probing and a /jiangshan-map/
alias so the local probe path matches the Pages sub-path form.
"""
import json
import os
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.dirname(os.path.abspath(__file__))
PORT = int(os.environ.get("PORT", "8930"))


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)

    def do_GET_health(self):
        body = json.dumps({"status": "ok", "service": "jiangshan-map"}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            return self.do_GET_health()
        # Pages hosts this site under /jiangshan-map/; accept that prefix locally
        if self.path in ("/jiangshan-map", "/jiangshan-map/"):
            self.path = "/"
        return super().do_GET()

    def log_message(self, fmt, *args):
        pass  # keep the run/ log quiet; access logs are not useful here


if __name__ == "__main__":
    print(f"jiangshan-map serving {ROOT} on http://127.0.0.1:{PORT}")
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
