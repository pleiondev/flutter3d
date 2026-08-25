#!/usr/bin/env python3
"""Draws the application icons, so that they can be changed rather than found.

    python3 tool/make_icons.py

**A generator rather than four folders of PNGs somebody once exported.** Every
other asset in this repository that is not a photograph is written by a script
next to it — the levels, the tracks, the models' preparation — for the reason
this file exists too: an icon that can only be edited in an image editor by the
person who has that image editor is an icon nobody will ever fix.

Four designs, one per application, each made of the thing the application is
about and nothing else:

  * **Ascent** climbs: steps rising into a cold morning sky.
  * **The Crypt** is a lit doorway in the dark, which is the whole of that game:
    somewhere to go, and a torch to see it by.
  * **Ring** is a circuit seen from above, with the line you cross.
  * **editor** is a wireframe box on a grid, in the green the editor draws a
    selection in — the one thing on its screen that is the editor rather than
    somebody's level.

Written at four times the largest size and reduced, because a rounded corner and
a diagonal drawn at 16 pixels by a program are a staircase, and drawn at 4096 and
reduced they are a corner and a diagonal.
"""

import math
import os
import sys

try:
    from PIL import Image, ImageChops, ImageDraw, ImageFilter
except ImportError:  # pragma: no cover - a helpful failure rather than a stack
    sys.exit('this needs Pillow: pip install pillow')

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# The sizes macOS asks for, and the sizes a browser does.
MAC_SIZES = (16, 32, 64, 128, 256, 512, 1024)
WEB_SIZES = (192, 512)

# What is drawn at, before reducing. Four times the largest is what it takes for
# the 16-pixel version to have a clean edge.
CANVAS = 4096

# macOS leaves the outer tenth alone and rounds what is left by about a fifth of
# its own width. Both numbers are Apple's, and getting them wrong is the
# difference between an icon that sits in the dock and one that shouts.
MARGIN = 0.098
RADIUS = 0.2237


def tile(background, draw_content):
    """A rounded square with [draw_content] inside it."""
    size = CANVAS
    image = Image.new('RGBA', (size, size), (0, 0, 0, 0))

    inset = int(size * MARGIN)
    side = size - inset * 2
    radius = int(side * RADIUS)

    face = Image.new('RGBA', (side, side), (0, 0, 0, 255))
    draw_content(face, ImageDraw.Draw(face))

    mask = Image.new('L', (side, side), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, side - 1, side - 1), radius=radius, fill=255
    )

    # A shadow, because every icon beside it in the dock has one and the one
    # without reads as flat.
    shadow = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 90), (inset, inset + int(side * 0.02)), mask)
    shadow = shadow.filter(ImageFilter.GaussianBlur(side * 0.02))

    image.alpha_composite(shadow)
    image.paste(face, (inset, inset), mask)
    return image


def vertical_gradient(image, top, bottom):
    width, height = image.size
    draw = ImageDraw.Draw(image)
    for y in range(height):
        t = y / (height - 1)
        draw.line(
            [(0, y), (width, y)],
            fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)),
        )


def radial_glow(image, centre, radius, colour, strength=1.0):
    """A soft light.

    **Added rather than drawn over**, which is the difference between a lamp and
    a stain: painting translucent circles on top of a picture pulls every colour
    under them towards the one being painted, so a warm glow over a blue sky
    came out as a dark disc. Light adds.
    """
    glow = Image.new('L', image.size, 0)
    draw = ImageDraw.Draw(glow)
    steps = 64
    for step in range(steps, 0, -1):
        t = step / steps
        r = radius * t
        draw.ellipse(
            [centre[0] - r, centre[1] - r, centre[0] + r, centre[1] + r],
            fill=round(255 * strength * (1 - t) ** 2),
        )
    tint = Image.new('RGB', image.size, colour)
    lit = ImageChops.add(image.convert('RGB'), ImageChops.multiply(
        tint, Image.merge('RGB', (glow, glow, glow))
    ))
    image.paste(lit)


