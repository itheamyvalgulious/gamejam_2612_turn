#!/usr/bin/env python3
"""本地预览服务器：正确的 MIME + 必要 header（Godot 网页版需要）。

    ./web/serve_web.sh                 # 127.0.0.1:16374
    ./web/serve_web.sh --port=16374

路由：
    /       网页版游戏（build/web/index.html）
    /win    Windows 版压缩包下载（build/win/*.zip）
    /mac    macOS 版压缩包下载（build/mac/*.zip）
"""
import argparse
import http.server
import os
import shutil
import socketserver
import ssl
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "build", "web")
BUILD = os.path.join(HERE, "..", "build")

# URL 路径 -> build/ 下的子目录
ARTIFACTS = {"/win": "win", "/mac": "mac"}

EXTRA_TYPES = {
    ".wasm": "application/wasm",
    ".pck": "application/octet-stream",
    ".js": "text/javascript",
    ".json": "application/json",
    ".svg": "image/svg+xml",
}


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=ROOT, **kw)

    def guess_type(self, path):
        ext = os.path.splitext(path)[1].lower()
        if ext in EXTRA_TYPES:
            return EXTRA_TYPES[ext]
        return super().guess_type(path)

    def end_headers(self):
        # 不需要跨源隔离（导出时关了线程），但缓存要关掉，方便反复验证
        self.send_header("Cache-Control", "no-store")
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        super().end_headers()

    def log_message(self, fmt, *args):
        sys.stderr.write("[web] %s\n" % (fmt % args))

    # ---- 桌面版下载 --------------------------------------------------------
    @staticmethod
    def artifact(kind):
        d = os.path.join(BUILD, kind)
        try:
            files = [os.path.join(d, f) for f in os.listdir(d) if f.endswith(".zip")]
        except OSError:
            return None
        return max(files, key=os.path.getmtime) if files else None

    @staticmethod
    def route(path):
        return (path.split("?", 1)[0].split("#", 1)[0].rstrip("/") or "/")

    def send_artifact(self, kind, head_only=False):
        path = self.artifact(kind)
        if not path:
            body = ("<!doctype html><meta charset=utf-8>"
                    "<title>还没有 %s 版</title>"
                    "<body style=\"font:15px/1.7 system-ui;padding:2em\">"
                    "<h1>还没有 %s 版构建</h1>"
                    "<p>先跑 <code>./web/build_web.sh build_all</code>，再刷新本页。</p>"
                    % (kind, kind)).encode("utf-8")
            self.send_response(404)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            if not head_only:
                self.wfile.write(body)
            return

        size = os.path.getsize(path)
        name = os.path.basename(path)
        self.send_response(200)
        self.send_header("Content-Type", "application/zip")
        self.send_header("Content-Length", str(size))
        self.send_header("Content-Disposition", 'attachment; filename="%s"' % name)
        self.end_headers()
        if head_only:
            return
        with open(path, "rb") as f:
            shutil.copyfileobj(f, self.wfile, 256 * 1024)

    def do_GET(self):
        r = self.route(self.path)
        if r in ARTIFACTS:
            return self.send_artifact(ARTIFACTS[r])
        return super().do_GET()

    def do_HEAD(self):
        r = self.route(self.path)
        if r in ARTIFACTS:
            return self.send_artifact(ARTIFACTS[r], head_only=True)
        return super().do_HEAD()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=16374)
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--tls", action="store_true", help="用自签名证书跑 HTTPS（安全上下文）")
    ap.add_argument("--cert", default=None)
    ap.add_argument("--key", default=None)
    args = ap.parse_args()
    if not os.path.isdir(ROOT):
        print("找不到 %s，先跑 ./web/build_web.sh" % ROOT, file=sys.stderr)
        return 1
    socketserver.TCPServer.allow_reuse_address = True
    cert = args.cert or os.path.join(HERE, "dev_cert.pem")
    key = args.key or os.path.join(HERE, "dev_key.pem")
    if args.tls and (not os.path.exists(cert) or not os.path.exists(key)):
        print("[web] 生成自签名证书 …")
        subprocess.run([
            "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "825",
            "-keyout", key, "-out", cert, "-subj", "/CN=actdemo.local",
            "-addext", "subjectAltName=DNS:localhost,IP:127.0.0.1,IP:10.82.90.210,IP:172.16.0.103",
        ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    with socketserver.ThreadingTCPServer((args.host, args.port), Handler) as httpd:
        scheme = "http"
        if args.tls:
            ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            ctx.load_cert_chain(certfile=cert, keyfile=key)
            httpd.socket = ctx.wrap_socket(httpd.socket, server_side=True)
            scheme = "https"
        base = "%s://%s:%d" % (scheme, args.host, args.port)
        print("[web] serving %s at %s/" % (ROOT, base))
        for route, kind in ARTIFACTS.items():
            path = Handler.artifact(kind)
            print("[web]   %-5s -> %s" % (route, path or "（未构建）"))
        httpd.serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main())
