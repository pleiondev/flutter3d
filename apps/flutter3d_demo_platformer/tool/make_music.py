#!/usr/bin/env python3
"""Writes the game's one music loop as a procedural WAV.

Run from `apps/flutter3d_demo_platformer`:

    python3 tool/make_music.py

Generated rather than sourced, for the reason `make_sounds.py` gives at
length: `apps/flutter3d_demo_dungeon` carries a recorded debt because its key model has no
licence traced, and this game generates its sounds and its surface textures so
it cannot repeat that. A licence nobody can trace is a debt whatever the asset
is, and a music track is the easiest one in the world to acquire carelessly.

## The loop is exactly periodic, by construction

A loop that merely *ends* is a loop that clicks: the seam is a step change in
the waveform, and at 44.1 kHz a step is a broadband snap the ear finds
instantly and cannot stop noticing. Fading the ends out avoids the click and
replaces it with a hole in the music every twenty seconds, which is worse
because it sounds like a mistake rather than like a mistake.

So every oscillator's frequency is rounded to a whole number of cycles inside
the loop. The whole mix is then periodic at exactly the loop's own length, the
last sample joins the first with no discontinuity in value *or* slope, and
there is nothing to fade. The cost is that every pitch moves by at most half of
`1 / duration` — 0.023 Hz here, which is a four-hundredth of a cent, and the
rounding is done on the frequency rather than on the note so the error does not
accumulate up a chord.

## What it plays, and what it deliberately does not

A minor, 90 beats a minute, eight bars of Am–F–C–G: a pad holding the chord and
a slow arpeggio over it. **No drums.** A platformer's rhythm is its footsteps,
and a generated drum loop under them is the fastest way to make music the
player turns off — which is the same as not having written it.

It is mixed quiet on purpose, about eighteen decibels under full scale, because
it plays under everything else and the mixer's music slider should be for
turning it *up*.
"""

import math
import struct
import wave
from pathlib import Path

RATE = 44100
OUT = Path(__file__).resolve().parent.parent / "assets" / "sounds"

BPM = 90.0
BEAT = 60.0 / BPM
BARS = 8
BEATS_PER_BAR = 4
DURATION = BARS * BEATS_PER_BAR * BEAT          # 21 1/3 seconds
SAMPLES = round(DURATION * RATE)                 # 940800, exactly


def note(semitones_from_a4):
    """Equal temperament, from A4 = 440."""
    return 440.0 * (2.0 ** (semitones_from_a4 / 12.0))


def periodic(frequency):
    """The nearest frequency that fits a whole number of cycles in the loop.

    This is the whole reason the seam is silent. Rounding *up* to at least one
    cycle keeps a very low pad note from collapsing to a constant.
    """
    cycles = max(1.0, round(frequency * DURATION))
    return cycles / DURATION


# A2 is -24 from A4. The chords are named by their root's semitone offset and
# the three notes above it, all inside one octave so no voice ever leaps.
CHORDS = [
    ("Am", [-24, -17, -12]),   # A2 E3 A3
    ("Am", [-24, -17, -12]),
    ("F",  [-28, -21, -16]),   # F2 C3 F3
    ("F",  [-28, -21, -16]),
    ("C",  [-33, -24, -21]),   # C2 A2 C3
    ("C",  [-33, -24, -21]),
    ("G",  [-26, -19, -14]),   # G2 D3 G3
    ("G",  [-26, -19, -14]),
]

# What the arpeggio picks out over each chord, an octave and a half up.
ARPEGGIO = {
    "Am": [0, 3, 7, 12],
    "F":  [0, 4, 7, 12],
    "C":  [0, 4, 7, 12],
    "G":  [0, 4, 7, 12],
}


