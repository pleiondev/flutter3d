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


def normalise(samples, peak=0.9):
    """Scaled so the loudest sample is [peak]: every sound in the bank starts
    from the same ceiling, and the mix in `sounds.dart` decides which is
    louder, not the arithmetic here."""
    top = max(abs(s) for s in samples) or 1.0
    return [s * peak / top for s in samples]


def saturate(samples, drive):
    """Soft clipping: loud parts held down, the body brought up under them.
    An explosion whose peak is a crack a few milliseconds long, normalised as
    it is, leaves its rumble too quiet to hear over the engine."""
    return [math.tanh(drive * s) for s in samples]


def seamless(samples, overlap):
    """A loop with no seam: the last [overlap] samples are faded into the
    first, and dropped. Noise has no whole number of cycles to end on, so
    without this every pass of the engine clicked."""
    body = samples[: len(samples) - overlap]
    tail = samples[len(samples) - overlap :]
    for i in range(overlap):
        x = i / overlap
        body[i] = body[i] * x + tail[i] * (1.0 - x)
    return body


def engine():
    """The drone the throttle bends: a low hum with a rumble of filtered noise
    over it, trembling a little. It was a square wave, loud and bright, and it
    buried every shot and every hit under it. The hum sits at 110 Hz rather
    than lower, where a laptop's speakers would drop it.

    A loop a second long: the hum's three partials and the tremble are whole
    numbers of cycles across it, and the noise is made seamless."""
    seconds = 1.0
    overlap = int(RATE * 0.1)
    n = int(RATE * seconds) + overlap
    poly = Poly(0x1ACE)
    noise = lowpass([poly.sample(2600.0) for _ in range(n)], 0.1)
    out = []
    for i in range(n):
        t = i / RATE
        hum = (
            math.sin(2 * math.pi * 110.0 * t)
            + 0.45 * math.sin(2 * math.pi * 220.0 * t)
            + 0.2 * math.sin(2 * math.pi * 330.0 * t)
        )
        tremble = 1.0 + 0.12 * math.sin(2 * math.pi * 12.0 * t)
        out.append((0.5 * hum + 1.6 * noise[i]) * tremble)
    return normalise(seamless(out, overlap), 0.7)


def shot():
    """A bright "pew": a sweep falling fast from high to low, with a click of
    noise at its start so it cuts through the engine."""
    seconds = 0.2
    n = int(RATE * seconds)
    poly = Poly(0x7E7E)
    out, phase = [], 0.0
    for i in range(n):
        x = i / n
        t = i / RATE
        phase += (1900.0 * (320.0 / 1900.0) ** x) / RATE
        tone = math.sin(2 * math.pi * phase) + 0.3 * square(phase)
        click = poly.sample(12000.0) * math.exp(-t / 0.006)
        out.append(tone * math.exp(-4.5 * x) + 0.6 * click)
    return edges(normalise(saturate(normalise(out), 1.8)))


def explosion(seconds, thump_from, thump_to, decay, crackle=0.0, seed=0x2B2B):
    """What anything blowing up is made of: a crack, a thump that drops in
    pitch, and a rumble of noise whose brightness dies away faster than its
    loudness, so the tail is a low roll rather than hiss. [crackle] scatters
    pops through the tail, for something big burning."""
    n = int(RATE * seconds)
    poly = Poly(seed)
    pops = Poly(seed ^ 0x5555)
    out, phase, last = [], 0.0, 0.0
    for i in range(n):
        x = i / n
        t = i / RATE
        phase += (thump_from * (thump_to / thump_from) ** x) / RATE
        thump = math.sin(2 * math.pi * phase) * math.exp(-7.0 * x)
        brightness = 0.02 + 0.5 * math.exp(-6.0 * x)
        last += (poly.sample(6000.0) - last) * brightness
        rumble = last * math.exp(-decay * x)
        crack = poly.sample(15000.0) * math.exp(-t / 0.012)
        pop = 0.0
        if crackle and pops.sample(40.0) > 0 and (i % 97) < 3:
            pop = crackle * math.exp(-2.0 * x)
        out.append(1.2 * thump + 2.2 * rumble + 0.5 * crack + pop)
    return edges(normalise(saturate(normalise(out), 3.0)))


def boom():
    """A tanker, a helicopter or a jet going down."""
    return explosion(0.9, 120.0, 45.0, 3.5)


def big_boom():
    """A depot or a bridge: deeper, longer, and burning as it goes."""
    return explosion(1.6, 90.0, 30.0, 2.2, crackle=0.35, seed=0x6E6E)


def crash():
    """The jet going in: a dive whining down, then the biggest blast in the
    bank."""
    dive_seconds = 0.35
    d = int(RATE * dive_seconds)
    dive, phase = [], 0.0
    for i in range(d):
        x = i / d
        phase += (1100.0 * (180.0 / 1100.0) ** x) / RATE
        dive.append(0.35 * (math.sin(2 * math.pi * phase) + 0.25 * square(phase)))
    blast = explosion(2.0, 80.0, 28.0, 1.8, crackle=0.4, seed=0x3C3C)
    return edges(normalise(dive + blast))


def refuel():
    """Rising tones while a depot fills the tank. A loop: each pass is one
    tone climbing, soft at both ends so the jump back to the bottom is heard
    as the next tone and not as a click."""
    seconds = 0.36
    n = int(RATE * seconds)
    out, phase = [], 0.0
    sounding = int(n * 0.75)
    for i in range(n):
        if i >= sounding:
            out.append(0.0)
            continue
        x = i / sounding
        phase += (520.0 + 560.0 * x) / RATE
        envelope = min(1.0, x / 0.08) * min(1.0, (1.0 - x) / 0.15)
        tone = math.sin(2 * math.pi * phase) + 0.35 * math.sin(4 * math.pi * phase)
        out.append(tone * envelope)
    return normalise(out, 0.8)


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
    write("boom.wav", boom())
    write("big_boom.wav", big_boom())
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
