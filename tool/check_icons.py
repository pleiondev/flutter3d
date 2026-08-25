#!/usr/bin/env python3
"""Checks that the committed icons are what `tool/make_icons.py` draws.

    python3 tool/check_icons.py

**Pixels, not bytes, and that is a finding rather than a preference.** The step
that used to do this regenerated the icons in place and asked `git diff` whether
anything moved. Two things were wrong with it.

The first is that it compared three files out of forty-three. Two of its three
pathspecs named directories with a `*` in them — `apps/*/macos/Runner/Assets.xcassets`
and `apps/*/web/icons` — and a `*` in a git pathspec does not cross a `/`, so
those patterns matched the directory's own path and nothing inside it. Only
`apps/*/web/favicon.png`, which has one `*` spanning one segment, ever matched.
It went unnoticed because the step could not run at all: Pillow was not on the
runner, so it failed before reaching the diff.

The second is that byte equality is not available across operating systems.
Pillow's LANCZOS is compiled per platform, and the same drawing reduced to the
same size gives bytes that differ by a little on Linux and macOS. Pinning the
version does not help — it was tried, and the same bytes came back. A check that
cannot pass on one of the machines it runs on is a check somebody switches off.

So this compares images: every pixel of every icon must be within
`TOLERANCE` per channel of the committed one, which a resampler's rounding stays
well inside and a changed design does not. The failure names the file, the worst
channel and how many pixels were over, because "the icons differ" is not
something anybody can act on.
"""

import os
import shutil
import sys
import tempfile

try:
    from PIL import Image, ImageChops
except ImportError:  # pragma: no cover - a helpful failure rather than a stack
    sys.exit('this needs Pillow: pip install pillow')

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_icons  # noqa: E402  (after the path is set, deliberately)

HERE = make_icons.HERE

# Per channel, on 0..255. The golden set uses the same number for the same
# reason: it is above what rounding does and below what a change does.
TOLERANCE = 8


def compare(drawn, committed):
    """The worst channel difference and how many pixels exceed the tolerance."""
    a = Image.open(drawn).convert('RGBA')
    b = Image.open(committed).convert('RGBA')
    if a.size != b.size:
        return None, None
    difference = ImageChops.difference(a, b)

    # The worst of the four channels, per pixel, as one band — `lighter` is a
    # per-pixel max. Counting through `histogram` rather than walking the pixels
    # keeps this in Pillow's C loop and avoids `getdata`, which is on its way
    # out.
    bands = difference.split()
    per_pixel = bands[0]
    for band in bands[1:]:
        per_pixel = ImageChops.lighter(per_pixel, band)

    worst = per_pixel.getextrema()[1]
    over = 0
    if worst > TOLERANCE:
        counts = per_pixel.histogram()
        over = sum(counts[TOLERANCE + 1:])
    return worst, over


def main():
    scratch = tempfile.mkdtemp(prefix='flutter3d_icons_')
    try:
        make_icons.main(root=scratch, quiet=True)

        checked = 0
        failures = []
        for base, _, files in os.walk(scratch):
            for name in sorted(files):
                drawn = os.path.join(base, name)
                relative = os.path.relpath(drawn, scratch)
                committed = os.path.join(HERE, relative)
                if not os.path.exists(committed):
                    failures.append(f'{relative}: is drawn and is not committed')
                    continue
                checked += 1
                worst, over = compare(drawn, committed)
                if worst is None:
                    failures.append(f'{relative}: committed at another size')
                elif worst > TOLERANCE:
                    failures.append(
                        f'{relative}: {over} pixels differ by more than '
                        f'{TOLERANCE}, worst channel {worst}')

        if failures:
            print('the committed icons are not what the generator draws:')
            for line in failures:
                print(f'  {line}')
            print('\nRun `python3 tool/make_icons.py` and commit the result, or '
                  'say why the drawing changed.')
            return 1

        print(f'{checked} icons match what the generator draws '
              f'(within {TOLERANCE} per channel)')
        return 0
    finally:
        shutil.rmtree(scratch, ignore_errors=True)


if __name__ == '__main__':
    sys.exit(main())
