#!/usr/bin/env python3
"""Synthesises the game's placeholder sound bank.

Not sampled, not downloaded: generated, so there is no licence to trace and no
binary in the repository whose origin somebody has to take on trust. They are
obviously synthetic and they are meant to be replaced — but a game with crude
sound reads as a game, and a silent one reads as broken.

Each sound is a short mono WAV at 22 050 Hz. Small enough that the whole bank
is under a hundred kilobytes, which is the other reason not to download.

Usage:  python3 tool/make_sounds.py
"""

import math
import pathlib
import random
import struct
import wave

RATE = 22050


def envelope(n: int, attack: float, decay: float, sustain: float = 0.0) -> list:
    """Attack-decay with an optional tail, in samples."""
    a = max(1, int(attack * RATE))
    d = max(1, int(decay * RATE))
    out = []
    for i in range(n):
        if i < a:
            out.append(i / a)
        elif i < a + d:
            t = (i - a) / d
            out.append((1.0 - t) * (1.0 - sustain) + sustain)
        else:
            out.append(sustain * max(0.0, 1.0 - (i - a - d) / max(1, n - a - d)))
    return out


def noise(n: int, seed: int) -> list:
    rng = random.Random(seed)
    return [rng.uniform(-1.0, 1.0) for _ in range(n)]


def tone(n: int, start: float, end: float) -> list:
    """A sine sweeping from [start] to [end] hertz."""
    out = []
    phase = 0.0
    for i in range(n):
        f = start + (end - start) * (i / max(1, n - 1))
        phase += 2.0 * math.pi * f / RATE
        out.append(math.sin(phase))
    return out


def lowpass(samples: list, cutoff: float) -> list:
    """One-pole, which is all a placeholder needs to stop sounding like hiss."""
    alpha = 1.0 - math.exp(-2.0 * math.pi * cutoff / RATE)
    out = []
    y = 0.0
    for x in samples:
        y += alpha * (x - y)
        out.append(y)
    return out


def mix(*layers) -> list:
    n = max(len(layer) for layer in layers)
    out = [0.0] * n
    for layer in layers:
        for i, v in enumerate(layer):
            out[i] += v
    return out


