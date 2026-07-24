#!/usr/bin/env python3
"""Generate the user's tiny codec-free RG34XX-SP boot chime."""

from __future__ import annotations

import math
import pathlib
import struct
import wave


SAMPLE_RATE = 48_000
DURATION = 0.32
OUTPUT = pathlib.Path(__file__).parent / "launcher" / "boot.wav"


def bell(t: float, start: float, frequency: float, decay: float) -> float:
    age = t - start
    if age < 0:
        return 0.0
    attack = min(age / 0.006, 1.0)
    envelope = attack * math.exp(-age / decay)
    phase = 2.0 * math.pi * frequency * age
    return envelope * (math.sin(phase) + 0.22 * math.sin(phase * 2.0))


def main() -> None:
    frames = bytearray()
    peak = 0
    for index in range(round(SAMPLE_RATE * DURATION)):
        t = index / SAMPLE_RATE
        sample = 0.16 * bell(t, 0.000, 523.251, 0.075)
        sample += 0.18 * bell(t, 0.085, 783.991, 0.105)
        sample += 0.05 * bell(t, 0.085, 1_567.982, 0.045)
        value = max(-32_767, min(32_767, round(sample * 32_767)))
        peak = max(peak, abs(value))
        frames.extend(struct.pack("<h", value))

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUTPUT), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(SAMPLE_RATE)
        wav.writeframes(frames)
    print(f"generated {OUTPUT} ({len(frames)} PCM bytes, peak={peak})")


if __name__ == "__main__":
    main()
