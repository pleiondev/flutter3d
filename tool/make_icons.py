#!/usr/bin/env python3
"""Draws the application icons, so that they can be changed rather than found.

    python3 tool/make_icons.py

**A generator rather than four folders of PNGs somebody once exported.** Every
other asset in this repository that is not a photograph is written by a script
next to it — the levels, the tracks, the models' preparation — for the reason
this file exists too: an icon that can only be edited in an image editor by the
person who has that image editor is an icon nobody will ever fix.

Five designs, one per application, each made of the thing the application is
about and nothing else:

  * **Ascent** climbs: steps rising into a cold morning sky.
  * **The Crypt** is a lit doorway in the dark, which is the whole of that game:
    somewhere to go, and a torch to see it by.
  * **Ring** is a circuit seen from above, with the line you cross.
  * **Hillside** is a crowd on sloping ground with a box dragged round part of
    it — a camera above a map and an order given to a selection, which is what
    makes the fourth genre a different shape from the three before it.
  * **editor** is a wireframe box on a grid, in the green the editor draws a
    selection in — the one thing on its screen that is the editor rather than
    somebody's level.

Written at four times the largest size and reduced, because a rounded corner and
a diagonal drawn at 16 pixels by a program are a staircase, and drawn at 4096 and
reduced they are a corner and a diagonal.

**Four platforms, and two of them want the drawing without the tile.** macOS and
the web get a rounded square with a margin and a shadow, because that is how an
icon sits in a dock and beside a bookmark. Android and iOS mask the icon
themselves — a superellipse on one, whatever the launcher's shape is on the
other — so they get the picture edge to edge and opaque. Handing a rounded,
transparent tile to something that rounds its own corner is how an icon ends up
with two of them and a halo between; iOS rejects an alpha channel outright.
"""

import json
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

# Android's density buckets, and the pixel side of a launcher icon in each. The
# names are the resource directories, so this table is also where the files go.
ANDROID_SIZES = {
    'mipmap-mdpi': 48,
    'mipmap-hdpi': 72,
    'mipmap-xhdpi': 96,
    'mipmap-xxhdpi': 144,
    'mipmap-xxxhdpi': 192,
}

# What is drawn at, before reducing. Four times the largest is what it takes for
# the 16-pixel version to have a clean edge.
CANVAS = 4096

# macOS leaves the outer tenth alone and rounds what is left by about a fifth of
# its own width. Both numbers are Apple's, and getting them wrong is the
# difference between an icon that sits in the dock and one that shouts.
MARGIN = 0.098
RADIUS = 0.2237


def full_bleed(draw_content):
    """[draw_content] on an opaque square, edge to edge and corner to corner.

    What Android and iOS want. Every design below sizes itself off the square it
    is handed, so the same function draws the tile's inner face and this one and
    neither knows the difference.
    """
    image = Image.new('RGBA', (CANVAS, CANVAS), (0, 0, 0, 255))
    draw_content(image, ImageDraw.Draw(image))
    return image


def tile(draw_content):
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


