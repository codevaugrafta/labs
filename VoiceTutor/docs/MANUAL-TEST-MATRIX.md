# Voice Tutor — manual test matrix

Run these after meaningful changes to audio, networking, or session lifecycle. Record pass/fail and macOS version.

## Microphone

- [ ] First launch: system prompts for microphone; deny → session shows a clear error path; allow → session can start.
- [ ] Toggle mute in-app while connected; confirm agent no longer hears you when muted.

## Audio route

- [ ] Start session on built-in mic; switch to Bluetooth headphones mid-session; confirm audio still works or app surfaces an error (note behavior).
- [ ] Disconnect Bluetooth during session; confirm recovery or controlled end (no silent hang).

## Sleep / wake

- [ ] Connect, then close laptop briefly; on wake, confirm session state is sensible (ended or reconnect prompt — note actual behavior).

## Network

- [ ] Start session, then disable Wi-Fi; confirm user-visible error within a reasonable time.
- [ ] Re-enable Wi-Fi; start a new session successfully.

## Token broker

- [ ] With **Use token broker** on and broker stopped: start session → expect connection/token error message.
- [ ] Start `scripts/elevenlabs_token_broker.py` with valid `ELEVENLABS_API_KEY`: `curl -s "http://127.0.0.1:8787/token?agent_id=YOUR_ID"` returns JSON with `token`.
- [ ] App start session with broker running succeeds for a private agent.

## Client tools (if configured in dashboard)

- [ ] Trigger a client tool from the agent; app returns an echo result and conversation continues without crash.
