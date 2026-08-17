#!/usr/bin/env python3
"""supervise.py — minimal HTTP server that fronts mcp-proxy.

Routes:
  GET  /healthz  -> "ok" (no auth)
  *    /         -> proxies to mcp-proxy on its private port

This is intentionally tiny (~50 lines) so the auth/routing surface
area is auditable. The actual MCP protocol runs unmodified inside
mcp-proxy.
"""
import os
import sys
import threading
import time
import urllib.request
import urllib.error
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MCP_PROXY_PORT = int(os.environ.get("MCP_PROXY_UPSTREAM_PORT", "8765"))
PUBLIC_PORT = int(os.environ.get("MCP_PORT", "8080"))


def proxy_to_mcp(method: str, path: str, body: bytes, headers: dict) -> tuple[int, dict, bytes]:
    """Forward a request to mcp-proxy and return (status, headers, body)."""
    url = f"http://127.0.0.1:{MCP_PROXY_PORT}{path}"
    req = urllib.request.Request(url, data=body, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            return resp.status, dict(resp.headers), resp.read()
    except urllib.error.HTTPError as e:
        return e.code, dict(e.headers), e.read()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        # Keep logs quiet; the supervisor emits its own status line per restart
        pass

    def do_GET(self):
        if self.path == "/healthz":
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"ok\n")
            return
        self._proxy("GET")

    def do_POST(self):
        self._proxy("POST")

    def do_DELETE(self):
        self._proxy("DELETE")

    def _proxy(self, method):
        length = int(self.headers.get("Content-Length", "0") or "0")
        body = self.rfile.read(length) if length else b""
        # Forward only a curated set of headers — drop Host, Connection, etc.
        fwd_headers = {
            k: v for k, v in self.headers.items()
            if k.lower() in ("authorization", "content-type", "accept", "user-agent")
        }
        try:
            status, resp_headers, resp_body = proxy_to_mcp(method, self.path, body, fwd_headers)
        except Exception as e:
            self.send_response(502)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(f"upstream error: {e}\n".encode())
            return
        self.send_response(status)
        for k, v in resp_headers.items():
            if k.lower() in ("content-type", "cache-control", "x-"):
                self.send_header(k, v)
        self.send_header("Content-Length", str(len(resp_body)))
        self.end_headers()
        self.wfile.write(resp_body)


def wait_for_mcp_proxy():
    """Block until mcp-proxy is answering on its private port."""
    deadline = time.time() + 90
    while time.time() < deadline:
        try:
            urllib.request.urlopen(
                f"http://127.0.0.1:{MCP_PROXY_PORT}/healthz",
                timeout=2,
            )
            return
        except Exception:
            time.sleep(1)
    print("[supervise] WARNING: mcp-proxy never came up after 90s", file=sys.stderr)


def main():
    print(f"[supervise] starting public HTTP server on :{PUBLIC_PORT}, proxying /mcp to :{MCP_PROXY_PORT}")
    wait_for_mcp_proxy()
    httpd = ThreadingHTTPServer(("0.0.0.0", PUBLIC_PORT), Handler)
    httpd.serve_forever()


if __name__ == "__main__":
    main()
