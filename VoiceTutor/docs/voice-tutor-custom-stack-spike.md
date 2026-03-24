# Custom voice stack spike (Path C)

This is a **research spike** for migrating off hosted ElevenLabs conversational agents to a **self-owned** pipeline. It is not implemented in the app; use it to decide whether Path C is worth the engineering cost.

## Target architecture

1. **STT**: Deepgram live WebSocket (`wss://api.deepgram.com/v1/listen`) with `interim_results`, `endpointing`, and `vad_events` tuned for end-of-turn latency.
2. **LLM**: Your choice (e.g. Claude API) with tool calling for tutor behaviors; you own prompt, memory, and rate limits.
3. **TTS**: Streaming TTS (Cartesia WebSocket/HTTP, InWorld, or ElevenLabs TTS-only) with chunked playback.
4. **Orchestrator**: Small state machine on-device or on a tiny backend: `listening → user_turn_final → llm_stream → tts_stream → speaking → listening`, plus **barge-in** (cancel TTS and flush when VAD detects user speech).

## Latency checklist

- Measure **transcript latency** vs **end-of-turn latency** (Deepgram docs).
- Measure **time-to-first-audio** from end of user speech.
- Compare cold vs warm connections (WebSocket reuse).

## Barge-in

- Hosted SDKs handle this differently; custom stack must **stop audio playback** and **cancel in-flight LLM/TTS** when user starts speaking.
- Validate with overlapping speech tests.

## Cost

- Recompute from current vendor pricing; STT + LLM + TTS each have independent meters.
- Include dev time: expect **many weeks** for parity with hosted agent UX.

## Exit criteria for “spike done”

- Documented numbers for one language (e.g. Mandarin) on your hardware.
- Go / no-go decision: stay on hosted agent vs invest in Path C.
