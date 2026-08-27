#!/usr/bin/python

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import sys


RESULT = Path(sys.argv[1])
PAGE = b"""<!doctype html>
<meta charset=utf-8>
<title>Tablet Chromium Input</title>
<style>
html,body { height:100%; margin:0; background:#202020; color:#fff; }
body { display:grid; place-items:center; font:24px sans-serif; }
textarea { width:70vw; height:25vh; padding:20px; font:28px monospace; }
</style>
<textarea id=target autofocus aria-label='Tablet input target'></textarea>
<script>
const target = document.querySelector('#target');
target.addEventListener('input', () => fetch('/result', {method:'POST', body:target.value}));
window.addEventListener('load', () => target.focus());
</script>"""


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/":
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(PAGE)))
        self.end_headers()
        self.wfile.write(PAGE)

    def do_POST(self):
        if self.path != "/result":
            self.send_error(404)
            return
        size = int(self.headers.get("Content-Length", "0"))
        RESULT.write_bytes(self.rfile.read(size))
        self.send_response(204)
        self.end_headers()

    def log_message(self, *_args):
        pass


ThreadingHTTPServer(("127.0.0.1", 18473), Handler).serve_forever()
