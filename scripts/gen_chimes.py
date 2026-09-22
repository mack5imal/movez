#!/usr/bin/env python3
"""Synthesise the five movez chimes as 44.1 kHz 16-bit mono WAV files.

Stdlib only. Re-running is idempotent: the same bytes are produced every time.

    headsup.wav       two soft notes, E5 then G5, 120 ms each, -12 dBFS
    transition.wav    a single C6 note, 150 ms, -14 dBFS
    completion.wav    three ascending notes, C5-E5-G5, 140 ms each, 60 ms apart, -12 dBFS
    toast.wav         a single A5 note, 220 ms, -16 dBFS — the quietest, for the away toast
    microcountin.wav  a single E5 note, 180 ms, -18 dBFS — softer still: it announces a minute
"""

from __future__ import annotations

import math
import struct
import wave
from pathlib import Path

SAMPLE_RATE = 44_100
ATTACK_SECONDS = 0.008
DECAY_TAU = 0.09

NOTES = {"C5": 523.2511, "E5": 659.2551, "G5": 783.9909, "A5": 880.0000, "C6": 1046.5023}


def dbfs_to_amplitude(dbfs: float) -> float:
    return 10.0 ** (dbfs / 20.0)


def note(frequency: float, seconds: float, peak: float) -> list[float]:
    """One sine note with a short attack and an exponential decay."""
    total = int(SAMPLE_RATE * seconds)
    attack = max(1, int(SAMPLE_RATE * ATTACK_SECONDS))
    samples = []
    for index in range(total):
        time = index / SAMPLE_RATE
        envelope = min(1.0, index / attack) * math.exp(-time / DECAY_TAU)
        # A quiet second harmonic keeps the tone from sounding like a test beep.
        tone = math.sin(2 * math.pi * frequency * time)
        tone += 0.18 * math.sin(4 * math.pi * frequency * time)
        samples.append(peak * envelope * tone / 1.18)
    return samples


def silence(seconds: float) -> list[float]:
    return [0.0] * int(SAMPLE_RATE * seconds)


def fade_tail(samples: list[float], seconds: float = 0.006) -> list[float]:
    """Taper the final milliseconds so playback never clicks."""
    count = min(len(samples), int(SAMPLE_RATE * seconds))
    for offset in range(count):
        samples[len(samples) - count + offset] *= 1.0 - offset / count
    return samples


def write_wav(path: Path, samples: list[float]) -> int:
    frames = b"".join(
        struct.pack("<h", max(-32768, min(32767, int(round(value * 32767)))))
        for value in samples
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(SAMPLE_RATE)
        handle.writeframes(frames)
    return path.stat().st_size


def main() -> None:
    out_dir = Path(__file__).resolve().parent.parent / "Sources" / "movez" / "Resources" / "Chimes"

    soft = dbfs_to_amplitude(-12.0)
    softer = dbfs_to_amplitude(-14.0)
    softest = dbfs_to_amplitude(-16.0)
    quietest = dbfs_to_amplitude(-18.0)

    headsup = note(NOTES["E5"], 0.120, soft) + note(NOTES["G5"], 0.120, soft)
    transition = note(NOTES["C6"], 0.150, softer)
    toast = note(NOTES["A5"], 0.220, softest)
    # One note from the heads-up pair, quieter: the same app clearing its throat, for a minute
    # rather than five.
    micro_count_in = note(NOTES["E5"], 0.180, quietest)
    completion: list[float] = []
    for index, name in enumerate(("C5", "E5", "G5")):
        if index:
            completion += silence(0.060)
        completion += note(NOTES[name], 0.140, soft)

    for name, samples in (
        ("headsup.wav", headsup),
        ("transition.wav", transition),
        ("completion.wav", completion),
        ("toast.wav", toast),
        ("microcountin.wav", micro_count_in),
    ):
        size = write_wav(out_dir / name, fade_tail(list(samples)))
        seconds = len(samples) / SAMPLE_RATE
        print(f"{name}: {size} bytes, {seconds:.3f} s")
        if size <= 10_000:
            raise SystemExit(f"{name} is only {size} bytes; expected more than 10 KB")


if __name__ == "__main__":
    main()
