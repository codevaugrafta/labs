#!/usr/bin/env python3
"""
One-shot macOS icon pipeline: Gemini image API -> PNG -> AppIcon.iconset -> AppIcon.icns.

Requires:
  - macOS (uses `sips` and `iconutil`)
  - GEMINI_API_KEY in the environment (Google AI Studio / Gemini API key)

Optional:
  - LOVE_ICON_GEMINI_MODEL (default: gemini-2.0-flash-preview-image-generation)
  - LOVE_ICON_PROMPT (override the default art brief)

Does not read .env files; never commit API keys.

Usage (from repo root or Love/):
  cd Love && export GEMINI_API_KEY=... && python3 scripts/generate_app_icon_gemini.py
"""

from __future__ import annotations

import base64
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request

DEFAULT_MODEL = "gemini-2.0-flash-preview-image-generation"
DEFAULT_PROMPT = (
    "Square macOS app icon, 1024x1024 concept: soft minimal heart motif on deep charcoal "
    "background, subtle coral or warm rose accent, flat vector style, no text, no letters, "
    "suitable for small menu bar sizes."
)

ICONSET_SPEC: list[tuple[int, str]] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]


def main() -> int:
    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        print("error: set GEMINI_API_KEY (see script docstring)", file=sys.stderr)
        return 1

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    build_dir = os.path.join(root, "build")
    os.makedirs(build_dir, exist_ok=True)
    master_png = os.path.join(build_dir, "gemini_icon_master.png")
    iconset_dir = os.path.join(build_dir, "AppIcon.iconset")

    model = os.environ.get("LOVE_ICON_GEMINI_MODEL", DEFAULT_MODEL)
    prompt = os.environ.get("LOVE_ICON_PROMPT", DEFAULT_PROMPT)

    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}"
    body = {
        "contents": [{"role": "user", "parts": [{"text": prompt}]}],
        "generationConfig": {"responseModalities": ["TEXT", "IMAGE"]},
    }
    req = urllib.request.Request(
        url,
        data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            payload = json.load(resp)
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8", errors="replace")
        print(f"error: Gemini HTTP {e.code}: {err_body}", file=sys.stderr)
        return 1
    except urllib.error.URLError as e:
        print(f"error: network {e}", file=sys.stderr)
        return 1

    image_bytes = _extract_first_inline_image(payload)
    if not image_bytes:
        print("error: no inline image in API response (model or API may have changed)", file=sys.stderr)
        print(json.dumps(payload, indent=2)[:4000], file=sys.stderr)
        return 1

    with open(master_png, "wb") as f:
        f.write(image_bytes)
    print(f"wrote {master_png}")

    if os.path.isdir(iconset_dir):
        subprocess.run(["rm", "-rf", iconset_dir], check=False)
    os.makedirs(iconset_dir, exist_ok=True)

    for size, filename in ICONSET_SPEC:
        out = os.path.join(iconset_dir, filename)
        subprocess.run(
            ["sips", "-z", str(size), str(size), master_png, "--out", out],
            check=True,
        )

    icns_out = os.path.join(build_dir, "AppIcon.icns")
    subprocess.run(["iconutil", "-c", "icns", iconset_dir, "-o", icns_out], check=True)
    print(f"wrote {icns_out}")
    print("To use in Love.app: ensure build-app.sh copies this icns, or delete Love.app/Contents/Resources/AppIcon.icns and re-run ./build-app.sh")
    return 0


def _extract_first_inline_image(payload: dict) -> bytes | None:
    candidates = payload.get("candidates") or []
    for cand in candidates:
        content = cand.get("content") or {}
        for part in content.get("parts") or []:
            inline = part.get("inlineData") or part.get("inline_data")
            if not inline:
                continue
            b64 = inline.get("data")
            if b64:
                return base64.standard_b64decode(b64)
    return None


if __name__ == "__main__":
    raise SystemExit(main())
