#!/usr/bin/env python3
"""
Minimal localhost broker: mints ElevenLabs ConvAI conversation tokens using xi-api-key.
Personal dev only — do not expose to the network.
"""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

DEFAULT_BASE = os.environ.get("ELEVENLABS_API_BASE", "https://api.elevenlabs.io").rstrip("/")
TOKEN_PATH = "/v1/convai/conversation/token"


def fetch_token(api_key: str, agent_id: str) -> tuple[int, bytes]:
    qs = urllib.parse.urlencode({"agent_id": agent_id})
    url = f"{DEFAULT_BASE}{TOKEN_PATH}?{qs}"
    req = urllib.request.Request(
        url,
        method="GET",
        headers={
            "xi-api-key": api_key,
            "Accept": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.getcode(), resp.read()
    except urllib.error.HTTPError as e:
        body = e.read()
        return e.code, body


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args) -> None:
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    def _send(self, code: int, body: bytes, content_type: str = "application/json") -> None:
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/health":
            self._send(200, b'{"ok":true}\n')
            return
        if parsed.path != "/token":
            self._send(404, b'{"error":"not_found"}\n')
            return

        api_key = os.environ.get("ELEVENLABS_API_KEY", "").strip()
        if not api_key:
            self._send(
                500,
                json.dumps({"error": "ELEVENLABS_API_KEY not set in broker environment"}).encode()
                + b"\n",
            )
            return

        q = urllib.parse.parse_qs(parsed.query)
        agent_ids = q.get("agent_id", [])
        if not agent_ids or not agent_ids[0]:
            self._send(400, b'{"error":"missing agent_id"}\n')
            return
        agent_id = agent_ids[0]

        status, data = fetch_token(api_key, agent_id)
        self._send(status, data if data else b"{}\n")


def main() -> None:
    host = os.environ.get("TOKEN_BROKER_HOST", "127.0.0.1")
    port = int(os.environ.get("TOKEN_BROKER_PORT", "8787"))
    print(f"ElevenLabs token broker on http://{host}:{port}", file=sys.stderr)
    print(f"API base: {DEFAULT_BASE}", file=sys.stderr)
    HTTPServer((host, port), Handler).serve_forever()


if __name__ == "__main__":
    main()