def write(path: pathlib.Path, samples: list, gain: float = 0.8) -> None:
    peak = max(1e-9, max(abs(s) for s in samples))
    scale = gain / peak
    frames = b"".join(
        struct.pack("<h", int(max(-1.0, min(1.0, s * scale)) * 32767))
        for s in samples
    )
    with wave.open(str(path), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(frames)
    print(f"{path.name:16} {len(samples) / RATE:.2f}s")


def build(out: pathlib.Path) -> None:
    out.mkdir(parents=True, exist_ok=True)

    # A pistol: a click of bright noise over a short thump.
    n = int(0.18 * RATE)
    env = envelope(n, 0.001, 0.14)
    crack = [s * e for s, e in zip(noise(n, 1), env)]
    body = [s * e * 0.8 for s, e in zip(tone(n, 220, 60), env)]
    write(out / "pistol.wav", mix(crack, body))

    # A shotgun: longer, darker, with a tail.
    n = int(0.42 * RATE)
    env = envelope(n, 0.002, 0.36)
    write(
        out / "shotgun.wav",
        mix(
            [s * e for s, e in zip(lowpass(noise(n, 2), 3000), env)],
            [s * e * 1.2 for s, e in zip(tone(n, 140, 40), env)],
        ),
    )

    # Stone on stone, for a door or a lift: filtered noise, no pitch.
    n = int(0.9 * RATE)
    env = envelope(n, 0.08, 0.5, sustain=0.35)
    write(
        out / "stone_move.wav",
        mix([s * e for s, e in zip(lowpass(noise(n, 3), 700), env)]),
        gain=0.55,
    )

    # The thud at each end of that travel.
    n = int(0.35 * RATE)
    env = envelope(n, 0.002, 0.3)
    write(
        out / "stone_stop.wav",
        mix(
            [s * e for s, e in zip(lowpass(noise(n, 4), 400), env)],
            [s * e for s, e in zip(tone(n, 90, 35), env)],
        ),
    )

    # A monster, hurt: a short growl.
    n = int(0.45 * RATE)
    env = envelope(n, 0.02, 0.4)
    growl = [
        math.sin(2 * math.pi * 110 * i / RATE)
        * (0.6 + 0.4 * math.sin(2 * math.pi * 23 * i / RATE))
        for i in range(n)
    ]
    write(
        out / "monster_pain.wav",
        mix(
            [s * e for s, e in zip(growl, env)],
            [s * e * 0.4 for s, e in zip(lowpass(noise(n, 5), 1500), env)],
        ),
    )

    # And dying: the same, lower and longer.
    n = int(0.85 * RATE)
    env = envelope(n, 0.03, 0.8)
    write(
        out / "monster_die.wav",
        mix(
            [s * e for s, e in zip(tone(n, 130, 45), env)],
            [s * e * 0.5 for s, e in zip(lowpass(noise(n, 6), 900), env)],
        ),
    )

    # A pickup: two quick rising blips, which is the sound every game uses
    # because it reads as "yours now" without a word being said.
    n = int(0.22 * RATE)
    blip = [s * e for s, e in zip(tone(n, 660, 990), envelope(n, 0.005, 0.18))]
    gap = [0.0] * int(0.06 * RATE)
    write(out / "pickup.wav", blip + gap + [s * 0.8 for s in blip])

    # A locked door: a flat, final clunk.
    n = int(0.25 * RATE)
    env = envelope(n, 0.001, 0.22)
    write(
        out / "locked.wav",
        mix([s * e for s, e in zip(lowpass(noise(n, 7), 500), env)]),
        gain=0.6,
    )

    # A torch, looping. Filtered noise slowly wobbling, and it has to join
    # itself end to end or the loop clicks once a second.
    n = int(2.0 * RATE)
    fire = lowpass(noise(n, 8), 1100)
    for i in range(n):
        fire[i] *= 0.55 + 0.45 * math.sin(2 * math.pi * 0.7 * i / RATE)
    blend = int(0.15 * RATE)
    for i in range(blend):
        t = i / blend
        fire[i] = fire[i] * t + fire[n - blend + i] * (1.0 - t)
    write(out / "torch_loop.wav", fire[: n - blend], gain=0.35)

    # A rocket leaving the tube. **Two of the four weapons used to be silent in
    # the sense that mattered**: the application played the pistol for anything
    # that was not a shotgun, so the launcher and the fists both cracked like a
    # nine-millimetre. Longer than the pistol and much darker, with the hiss of
    # the motor behind the launch.
    n = int(0.55 * RATE)
    env = envelope(n, 0.004, 0.5)
    write(
        out / "rocket.wav",
        mix(
            [s * e * 1.1 for s, e in zip(tone(n, 90, 28), env)],
            [s * e * 0.7 for s, e in zip(lowpass(noise(n, 11), 1800), env)],
        ),
        gain=0.75,
    )

    # A fist landing. No crack at all: a dull, close thump, and short, because
    # it is the one attack whose sound should not carry.
    n = int(0.16 * RATE)
    env = envelope(n, 0.002, 0.13)
    write(
        out / "punch.wav",
        mix(
            [s * e for s, e in zip(lowpass(noise(n, 12), 900), env)],
            [s * e * 0.9 for s, e in zip(tone(n, 150, 55), env)],
        ),
        gain=0.5,
    )

    # A boot on stone. Quiet on purpose: this plays several times a second for
    # the whole game, and a footstep anybody notices is a footstep everybody
    # hates by the second corridor.
    n = int(0.13 * RATE)
    env = envelope(n, 0.001, 0.11)
    write(
        out / "step_stone.wav",
        mix(
            [s * e for s, e in zip(lowpass(noise(n, 13), 2200), env)],
            [s * e * 0.5 for s, e in zip(tone(n, 190, 90), env)],
        ),
        gain=0.32,
    )


if __name__ == "__main__":
    build(pathlib.Path(__file__).resolve().parent.parent / "assets" / "sounds")