def ascent(face, draw):
    """Steps rising into a cold morning."""
    vertical_gradient(face, (22, 38, 86), (196, 224, 238))
    side = face.size[0]

    # A sun low on the right, and the light it puts into the sky.
    sun = (side * 0.74, side * 0.30)
    radial_glow(face, sun, side * 0.46, (250, 206, 120), 0.85)
    draw = ImageDraw.Draw(face)
    draw.ellipse(
        [sun[0] - side * 0.062, sun[1] - side * 0.062,
         sun[0] + side * 0.062, sun[1] + side * 0.062],
        fill=(255, 250, 232),
    )

    # Five steps, each one taller, climbing to the right: rock with snow on it,
    # which is what this game's last level is made of.
    steps = 5
    for i in range(steps):
        left = side * (0.06 + i * 0.176)
        width = side * 0.176
        top = side * (0.80 - i * 0.128)
        draw.rectangle([left, top, left + width, side], fill=(42, 50, 74))
        draw.rectangle(
            [left, top, left + width, top + side * 0.030],
            fill=(240, 248, 255),
        )
        # The side of each step catches a little of the sun.
        draw.rectangle(
            [left, top, left + side * 0.012, side], fill=(58, 68, 96)
        )


def crypt(face, draw):
    """A lit doorway in the dark."""
    vertical_gradient(face, (18, 16, 20), (34, 28, 26))
    side = face.size[0]

    # Courses of stone, just visible.
    course = side * 0.085
    for row in range(int(side / course) + 1):
        y = row * course
        draw.line([(0, y), (side, y)], fill=(48, 42, 40), width=int(side * 0.006))
        offset = 0 if row % 2 else course / 2
        for column in range(int(side / course) + 2):
            x = column * course + offset
            draw.line(
                [(x, y), (x, y + course)],
                fill=(48, 42, 40),
                width=int(side * 0.006),
            )

    # The arch: a rectangle with a half-round top, filled with the light beyond.
    left, right = side * 0.30, side * 0.70
    top, bottom = side * 0.34, side * 0.92
    radial_glow(face, (side * 0.5, side * 0.58), side * 0.52, (255, 168, 64), 0.5)
    draw.rectangle([left, top + (right - left) / 2, right, bottom], fill=(255, 196, 104))
    draw.pieslice(
        [left, top, right, top + (right - left)],
        start=180,
        end=360,
        fill=(255, 196, 104),
    )
    # Deeper in the doorway it is darker, or the arch reads as a lamp.
    inset = side * 0.055
    draw.rectangle(
        [left + inset, top + (right - left) / 2, right - inset, bottom],
        fill=(196, 116, 40),
    )
    draw.pieslice(
        [left + inset, top + inset, right - inset, top + (right - left) - inset],
        start=180,
        end=360,
        fill=(196, 116, 40),
    )


def ring(face, draw):
    """A circuit from above, and the line you cross."""
    vertical_gradient(face, (30, 34, 42), (16, 18, 22))
    side = face.size[0]

    tarmac = (78, 80, 88)
    infield = (30, 54, 38)
    kerb = (236, 238, 244)

    # The road as a wide oval, its inside cut back out. Drawn kerb-first so the
    # white edges are a ring under the tarmac rather than two more ellipses to
    # keep in step.
    outer = [side * 0.08, side * 0.16, side * 0.92, side * 0.84]
    inner = [side * 0.30, side * 0.36, side * 0.70, side * 0.64]
    draw.ellipse(outer, fill=kerb)
    edge = side * 0.018
    draw.ellipse([outer[0] + edge, outer[1] + edge,
                  outer[2] - edge, outer[3] - edge], fill=tarmac)
    draw.ellipse([inner[0] - edge, inner[1] - edge,
                  inner[2] + edge, inner[3] + edge], fill=kerb)
    draw.ellipse(inner, fill=infield)

    # The start line, chequered, **across** the road rather than along it: two
    # rows of eight, laid on the near straight.
    columns, rows = 8, 2
    band_width = side * 0.20
    cell = band_width / columns
    x0 = side * 0.5 - band_width / 2
    y0 = side * 0.84 - edge - rows * cell
    for row in range(rows):
        for column in range(columns):
            if (row + column) % 2:
                continue
            draw.rectangle(
                [x0 + column * cell, y0 + row * cell,
                 x0 + (column + 1) * cell, y0 + (row + 1) * cell],
                fill=kerb,
            )


