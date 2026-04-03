#!/usr/bin/env python3
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib import request


BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "").strip()
CHAT_ID = os.environ.get("TELEGRAM_CHAT_ID", "").strip()
HOST = os.environ.get("TELEGRAM_RELAY_HOST", "127.0.0.1")
PORT = int(os.environ.get("TELEGRAM_RELAY_PORT", "8787"))


class RelayHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/health":
            self.send_error(404, "Unknown endpoint")
            return

        payload = json.dumps({
            "ok": True,
            "telegramConfigured": bool(BOT_TOKEN and CHAT_ID),
            "host": HOST,
            "port": PORT,
        }).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(payload)

    def do_POST(self):
        if self.path not in ("/telegram/message", "/live"):
            self.send_error(404, "Unknown endpoint")
            return

        if not BOT_TOKEN or not CHAT_ID:
            self.send_error(500, "Set TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID")
            return

        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length) if length else b"{}"
        payload = json.loads(body.decode("utf-8") or "{}")
        text = str(payload.get("text", "")).strip()
        if not text:
            self.send_error(400, "Missing 'text'")
            return

        telegram_payload = json.dumps({"chat_id": CHAT_ID, "text": text}).encode("utf-8")
        telegram_request = request.Request(
            f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage",
            data=telegram_payload,
            headers={"Content-Type": "application/json"},
            method="POST",
        )

        try:
            with request.urlopen(telegram_request) as response:
                raw = response.read()
        except Exception as exc:
            self.send_error(502, f"Telegram relay failed: {exc}")
            return

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(raw)

    def log_message(self, fmt, *args):
        sys.stdout.write((fmt % args) + "\n")


def main():
    server = HTTPServer((HOST, PORT), RelayHandler)
    print(f"Telegram relay listening on http://{HOST}:{PORT}")
    server.serve_forever()


if __name__ == "__main__":
    main()
