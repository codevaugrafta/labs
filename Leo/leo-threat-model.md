# Leo Threat Model

Date: 2026-03-28  
Scope: Runtime behavior in `Leo/` — embedded HTTP server, WKWebView EPUB reader, local dictionary assets, optional cloud lookups (OpenRouter, InWorld TTS).

## Assumptions

- The attacker does not already have root on the Mac; targets are other processes on the LAN, malicious EPUB/PDF, and confused deputy via the local server.
- Leo is a **local reader**; `com.apple.security.app-sandbox` is **disabled** in the current entitlements (developer distribution posture).

## Assets

- User library paths on disk (imported books under Application Support).
- Vocabulary / FSRS SwiftData store.
- API keys in UserDefaults (`leo.openRouterApiKey`, `leo.inworldApiKey`).
- Reading privacy (titles, lookups).

## Trust Boundaries

- **LocalServer** (Swifter on loopback): serves `web/` and per-book blobs under `/book/:id`.
- **WKWebView**: loads `http://127.0.0.1:port/…`; JS bridge `leoReader`.
- **User-selected files**: EPUB/PDF import (security-scoped bookmark where applicable).
- **Network**: OpenRouter and InWorld when enabled.

## Hardening (this revision)

- **Loopback bind:** `HttpServer.listenAddressIPv4 = "127.0.0.1"` so the server does not listen on all interfaces (Swifter default was INADDR_ANY).
- **CORS:** `Access-Control-Allow-Origin` set to `http://127.0.0.1:<port>` instead of `*` for `/web/` and `/book/` responses (same origin as the WebView).

## Residual Risks

- **Unsandboxed app:** any RCE or serious bug runs with the user’s privileges; App Store would require a sandbox migration (file access, server, networking).
- **Any local process** can call `http://127.0.0.1:<port>/book/<uuid>` if it guesses or learns port + book id — EPUB/PDF bytes are user content but could be sensitive; treat as **local confidentiality** boundary.
- **LLM / TTS:** prompts and text leave the device when API keys are set; users must trust OpenRouter/InWorld policies.

## Recommended Next Steps

1. If shipping broadly: enable App Sandbox and re-audit LocalServer + file access entitlements.
2. Rate-limit or authenticate local `/book/` routes if threat model moves beyond single-user desktop.
3. Move API keys from UserDefaults to Keychain for moderate local adversary resistance.
