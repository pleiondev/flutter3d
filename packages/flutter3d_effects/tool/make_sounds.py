#!/usr/bin/env python3
"""Synthesises the sounds the physics is heard through.

Generated rather than recorded, so there is no licence to trace and no
binary whose origin has to be taken on trust. A game turns each one's gain
and speed every frame by what the physics does — a fire's watts, the power
of falling water, the energy a body enters the water with — so the files are
the timbre, and the physics is the performance.

Mono WAV at 22 050 Hz, into `assets/`, which the package declares.

Usage:  python3 tool/make_sounds.py
"""

import math
import pathlib
import random
import struct
import wave

RATE = 22050


def lowpass(samples, cutoff):
    alpha = 1.0 - math.exp(-2.0 * math.pi * cutoff / RATE)
    out, y = [], 0.0
    for s in samples:
        y += alpha * (s - y)
        out.append(y)
    return out


def highpass(samples, cutoff):
    low = lowpass(samples, cutoff)
    return [s - l for s, l in zip(samples, low)]


def loop_blend(samples, blend):
    """The tail laid over the head, so the loop has no click where it wraps."""
    n = len(samples) - blend
    out = samples[:n]
    for i in range(blend):
        t = i / blend
        out[i] = out[i] * t + samples[n + i] * (1.0 - t)
    return out


def write(path, samples, gain):
    peak = max(1e-9, max(abs(s) for s in samples))
    with wave.open(str(path), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(
            b"".join(
                struct.pack("<h", int(max(-1.0, min(1.0, s / peak * gain)) * 32767))
                for s in samples
            )
        )


def main():
    out = pathlib.Path(__file__).resolve().parent.parent / "assets"
    out.mkdir(exist_ok=True)
    rng = random.Random(3)

    # A fire: the low rush of the plume, and crackle — short clicks at random,
    # each a decaying burst, denser and brighter than a torch's.
    n = int(4.0 * RATE)
    blend = int(0.3 * RATE)
    rush = lowpass([rng.uniform(-1, 1) for _ in range(n)], 260)
    crackle = [0.0] * n
    t = 0
    while t < n:
        t += int(rng.expovariate(38.0) * RATE) + 1
        size = rng.uniform(0.2, 1.0) ** 2
        length = int(rng.uniform(0.002, 0.012) * RATE)
        for k in range(min(length, n - t)):
            crackle[t + k] += size * rng.uniform(-1, 1) * math.exp(-5.0 * k / length)
    crackle = highpass(crackle, 900)
    fire = [r * 3.0 + c for r, c in zip(rush, crackle)]
    write(out / "fire_loop.wav", loop_blend(fire, blend), gain=0.6)

    # Falling water: broad noise, its weight below a kilohertz, with a slow
    # swell so a long loop does not sound like a held note.
    n = int(5.0 * RATE)
    blend = int(0.4 * RATE)
    white = [rng.uniform(-1, 1) for _ in range(n)]
    body = lowpass(white, 900)
    hiss = highpass(lowpass(white, 5000), 1500)
    falls = [
        (b * 2.2 + h * 0.5) * (0.85 + 0.15 * math.sin(2 * math.pi * 0.37 * i / RATE))
        for i, (b, h) in enumerate(zip(body, hiss))
    ]
    write(out / "falls_loop.wav", loop_blend(falls, blend), gain=0.6)

    # A splash: a thump as the surface parts, then the spray falling back,
    # bright and quickly gone.
    n = int(0.7 * RATE)
    thump = lowpass([rng.uniform(-1, 1) for _ in range(n)], 300)
    spray = highpass([rng.uniform(-1, 1) for _ in range(n)], 1200)
    splash = []
    for i in range(n):
        s = i / RATE
        splash.append(
            thump[i] * 2.5 * math.exp(-s / 0.05)
            + spray[i] * 0.8 * min(1.0, s / 0.03) * math.exp(-s / 0.18)
        )
    write(out / "splash.wav", splash, gain=0.8)


if __name__ == "__main__":
    main()
