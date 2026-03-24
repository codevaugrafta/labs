# ElevenLabs conversation token broker (personal use)

The ElevenLabs Swift SDK can start a session with a **public** `agent_id` only for agents marked public in the dashboard. **Private** agents need a **short-lived conversation token** minted with your **API key**. That key must not be embedded in `IMI.app`.

## Recommended setup

1. Create an API key in the ElevenLabs dashboard (restrict scopes if your plan allows).
2. Export it only in your shell when running the broker (never commit it):

   ```bash
   export ELEVENLABS_API_KEY="xi-..."
   ```

3. Start the local broker from the repo:

   ```bash
   cd VoiceTutor
   python3 scripts/elevenlabs_token_broker.py
   ```

   Default listen: `127.0.0.1:8787`. Override with `TOKEN_BROKER_HOST`, `TOKEN_BROKER_PORT`.

4. In **IMI → Settings**, enable **Use token broker**, set **Broker base URL** to `http://127.0.0.1:8787`, and set your **Agent ID**.

## API (local)

- `GET /health` → `200` with `{"ok":true}`.
- `GET /token?agent_id=<id>` → proxies to ElevenLabs and returns the JSON body (expects a `token` field).

## ElevenLabs API base URL

Some accounts use a regional host. Override if the default fails:

```bash
export ELEVENLABS_API_BASE="https://api.us.elevenlabs.io"
```

## Security notes

- The broker binds to **loopback** by default so other machines cannot reach it.
- Do not expose this process to the public internet.
- For a shared binary or TestFlight, replace the script with a real backend you control.

## Troubleshooting

- **401 / 403**: API key invalid or missing `convai` permission.
- **404 on token path**: Set `ELEVENLABS_API_BASE` to the host shown in your ElevenLabs API settings.
- **Regional routing**: If ElevenLabs documents an `environment` query value for your account, set the same in **IMI → Settings → Advanced (Swift SDK) → Environment** so the packaged app matches the broker/API host.

## SDK logs (debug builds)

Debug binaries configure the Swift SDK at **`.debug`** log level. In **Console.app**, filter subsystem **`com.elevenlabs.sdk`** (see upstream [Usage.md](https://github.com/elevenlabs/elevenlabs-swift-sdk/blob/main/Documentation/Usage.md) § Diagnostics).
