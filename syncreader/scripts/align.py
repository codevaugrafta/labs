#!/usr/bin/env python3
"""
SyncReader Alignment Script

Uses stable-ts (a wrapper around OpenAI Whisper) to perform forced alignment:
given a pre-existing audio file and the known transcript text, it produces
word-level timestamps without transcribing from scratch.

Output JSON schema (matches the Rust `AlignmentResult` type):
{
  "timestamps": [
    { "word": str, "start": float, "end": float, "sentenceIndex": int }
  ],
  "sentences": [
    {
      "index": int,
      "startWordIndex": int,
      "endWordIndex": int,
      "start": float,
      "end": float,
      "speaker": str | null
    }
  ]
}
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    import stable_whisper


# ---------------------------------------------------------------------------
# Dependency bootstrap
# ---------------------------------------------------------------------------

def _require_stable_ts():
    """Import stable_whisper, auto-installing if missing."""
    try:
        import stable_whisper
        return stable_whisper
    except ImportError:
        print("[align.py] stable-ts not found — installing…", file=sys.stderr)
        import subprocess
        subprocess.check_call(
            [sys.executable, "-m", "pip", "install", "stable-ts", "-q"],
            stdout=sys.stderr,
        )
        import stable_whisper
        return stable_whisper


# ---------------------------------------------------------------------------
# Speaker detection
# ---------------------------------------------------------------------------

_SPEAKER_RE = re.compile(r"^\[([^\]]+)\]\s*:")


def _extract_speaker(segment_text: str) -> str | None:
    """Return the speaker label from a `[Speaker]: text` prefix, or None."""
    m = _SPEAKER_RE.match(segment_text.strip())
    return m.group(1) if m else None


# ---------------------------------------------------------------------------
# Core alignment
# ---------------------------------------------------------------------------

def align(audio_path: str, text_path: str, output_path: str) -> None:
    stable_whisper = _require_stable_ts()

    with open(text_path, "r", encoding="utf-8") as fh:
        text = fh.read().strip()

    if not text:
        raise ValueError("Text file is empty — nothing to align.")

    print(f"[align.py] Loading model 'large-v3'…", file=sys.stderr)
    model = stable_whisper.load_model("large-v3")

    print(f"[align.py] Running alignment on: {audio_path}", file=sys.stderr)
    # `align` performs forced alignment against the provided text.
    # Pass language=None to let Whisper auto-detect it from the audio.
    result = model.align(audio_path, text, language=None)

    timestamps: list[dict] = []
    sentences: list[dict] = []
    word_index = 0
    sentence_index = 0

    for segment in result.segments:
        sentence_start_word = word_index
        sentence_start_time: float | None = None
        last_end: float = 0.0

        for word_info in segment.words:
            word_text: str = word_info.word.strip()
            if not word_text:
                continue

            if sentence_start_time is None:
                sentence_start_time = word_info.start

            last_end = word_info.end

            timestamps.append(
                {
                    "word": word_text,
                    "start": round(word_info.start, 3),
                    "end": round(word_info.end, 3),
                    "sentenceIndex": sentence_index,
                }
            )
            word_index += 1

        # Only emit a sentence entry when there was at least one word.
        if sentence_start_time is not None and word_index > sentence_start_word:
            sentences.append(
                {
                    "index": sentence_index,
                    "startWordIndex": sentence_start_word,
                    "endWordIndex": word_index - 1,
                    "start": round(sentence_start_time, 3),
                    "end": round(last_end, 3),
                    "speaker": _extract_speaker(segment.text),
                }
            )
            sentence_index += 1

    output = {"timestamps": timestamps, "sentences": sentences}

    with open(output_path, "w", encoding="utf-8") as fh:
        json.dump(output, fh, ensure_ascii=False, indent=2)

    print(
        f"[align.py] Done — {len(timestamps)} words across {len(sentences)} sentences.",
        file=sys.stderr,
    )


# ---------------------------------------------------------------------------
# CLI entry-point
# ---------------------------------------------------------------------------

def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Align audio with known text, producing word-level timestamps."
    )
    parser.add_argument("--audio", required=True, help="Path to the audio file (mp3/wav/…)")
    parser.add_argument("--text", help="Path to the plain-text transcript file")
    parser.add_argument("--output", help="Path to write the output JSON file (omit for stdout)")
    parser.add_argument("--stdin", action="store_true", help="Read text from stdin instead of --text file")
    return parser.parse_args()


if __name__ == "__main__":
    args = _parse_args()
    try:
        if args.stdin:
            # Read text from stdin, write JSON to stdout
            text = sys.stdin.read().strip()
            if not text:
                raise ValueError("No text received on stdin.")

            # Write to a temp file for stable-ts (it needs a file path)
            import tempfile, os
            with tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False, encoding="utf-8") as f:
                f.write(text)
                text_path = f.name

            try:
                output_path = text_path.replace(".txt", "_output.json")
                align(args.audio, text_path, output_path)
                with open(output_path, "r", encoding="utf-8") as f:
                    sys.stdout.write(f.read())
            finally:
                os.unlink(text_path)
                if os.path.exists(output_path):
                    os.unlink(output_path)
        else:
            if not args.text:
                print("[align.py] ERROR: --text is required when not using --stdin", file=sys.stderr)
                sys.exit(1)
            align(args.audio, args.text, args.output or "/dev/stdout")
    except Exception as exc:
        print(f"[align.py] ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
