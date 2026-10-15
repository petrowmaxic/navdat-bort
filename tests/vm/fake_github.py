"""Имитация GitHub API для проверки мастера установки без настоящих ключей.

    python3 fake_github.py <каталог с deb и SHA256SUMS> [порт]

Отвечает как api.github.com на запросы, которые делает navdat-install.sh:
  GET /user                                    -> {"login": LOGIN}
  GET /repos/<repo>/releases/tags/<tag>        -> список файлов релиза
  GET /repos/<repo>/releases/assets/<n>        -> 302 на /download/<имя>
  GET /download/<имя>                          -> файл (как S3, без ключа)
Всё, кроме /download, требует заголовок "Authorization: Bearer <TOKEN>".
"""
import http.server
import json
import os
import sys

LOGIN = "navdat-admin"
TOKEN = "test-token-123"
REPO = "petrowmaxic/navdat-bort-private"
TAG = "navdat-0.2.12"

ASSETS_DIR = sys.argv[1]
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 8088
BASE = "http://127.0.0.1:%d" % PORT
NAMES = sorted(n for n in os.listdir(ASSETS_DIR)
               if n.endswith(".deb") or n == "SHA256SUMS")


class Handler(http.server.BaseHTTPRequestHandler):
    def send_json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path.startswith("/download/"):
            name = os.path.basename(self.path)
            if self.headers.get("Authorization"):
                # S3 отклоняет чужой Authorization: curl не должен его пересылать
                return self.send_json(400, {"message": "unexpected Authorization"})
            data = open(os.path.join(ASSETS_DIR, name), "rb").read()
            self.send_response(200)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        if self.headers.get("Authorization") != "Bearer " + TOKEN:
            return self.send_json(401, {"message": "Bad credentials"})
        if self.path == "/user":
            return self.send_json(200, {"login": LOGIN})
        if self.path == "/repos/%s/releases/tags/%s" % (REPO, TAG):
            return self.send_json(200, {"tag_name": TAG, "assets": [
                {"url": "%s/repos/%s/releases/assets/%d" % (BASE, REPO, i), "name": n}
                for i, n in enumerate(NAMES)]})
        prefix = "/repos/%s/releases/assets/" % REPO
        if self.path.startswith(prefix):
            i = int(self.path[len(prefix):])
            if self.headers.get("Accept") != "application/octet-stream":
                return self.send_json(415, {"message": "need octet-stream"})
            self.send_response(302)
            self.send_header("Location", "%s/download/%s" % (BASE, NAMES[i]))
            self.end_headers()
            return
        self.send_json(404, {"message": "Not Found"})

    def log_message(self, fmt, *args):
        sys.stderr.write("fake_github: " + fmt % args + "\n")


http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
