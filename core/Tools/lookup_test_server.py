#!/usr/bin/env python3
"""A small web server on this computer only, for the lookup's transport tests (PortableTransportTests).

It listens on 127.0.0.1 at ports the system picks and prints them: "PORT <n>" for plain HTTP and "TLS <n>" for
HTTPS with a certificate made on the spot that no system trusts (0 when no `openssl` program is here to make one).
A test never reaches MusicBrainz: it asks this server. Python's standard library only.
"""
import http.server, json, os, shutil, ssl, subprocess, sys, tempfile, threading, time


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def answer(self, status, body, kind="application/json", extra=()):
        self.send_response(status)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Deckie-Test", "yes")
        for name, value in extra:
            self.send_header(name, value)
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/json":
            self.answer(200, b'{"ok":true,"name":"Caf\xc3\xa9"}')
        elif path == "/echo":
            seen = {k.lower(): v for k, v in self.headers.items()}
            self.answer(200, json.dumps({"path": self.path, "headers": seen}).encode())
        elif path.startswith("/status/"):
            self.answer(int(path.rsplit("/", 1)[1]), b"x", "text/plain", [("Retry-After", "1")])
        elif path == "/cookie":
            self.answer(200, b"{}", extra=[("Set-Cookie", "deckie=1; Path=/")])
        elif path == "/slow":
            time.sleep(8)
            self.answer(200, b"{}")
        elif path == "/big":
            self.answer(200, b"a" * (1024 * 1024), "text/plain")
        elif path == "/redirect":
            self.answer(302, b"", extra=[("Location", "/json")])
        else:
            self.answer(404, b"{}")


def serve(context=None):
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    server.daemon_threads = True
    if context:
        server.socket = context.wrap_socket(server.socket, server_side=True)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server.server_address[1]


def tls_context():
    openssl = shutil.which("openssl")
    if not openssl:
        return None
    folder = tempfile.mkdtemp(prefix="deckie-lookup-test-")
    key, cert = os.path.join(folder, "key.pem"), os.path.join(folder, "cert.pem")
    made = subprocess.run([openssl, "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", key, "-out", cert,
                           "-days", "1", "-subj", "/CN=localhost"], capture_output=True)
    if made.returncode != 0:
        return None
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(cert, key)
    return context


if __name__ == "__main__":
    print("PORT", serve(), flush=True)
    context = tls_context()
    print("TLS", serve(context) if context else 0, flush=True)
    # Ends when the test closes this program's input, or after ten minutes whatever happens.
    threading.Thread(target=lambda: (sys.stdin.read(), os._exit(0)), daemon=True).start()
    time.sleep(600)
