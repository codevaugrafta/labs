#!/usr/bin/env bash
# Regenerate gentle-chime.m4a (short tone, no third-party audio).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/Sources/Resources/Audio/gentle-chime.m4a"
TMPWAV="$(mktemp -t adhan-chimeXXXX).wav"
python3 << PY
import wave, struct, math
path = "$TMPWAV"
sample_rate = 44_100
duration = 0.22
freq = 880.0
frames = int(sample_rate * duration)
with wave.open(path, "w") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(sample_rate)
    for i in range(frames):
        env = min(1.0, i / 800.0, (frames - i) / 1200.0)
        v = int(32767 * 0.18 * env * math.sin(2 * math.pi * freq * i / sample_rate))
        w.writeframes(struct.pack("<h", v))
PY
afconvert -f m4af -d aac "$TMPWAV" "$OUT"
rm -f "$TMPWAV"
echo "Wrote $OUT"
shasum -a 256 "$OUT"
