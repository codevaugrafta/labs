#!/usr/bin/env python3
"""
List ElevenLabs Conversational AI agents (for pasting Agent ID into IMI Settings).

Requires ELEVENLABS_API_KEY in the environment (same as elevenlabs_token_broker.py).
Do not paste API keys into chat — export in your shell only.

Usage:
  export ELEVENLABS_API_KEY='xi-…'
  python3 scripts/list_convai_agents.py
"""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request

DEFAULT_BASE = os.environ.get("ELEVENLABS_API_BASE", "https://api.elevenlabs.io").rstrip("/")
FALLBACK_BASE = "https://api.us.elevenlabs.io"
BUNDLE_ID = "com.franciscodilussor.voicetutor"
AGENT_KEY = "VoiceTutor.agentId"


def main() -> int:
    api_key = os.environ.get("ELEVENLABS_API_KEY", "").strip()
    if not api_key:
        print(
            "Set ELEVENLABS_API_KEY in your environment (do not commit or paste in chat).\n"
            "  export ELEVENLABS_API_KEY='xi-…'\n"
            "Optional: ELEVENLABS_API_BASE if your account uses a regional host.",
            file=sys.stderr,
        )
        return 2

    bases_tried: list[str] = []
    last_body: str | None = None
    for base in [DEFAULT_BASE, FALLBACK_BASE]:
        if base in bases_tried:
            continue
        bases_tried.append(base)
        url = f"{base}/v1/convai/agents?page_size=50"
        req = urllib.request.Request(url, headers={"xi-api-key": api_key})
        try:
            with urllib.request.urlopen(req, timeout=45) as resp:
                last_body = resp.read().decode()
                data = json.loads(last_body)
        except urllib.error.HTTPError as e:
            err_txt = e.read().decode(errors="replace")[:500]
            print(f"{base}: HTTP {e.code} {err_txt}", file=sys.stderr)
            continue
        except Exception as e:
            print(f"{base}: {e}", file=sys.stderr)
            continue

        agents = data.get("agents")
        if agents is None and isinstance(data.get("data"), list):
            agents = data["data"]
        if not isinstance(agents, list):
            agents = []

        print(f"Using API host: {base}\n")
        if not agents:
            print("No agents found. Create one in the ElevenLabs ConvAI / Agents UI.")
            return 0

        for a in agents:
            if not isinstance(a, dict):
                continue
            aid = a.get("agent_id") or a.get("id")
            name = (a.get("name") or "?").strip()
            if aid:
                print(f"  {aid}\t{name}")

        print(
            "\n— IMI Settings —\n"
            "Copy an Agent ID above into IMI → Settings (⌘,).\n"
            "Public agent: turn **Use token broker** off.\n"
            "Private agent: run `python3 scripts/elevenlabs_token_broker.py` and enable the broker in Settings.\n"
            "\nOptional (CLI, quit IMI first):\n"
            f"  defaults write {BUNDLE_ID} {AGENT_KEY} -string 'PASTE_AGENT_ID_HERE'\n"
        )
        return 0

    print("Failed to list agents from known API hosts.", file=sys.stderr)
    if last_body:
        print(last_body[:800], file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