def hillside(face, draw):
    """A crowd on sloping ground, and the box dragged round part of it.

    The three games before this one put a camera on a body. This one puts it
    over a map, and the order goes to whoever is inside a rectangle — so the
    rectangle is the icon. Without it this is a picture of some dots.
    """
    side = face.size[0]

    # Grass, lit from above.
    vertical_gradient(face, (112, 148, 78), (66, 100, 58))

    # The ridge: everything past it is the far side of the slope and stands in
    # shade. Two flat tones with a lit crest between them, rather than a
    # gradient — a camera this high sees no horizon, so a change of shade is
    # the only thing in this picture that can say "height", and it has to
    # survive being sixteen pixels wide.
    crest = ((0, side * 0.66), (side, side * 0.50))
    shade = Image.new('RGBA', face.size, (0, 0, 0, 0))
    ImageDraw.Draw(shade).polygon(
        [crest[0], crest[1], (side, side), (0, side)], fill=(6, 20, 12, 120)
    )
    face.alpha_composite(shade)
    draw = ImageDraw.Draw(face)
    draw.line(list(crest), fill=(168, 202, 122), width=int(side * 0.020))

    # Nine of them in three ranks, which is what a unit is from this height: a
    # disc and the shadow under it. The ranks lean with the slope, so the crowd
    # stands on the ground rather than on top of the picture.
    spacing = side * 0.215
    origin = (side * 0.245, side * 0.335)
    crowd = tuple(
        (origin[0] + column * spacing + row * spacing * 0.20,
         origin[1] + row * spacing * 0.72)
        for row in range(3)
        for column in range(3)
    )
    body = side * 0.058

    # The marquee: the box you drag round the ones about to be given an order.
    # Four of the nine are inside it and five are not, which is the whole
    # difference between this genre and the three before it — there, the thing
    # under the camera was the only thing there was.
    chosen = tuple(crowd[row * 3 + column] for row in (0, 1) for column in (0, 1))
    margin = body * 1.35
    box = (
        min(x for x, _ in chosen) - margin,
        min(y for _, y in chosen) - margin,
        max(x for x, _ in chosen) + margin,
        max(y for _, y in chosen) + margin,
    )

    # Under the crowd, so that being selected leaves a unit its own colour. A
    # wash painted over them turned four red discs brown, which reads as the
    # selection having gone out rather than come on.
    wash = Image.new('RGBA', face.size, (0, 0, 0, 0))
    ImageDraw.Draw(wash).rectangle(box, fill=(230, 252, 238, 46))
    face.alpha_composite(wash)
    draw = ImageDraw.Draw(face)

    for x, y in crowd:
        draw.ellipse(
            [x - body * 1.05, y + body * 0.30,
             x + body * 1.05, y + body * 1.25],
            fill=(20, 36, 24),
        )
    for x, y in crowd:
        draw.ellipse([x - body, y - body, x + body, y + body],
                     fill=(214, 84, 58))
        draw.ellipse(
            [x - body * 0.52, y - body * 0.70,
             x + body * 0.22, y - body * 0.02],
            fill=(250, 156, 122),
        )

    draw.rectangle(box, outline=(238, 252, 244), width=int(side * 0.019))


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
    'flutter3d_demo_strategy': hillside,
    'flutter3d_editor': editor,
}


def write(image, path, size, opaque=False):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    reduced = image.resize((size, size), Image.LANCZOS)
    if opaque:
        reduced = reduced.convert('RGB')
    reduced.save(path)


def ios_icons(appiconset):
    """The (filename, pixel side) pairs `Contents.json` in [appiconset] asks for.

    Read out of the catalogue rather than listed here, because the catalogue is
    what Xcode reads: a size added there and missing from a table in this file
    would be a hole in an app's icon set that nothing notices until the App
    Store rejects the upload. The pixel side is the point size times the scale,
    which is why `83.5x83.5@2x` is a 167-pixel file.
    """
    with open(os.path.join(appiconset, 'Contents.json')) as handle:
        catalogue = json.load(handle)
    # A filename can appear twice — the iPhone and iPad entries share several —
    # so this is keyed on the name and not a list.
    return {
        entry['filename']: round(
            float(entry['size'].split('x')[0]) * int(entry['scale'].rstrip('x'))
        )
        for entry in catalogue['images']
        if 'filename' in entry
    }


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
        image = tile(design)

        android = os.path.join(HERE, 'apps', app, 'android', 'app', 'src',
                               'main', 'res')
        appiconset = os.path.join(HERE, 'apps', app, 'ios', 'Runner',
                                  'Assets.xcassets', 'AppIcon.appiconset')
        # Drawn only if somebody wants it. The editor has neither mobile
        # platform, and a 4096-square nobody reduces is a second of nothing.
        picture = (full_bleed(design)
                   if os.path.isdir(android) or os.path.isdir(appiconset)
                   else None)

        if os.path.isdir(android):
            for bucket, size in ANDROID_SIZES.items():
                write(
                    picture,
                    os.path.join(root, 'apps', app, 'android', 'app', 'src',
                                 'main', 'res', bucket, 'ic_launcher.png'),
                    size,
                    opaque=True,
                )

        if os.path.isdir(appiconset):
            for name, size in ios_icons(appiconset).items():
                write(
                    picture,
                    os.path.join(root, 'apps', app, 'ios', 'Runner',
                                 'Assets.xcassets', 'AppIcon.appiconset', name),
                    size,
                    opaque=True,
                )

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
