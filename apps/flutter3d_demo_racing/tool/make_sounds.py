#!/usr/bin/env python3
"""Writes this game's sound bank as small procedural WAVs.

Generated rather than sourced, for the reason the platformer's script gives:
`apps/flutter3d_demo_dungeon` carries a recorded debt because one of its assets has no licence
traced, and a game that repeated that would be repeating a known mistake.
Everything here is sines and phase-randomised harmonics written by this file, so
the licence is the repository's own.

Run from `apps/flutter3d_demo_racing`:

    python3 tool/make_sounds.py

## Why the loops are built out of harmonics of the loop length

A loop has to join to itself. Any partial whose frequency is not a whole number
of cycles across the loop arrives at the seam mid-swing, and the step to the
start of the next pass is a click — once every loop, forever, which is the most
noticeable fault a continuous sound can have. So every component here, including
the noise, is a sine at an integer multiple of `1 / seconds`. That makes the
waveform exactly periodic by construction rather than by fading the ends, which
is the other way to do it and costs the bottom octave.
"""

import math
import random
import struct
import wave
from pathlib import Path

RATE = 44100
OUT = Path(__file__).resolve().parent.parent / "assets" / "sounds"

# How long the continuous sounds are. Long enough that the ear does not hear the
# repeat, short enough that the files stay small.
LOOP_SECONDS = 0.5

# What the two engine recordings are *of*, as a fraction of maximum revs. These
# are the numbers `LoopBand.centre` is given, and they have to agree with the
# firing frequencies below or the crossfade corrects a pitch that was never
# wrong.
LOW_REVS = 0.35
HIGH_REVS = 0.85

# The firing note at each of those, in Hz, rounded to a whole number of cycles
# per loop.
LOW_HZ = 90.0
HIGH_HZ = 220.0


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


def harmonics_of(seconds):
    """The only frequencies that can appear in a seamless loop of this length."""
    return 1.0 / seconds


def loop(seconds, parts, seed=1):
    """Sums `(multiple, amplitude)` pairs of the loop's own fundamental.

    Phases are random but fixed by the seed, so two runs of this script produce
    the same file — the same rule the level and texture generators keep.
    """
    rng = random.Random(seed)
    base = harmonics_of(seconds)
    phases = {multiple: rng.uniform(0.0, 2 * math.pi) for multiple, _ in parts}
    count = int(RATE * seconds)

    peak = 0.0
    samples = []
    for i in range(count):
        t = i / RATE
        value = 0.0
        for multiple, amplitude in parts:
            value += amplitude * math.sin(
                2 * math.pi * base * multiple * t + phases[multiple]
            )
        samples.append(value)
        peak = max(peak, abs(value))

    if peak > 0:
        samples = [s / peak * 0.85 for s in samples]
    return samples


def engine(fundamental, roughness, seed):
    """An engine note: a stack of harmonics of the firing frequency, plus hash.

    The harmonics are what makes it an engine rather than a tone, and the hash
    is what makes it a mechanical one. A higher `roughness` moves weight up the
    stack and adds more of the wideband part, which is what an engine does as it
    is worked harder.
    """
    base = harmonics_of(LOOP_SECONDS)
    firing = round(fundamental / base)

    parts = []
    for order in range(1, 13):
        multiple = firing * order
        if multiple * base > 8000:
            break
        # Falling off with order, less steeply when the engine is working.
        amplitude = 1.0 / (order ** (1.9 - roughness * 0.7))
        # Half orders: the uneven firing of a real engine, which is most of why
        # one sounds like an engine and not like an organ.
        parts.append((multiple, amplitude))
        if order < 6:
            parts.append((max(1, multiple - firing // 2), amplitude * 0.35))

    # The wideband part, as phase-randomised harmonics so that it still loops.
    rng = random.Random(seed + 99)
    for multiple in range(firing // 2, 4000 // int(base), max(1, firing // 3)):
        parts.append((multiple, rng.uniform(0.0, 0.05) * (0.4 + roughness)))

    return loop(LOOP_SECONDS, parts, seed=seed)


def skid():
    """Tyres letting go: wideband, with a peak where rubber squeals."""
    base = harmonics_of(LOOP_SECONDS)
    rng = random.Random(7)
    parts = []
    for multiple in range(2, int(6000 / base), 3):
        hz = multiple * base
        # A broad resonance around 1.4 kHz, which is where a squeal lives.
        shape = math.exp(-(((hz - 1400.0) / 900.0) ** 2)) + 0.25
        parts.append((multiple, rng.uniform(0.3, 1.0) * shape))
    return loop(LOOP_SECONDS, parts, seed=11)


def rumble():
    """Off the road: low, coarse, and continuous."""
    base = harmonics_of(LOOP_SECONDS)
    rng = random.Random(13)
    parts = []
    for multiple in range(1, int(900 / base)):
        hz = multiple * base
        parts.append((multiple, rng.uniform(0.2, 1.0) * math.exp(-hz / 260.0)))
    return loop(LOOP_SECONDS, parts, seed=17)


def blip(seconds, hz, harmonics=(1.0, 0.4, 0.15), attack=0.005, release=0.35):
    """A short tone with a soft start and end. For the lights and the flag."""
    count = int(RATE * seconds)
    samples = []
    for i in range(count):
        t = i / RATE
        fraction = i / count
        if fraction < attack:
            level = fraction / attack
        else:
            level = max(0.0, (1.0 - fraction) ** (1.0 / release))
        value = 0.0
        for order, amplitude in enumerate(harmonics, start=1):
            value += amplitude * math.sin(2 * math.pi * hz * order * t)
        samples.append(value * level / sum(harmonics) * 0.9)
    return samples


def thud(seconds=0.28, seed=23):
    """Car meets car, or car meets wall."""
    rng = random.Random(seed)
    count = int(RATE * seconds)
    samples = []
    state = 0.0
    for i in range(count):
        fraction = i / count
        level = max(0.0, (1.0 - fraction) ** 3)
        # A one-pole filter on white noise: a knock rather than a hiss.
        state += (rng.uniform(-1.0, 1.0) - state) * 0.12
        tone = math.sin(2 * math.pi * 70.0 * i / RATE)
        samples.append((state * 1.6 + tone * 0.7) * level)
    return samples


def main():
    write("engine_low.wav", engine(LOW_HZ, roughness=0.25, seed=3))
    write("engine_high.wav", engine(HIGH_HZ, roughness=0.9, seed=5))
    write("skid.wav", skid())
    write("rumble.wav", rumble())

    # The lights: three of one note and one of another, which is the shape
    # every racing game uses because it needs no explaining.
    write("count.wav", blip(0.18, 440.0))
    write("go.wav", blip(0.45, 660.0, harmonics=(1.0, 0.5, 0.25), release=0.5))

    write("lap.wav", blip(0.3, 880.0, harmonics=(1.0, 0.3)))
    write("best.wav", blip(0.55, 1046.5, harmonics=(1.0, 0.45, 0.2), release=0.5))
    write("checkpoint.wav", blip(0.12, 1320.0, harmonics=(1.0,)))
    write("bump.wav", thud())

    print(
        f"engine bands: low {LOW_HZ:.0f} Hz at {LOW_REVS} revs, "
        f"high {HIGH_HZ:.0f} Hz at {HIGH_REVS} — these must match `Sounds`"
    )


if __name__ == "__main__":
    main()
