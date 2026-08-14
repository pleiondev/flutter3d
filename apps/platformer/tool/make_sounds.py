#!/usr/bin/env python3
"""Writes the game's sound bank as small procedural WAVs.

Generated rather than sourced, and that is the point: `apps/dungeon` carries a
recorded debt because its key model and its maps have no licence traced, and a
second game repeating that would be repeating a known mistake. Everything here
is a few sine and noise envelopes written by this file, so the licence is the
repository's own.

Run from `apps/platformer`:

    python3 tool/make_sounds.py
"""

import math
import random
import struct
import wave
from pathlib import Path

RATE = 44100
OUT = Path(__file__).resolve().parent.parent / "assets" / "sounds"


def write(name, samples):
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / name
    with wave.open(str(path), "w") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(
            b"".join(
                struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32000)) for s in samples
            )
        )
    print(f"{path.name}  {path.stat().st_size // 1024} KB")


def envelope(i, count, attack=0.01, release=0.6):
    """Attack and decay as fractions of the whole, so nothing clicks."""
    t = i / count
    if t < attack:
        return t / attack
    return max(0.0, (1.0 - t) ** (1.0 / release))


def tone(seconds, start, end, harmonics=(1.0,), noise=0.0, seed=1):
    rng = random.Random(seed)
    count = int(RATE * seconds)
    phase = 0.0
    for i in range(count):
        t = i / count
        frequency = start + (end - start) * t
        phase += 2.0 * math.pi * frequency / RATE
        value = sum(a * math.sin(phase * n) for n, a in enumerate(harmonics, start=1))
        if noise:
            value += rng.uniform(-1.0, 1.0) * noise
        yield value * envelope(i, count) * 0.6


# A coin: two quick rising partials, the oldest sound in the genre.
write("coin.wav", tone(0.22, 900, 1700, harmonics=(1.0, 0.35)))

# A jump: a short upward whoop.
write("jump.wav", tone(0.16, 320, 700, harmonics=(1.0, 0.2)))

# Landing: a low thud with a little grit in it.
write("land.wav", tone(0.14, 190, 90, harmonics=(1.0, 0.3), noise=0.25, seed=7))

# A double jump, thinner and higher than the first so the two are not one sound.
write("airjump.wav", tone(0.14, 520, 980, harmonics=(1.0, 0.15)))

# The dash: noise sweeping down, no pitch to speak of.
write("dash.wav", tone(0.18, 1400, 300, harmonics=(0.4,), noise=0.55, seed=3))

# Death: a falling tone that gives up.
write("death.wav", tone(0.5, 480, 110, harmonics=(1.0, 0.45, 0.2)))

# The checkpoint: a two-note chime, so it reads as good news.
write("checkpoint.wav", tone(0.4, 600, 900, harmonics=(1.0, 0.5, 0.25)))