def pad():
    """The chords, held. Three sines a note, the upper two very slightly quiet.

    A chord that arrives and leaves would need an envelope, and an envelope
    that does not complete inside the loop is a click. Instead each bar's chord
    crossfades into the next over a whole beat, which is periodic by
    construction because the fade is a function of position in the loop.
    """
    out = [0.0] * SAMPLES
    bar_samples = SAMPLES // BARS
    fade = int(BEAT * RATE)

    for bar, (_, semitones) in enumerate(CHORDS):
        start = bar * bar_samples
        for voice, semitone in enumerate(semitones):
            f = periodic(note(semitone))
            gain = 0.6 if voice == 0 else 0.35
            # Two sines a hair apart, which is what makes a pad sound wide
            # rather than like a test tone. The detune is also quantised, so it
            # stays periodic.
            f2 = periodic(note(semitone) * 1.004)
            for i in range(bar_samples + fade):
                at = (start + i) % SAMPLES
                t = at / RATE
                # Level: full inside the bar, fading in over the first beat and
                # out over the last.
                if i < fade:
                    level = i / fade
                elif i > bar_samples - fade:
                    level = max(0.0, (bar_samples + fade - i) / (2.0 * fade))
                else:
                    level = 1.0
                out[at] += gain * level * (
                    math.sin(2.0 * math.pi * f * t) * 0.6
                    + math.sin(2.0 * math.pi * f2 * t) * 0.4
                )
    return out


def arpeggio():
    """Eighth notes climbing each chord, on a soft tone.

    The envelope is a decay that finishes well inside its own eighth, so no
    note is cut off by the loop point. The tone is a sine plus a quiet third
    harmonic, which is a clarinet's shape and forgiving at low volume.
    """
    out = [0.0] * SAMPLES
    eighth = int(BEAT * RATE / 2)
    per_bar = BEATS_PER_BAR * 2

    for bar, (name, semitones) in enumerate(CHORDS):
        root = semitones[0] + 24          # up two octaves, into the melody
        steps = ARPEGGIO[name]
        for eighth_i in range(per_bar):
            step = steps[eighth_i % len(steps)]
            # Down the chord in the second half of the bar, so eight notes are
            # a phrase rather than the same four twice.
            if eighth_i >= per_bar // 2:
                step = steps[(per_bar - 1 - eighth_i) % len(steps)]
            f = periodic(note(root + step))
            start = (bar * per_bar + eighth_i) * eighth
            length = min(eighth * 2, SAMPLES - start)
            for i in range(length):
                t = (start + i) / RATE
                # Struck and left to ring: a quick rise so it does not click,
                # then an exponential decay of about a third of a second.
                age = i / RATE
                envelope = (1.0 - math.exp(-age * 400.0)) * math.exp(-age * 3.4)
                out[start + i] += 0.22 * envelope * (
                    math.sin(2.0 * math.pi * f * t)
                    + 0.18 * math.sin(2.0 * math.pi * f * 3.0 * t)
                )
    return out


def mix():
    pad_track = pad()
    arp_track = arpeggio()
    out = [pad_track[i] + arp_track[i] for i in range(SAMPLES)]

    peak = max(abs(s) for s in out)
    # About eighteen decibels under full scale. It plays under everything.
    target = 0.126
    scale = target / peak if peak > 0.0 else 1.0
    return [s * scale for s in out]


def write(name, samples):
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / name
    with wave.open(str(path), "w") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(
            b"".join(
                struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32000))
                for s in samples
            )
        )
    return path


def main():
    samples = mix()
    path = write("music.wav", samples)

    # What can be checked without ears, and it is worth printing rather than
    # trusting: the seam, the level, and the length.
    seam = abs(samples[-1] - samples[0])
    slope_in = abs(samples[1] - samples[0])
    slope_out = abs(samples[-1] - samples[-2])
    rms = math.sqrt(sum(s * s for s in samples) / len(samples))
    print(f"{path.name}  {path.stat().st_size // 1024} KB")
    print(f"  {DURATION:.3f} s, {len(samples)} samples at {RATE} Hz")
    print(f"  peak {max(abs(s) for s in samples):.4f}, rms {rms:.4f}")
    print(f"  seam: value step {seam:.6f}, slope {slope_in:.6f} -> {slope_out:.6f}")
    if seam > 0.01:
        raise SystemExit("the loop does not join itself: the seam will click")


if __name__ == "__main__":
    main()
