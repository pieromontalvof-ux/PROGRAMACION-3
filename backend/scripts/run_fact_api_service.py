"""Local Windows adapter to the actual Laravel HTTP kernel, never a mock API.

Each request boots PHP CLI; production should use PHP-FPM/nginx instead.
Only the authenticated bridge is served. Maximum four PHP processes.
"""
from pathlib import Path
import base64
import json
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from threading import BoundedSemaphore

root=Path(__file__).resolve().parents[2]
php=root/'.local/php/php.exe'
service=root/'services/fact_api'
slots=BoundedSemaphore(4)


class Handler(BaseHTTPRequestHandler):
    def setup(self):
        super().setup()
        self.connection.settimeout(15)
    def log_message(self,*args):pass  # Do not log documents, headers or personal data.
    def do_GET(self):self.handle_bridge()
    def do_POST(self):self.handle_bridge()
    def handle_bridge(self):
        if not self.path.startswith('/api/barbarito/'):
            self.send_error(404);return
        if not slots.acquire(blocking=False):
            self.send_response(429);self.send_header('Retry-After','5');self.end_headers();return
        try:
            length=int(self.headers.get('Content-Length','0'))
            if not 0<=length<=1024*1024:raise ValueError()
            request={'uri':self.path,'method':self.command,'authorization':self.headers.get('Authorization',''),
                     'key':self.headers.get('Idempotency-Key',''),'body':self.rfile.read(length).decode()}
            result=subprocess.run([str(php),str(service/'barbarito-cli-http.php')],cwd=service,
                input=json.dumps(request).encode(),capture_output=True,timeout=45,
                creationflags=subprocess.CREATE_NO_WINDOW if sys.platform=='win32' else 0)
            data=json.loads(result.stdout)
            self.send_response(data['status']);self.send_header('Content-Type',data['type'] or 'application/json')
            self.send_header('Cache-Control','private, no-store');self.send_header('X-Content-Type-Options','nosniff')
            body=base64.b64decode(data['body']);self.send_header('Content-Length',str(len(body)));self.end_headers()
            self.wfile.write(body)
        except (ValueError,KeyError,OSError,subprocess.SubprocessError):
            self.send_error(502)
        finally:slots.release()


if __name__=='__main__':
    print('fact_api DEMO (Laravel PHP): http://127.0.0.1:8091',flush=True)
    ThreadingHTTPServer(('127.0.0.1',8091),Handler).serve_forever()
