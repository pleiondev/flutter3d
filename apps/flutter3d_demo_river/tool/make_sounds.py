#!/usr/bin/env python3
"""Writes River Sortie's sound bank as small procedural WAVs.

Generated rather than sourced, like every other demo's bank here: square waves
and a stepped noise from a shift register, the two things the Atari 2600's
sound chip could make, written by this file. Nothing is sampled from any game,
so the licence is the repository's own. The sounds are in the spirit of a 1982
cartridge (a droning engine that climbs with the throttle, a falling whistle
for a shot, crunching noise for anything hit, beeps while refuelling) without
being copies of anybody's.

Run from `apps/flutter3d_demo_river`:

    python3 tool/make_sounds.py

The output is deterministic: the noise comes from a fixed seed, so two runs
write the same bytes.
"""

import math
import struct
import wave
from pathlib import Path

RATE = 22050
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
                struct.pack("<h", int(max(-1.0, min(1.0, s)) * 30000))
                for s in samples
            )
        )
    print(f"{path.name}  {path.stat().st_size // 1024} KB")


def square(phase):
    return 1.0 if (phase % 1.0) < 0.5 else -1.0


class Poly:
    """A 15-bit shift register, stepped at a clock rate and held between
    steps: the pitched, gritty noise of an old sound chip rather than hiss."""

    def __init__(self, seed=0x5A5A):
        self.state = seed or 1
        self.value = 1.0
        self.phase = 0.0

    def sample(self, clock):
        self.phase += clock / RATE
        while self.phase >= 1.0:
            self.phase -= 1.0
            bit = (self.state ^ (self.state >> 1)) & 1
            self.state = (self.state >> 1) | (bit << 14)
            self.value = 1.0 if self.state & 1 else -1.0
        return self.value


def edges(samples, fade=0.004):
    """A few milliseconds in and out, so a one-shot never starts or stops on a
    click."""
    n = len(samples)
    k = max(1, int(RATE * fade))
    for i in range(min(k, n)):
        samples[i] *= i / k
        samples[n - 1 - i] *= i / k
    return samples


def lowpass(samples, amount):
    out, last = [], 0.0
    for s in samples:
        last += (s - last) * amount
        out.append(last)
    return out


def engine():
    """The drone the throttle bends: rumbling noise over a low buzz. A loop,
    played faster or slower with the jet's speed, so the noise clock and the
    buzz are both whole numbers of cycles across it."""
    seconds = 0.5
    n = int(RATE * seconds)
    poly = Poly(0x1ACE)
    out = []
    for i in range(n):
        t = i / RATE
        buzz = square(t * 62.0)  # 31 cycles in half a second
        out.append(0.55 * poly.sample(1300.0) + 0.3 * buzz)
    return lowpass(out, 0.35)


def shot():
    """A falling whistle."""
    seconds = 0.26
    n = int(RATE * seconds)
    out, phase = [], 0.0
    for i in range(n):
        x = i / n
        phase += (1500.0 - 1150.0 * x) / RATE
        out.append(0.5 * square(phase) * (1.0 - x) ** 1.5)
    return edges(out)


def boom(seconds, start_clock, end_clock, weight=1.0, seed=0x2B2B):
    """Noise whose clock falls as it dies: a crunch that drops in pitch."""
    n = int(RATE * seconds)
    poly = Poly(seed)
    out = []
    for i in range(n):
        x = i / n
        clock = start_clock * (end_clock / start_clock) ** x
        out.append(weight * poly.sample(clock) * math.exp(-4.0 * x))
    return edges(lowpass(out, 0.5))


def crash():
    """The jet going in: a long crunch with a low pulse under it."""
    noise = boom(1.8, 2400.0, 180.0, seed=0x3C3C)
    for i in range(len(noise)):
        t = i / RATE
        x = i / len(noise)
        noise[i] += 0.3 * square(t * 48.0) * math.exp(-3.0 * x)
    return edges(noise)


def refuel():
    """Rising chirps while a depot fills the tank. A loop: each pass is one
    chirp, and the jump back to the bottom is the point of it."""
    seconds = 0.32
    n = int(RATE * seconds)
    out, phase = [], 0.0
    for i in range(n):
        x = i / n
        phase += (380.0 + 620.0 * x) / RATE
        gate = 1.0 if x < 0.8 else 0.0
        out.append(0.35 * square(phase) * gate)
    return out


def low_fuel():
    """Two short beeps and a gap, over and over, below a quarter of a tank."""
    seconds = 0.6
    n = int(RATE * seconds)
    out = []
    for i in range(n):
        t = i / RATE
        on = t < 0.09 or 0.16 < t < 0.25
        out.append(0.4 * square(t * 920.0) if on else 0.0)
    return out


def spark():
    """A shot glancing off a shield: a bright ping."""
    seconds = 0.16
    n = int(RATE * seconds)
    poly = Poly(0x4D4D)
    out = []
    for i in range(n):
        t = i / RATE
        x = i / n
        tone = square(t * 2100.0) * 0.4 + poly.sample(9000.0) * 0.15
        out.append(tone * math.exp(-9.0 * x))
    return edges(out)


def tracer():
    """A helicopter firing: a short rising blip, higher than the jet's shot so
    the two are never confused."""
    seconds = 0.12
    n = int(RATE * seconds)
    out, phase = [], 0.0
    for i in range(n):
        x = i / n
        phase += (700.0 + 500.0 * x) / RATE
        out.append(0.35 * square(phase) * (1.0 - x))
    return edges(out)


def jingle(notes, step=0.09, gap=0.02):
    """Square-wave notes one after another."""
    out = []
    for frequency in notes:
        n = int(RATE * step)
        for i in range(n):
            t = i / RATE
            out.append(0.35 * square(t * frequency) * (1.0 - 0.5 * i / n))
        out.extend([0.0] * int(RATE * gap))
    return edges(out)


def main():
    write("engine.wav", engine())
    write("shot.wav", shot())
    write("boom.wav", boom(0.7, 3000.0, 400.0))
    write("big_boom.wav", boom(1.3, 2200.0, 160.0, seed=0x6E6E))
    write("crash.wav", crash())
    write("refuel.wav", refuel())
    write("low_fuel.wav", low_fuel())
    write("spark.wav", spark())
    write("tracer.wav", tracer())
    # C, E, G, high C: a level finished.
    write("level.wav", jingle([523.25, 659.25, 783.99, 1046.5]))
    # Up a fifth twice: another jet in reserve.
    write("extra_jet.wav", jingle([659.25, 987.77, 659.25, 987.77], step=0.07))


if __name__ == "__main__":
    main()