def editor(face, draw):
    """A wireframe box on a grid, in the green a selection is drawn in."""
    vertical_gradient(face, (18, 22, 28), (10, 12, 16))
    side = face.size[0]

    # A ground grid in perspective, fading as it goes back.
    horizon = side * 0.46
    for i in range(-6, 7):
        x = side * 0.5 + i * side * 0.19
        draw.line(
            [(side * 0.5 + i * side * 0.055, horizon), (x, side)],
            fill=(38, 48, 60),
            width=int(side * 0.006),
        )
    y = horizon
    step = side * 0.022
    while y < side:
        draw.line([(0, y), (side, y)], fill=(38, 48, 60), width=int(side * 0.006))
        step *= 1.34
        y += step

    # The box: a cube in two-point perspective, drawn as twelve lines exactly
    # the way the editor draws a selection.
    green = (126, 217, 87)
    width = int(side * 0.022)
    w, h, d = side * 0.30, side * 0.30, side * 0.16
    cx, cy = side * 0.46, side * 0.60
    front = [
        (cx - w / 2, cy - h / 2),
        (cx + w / 2, cy - h / 2),
        (cx + w / 2, cy + h / 2),
        (cx - w / 2, cy + h / 2),
    ]
    back = [(x + d, y - d) for x, y in front]
    for a, b in zip(front, front[1:] + front[:1]):
        draw.line([a, b], fill=green, width=width)
    for a, b in zip(back, back[1:] + back[:1]):
        draw.line([a, b], fill=green, width=width)
    for a, b in zip(front, back):
        draw.line([a, b], fill=green, width=width)


# Keyed on the application directory, which is also its package name. The
# `flutter3d_` prefix is not decoration here: `os.path.isdir` below silently
# writes nothing for a key that does not match a directory, so a stale name
# means an icon that quietly stops being regenerated — and the CI step that
# diffs the output would go on passing, because nothing changed.
DESIGNS = {
    'flutter3d_demo_platformer': ascent,
    'flutter3d_demo_dungeon': crypt,
    'flutter3d_demo_racing': ring,
    'flutter3d_editor': editor,
}


def write(image, path, size):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    image.resize((size, size), Image.LANCZOS).save(path)


def main(root=HERE, quiet=False):
    """Draws every icon under `root`, which is the repository unless a checker
    hands it somewhere else.

    The output root is a parameter so `tool/check_icons.py` can draw into a
    temporary directory and compare, instead of overwriting what is committed
    and then asking git what moved. A check that has to dirty the tree to run is
    a check nobody runs while they are working.

    Which applications get which icons is decided from `root` when it is the
    repository and from `HERE` otherwise: a temporary directory has no `macos/`
    or `web/` in it, and the answer must not depend on that.
    """
    for app, design in DESIGNS.items():
        image = tile(None, design)

        if os.path.isdir(os.path.join(HERE, 'apps', app, 'macos', 'Runner',
                                      'Assets.xcassets', 'AppIcon.appiconset')):
            mac = os.path.join(
                root, 'apps', app, 'macos', 'Runner', 'Assets.xcassets',
                'AppIcon.appiconset',
            )
            for size in MAC_SIZES:
                write(image, os.path.join(mac, f'app_icon_{size}.png'), size)

        web = os.path.join(root, 'apps', app, 'web')
        if os.path.isdir(os.path.join(HERE, 'apps', app, 'web')):
            for size in WEB_SIZES:
                write(image, os.path.join(web, 'icons', f'Icon-{size}.png'), size)
                # The maskable one is the same drawing: this tile already keeps
                # everything well inside the safe area a mask leaves, which is
                # what "maskable" asks for.
                write(
                    image,
                    os.path.join(web, 'icons', f'Icon-maskable-{size}.png'),
                    size,
                )
            write(image, os.path.join(web, 'favicon.png'), 32)

        if not quiet:
            print(f'{app}: icons written')


if __name__ == '__main__':
    main()
