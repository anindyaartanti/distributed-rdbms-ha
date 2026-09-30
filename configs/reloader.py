import json
import os
import re
import shutil
import socket
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

CFG = os.environ.get("HAPROXY_CFG", "/shared/haproxy.cfg")
MASTER_SOCK = os.environ.get("HAPROXY_MASTER_SOCK", "/shared/haproxy.sock")
PORT = int(os.environ.get("RELOADER_PORT", "8080"))


def reload_haproxy():
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(10)
    s.connect(MASTER_SOCK)
    s.sendall(b"reload\n")
    data = b""
    try:
        while True:
            chunk = s.recv(4096)
            if not chunk:
                break
            data += chunk
            if b"Success=" in data:
                break
    except socket.timeout:
        pass
    finally:
        s.close()
    return data.decode(errors="replace")


def apply_failover(failed, successor, port):
    if not failed:
        raise ValueError("field 'failed' is required")
    if not successor:
        raise ValueError("field 'successor' is required")

    with open(CFG, "r", encoding="utf-8") as fh:
        original = fh.read()

    pattern = re.compile(
        r"(^\s*server\s+)" + re.escape(failed) + r"(\s+)" + re.escape(failed) + r"(:\d+)",
        re.MULTILINE,
    )
    updated, count = pattern.subn(
        r"\g<1>" + successor + r"\g<2>" + successor + r"\g<3>", original
    )
    if count == 0:
        pattern = re.compile(
            r"(^\s*server\s+\S+\s+)" + re.escape(failed) + r"(:\d+)",
            re.MULTILINE,
        )
        updated, count = pattern.subn(r"\g<1>" + successor + r"\g<2>", original)
    if count == 0:
        raise ValueError("no backend server references host '%s'" % failed)

    backup = CFG + ".bak"
    shutil.copyfile(CFG, backup)
    with open(CFG, "w", encoding="utf-8") as fh:
        fh.write(updated)

    result = reload_haproxy()
    if "Success=1" not in result:
        shutil.copyfile(backup, CFG)
        raise RuntimeError("haproxy reload failed: %s" % result.strip())
    return count, result.strip()


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, payload):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            self._send(200, {"status": "ok"})
        else:
            self._send(404, {"error": "not found"})

    def do_POST(self):
        if self.path == "/reload":
            try:
                self._send(200, {"status": "ok", "reload": reload_haproxy().strip()})
            except Exception as exc:
                self._send(500, {"status": "error", "error": str(exc)})
            return
        if self.path != "/failover":
            self._send(404, {"error": "not found"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            payload = json.loads(self.rfile.read(length) or b"{}")
            count, result = apply_failover(
                payload.get("failed"),
                payload.get("successor"),
                payload.get("port", 3306),
            )
            self._send(200, {"status": "ok", "updated": count, "reload": result})
        except Exception as exc:
            self._send(500, {"status": "error", "error": str(exc)})

    def log_message(self, fmt, *args):
        sys.stderr.write("reloader: " + (fmt % args) + "\n")


if __name__ == "__main__":
    print("haproxy-reloader listening on :%d (cfg=%s sock=%s)" % (PORT, CFG, MASTER_SOCK))
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
