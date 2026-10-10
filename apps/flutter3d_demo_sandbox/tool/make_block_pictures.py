#!/usr/bin/env python3
"""Turns ambientCG's material downloads into the block pictures this game ships.

    python3 tool/make_block_pictures.py ~/Downloads/ambientcg

The directory holds each material unzipped into a folder of its own name,
as ambientCG's `<Id>_1K-JPG.zip` unpacks: `Rock030/Rock030_1K-JPG_Color.jpg`
and so on. Every one of them is CC0 (see `assets/blocks/CREDITS.md`). Only
the colour and the OpenGL normal map of each are read; the rest of the
download, scripts and scene files included, is never touched.

What happens to them:

* each is taken down to 256 pixels, a block face being a metre and seen from
  a few metres away at most;
* stone, sand and planks are brightened or darkened so the blocks sit
  together under one sun, rather than each at its photographer's exposure;
* the grass side is made here, from the dirt and the grass: earth with a
  fringe of turf hanging over its top edge, ragged along the bottom and
  casting a little shade onto the earth below it. The fringe is a sum of
  whole-period waves across the picture, so a row of grass blocks shows one
  unbroken fringe;
* the gold block is ambientCG's rough gold with a bevel worked into its
  border, in the colour and in the normal map, so a gold block reads as a
  cast ingot rather than as a yellow box.

Run it again on the same downloads and the result is the same.
"""

import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image

SIZE = 256
OUT = Path(__file__).resolve().parent.parent / 'assets' / 'blocks'


def load(root, asset, map_name):
    """One map of an ambientCG material, at SIZE, as floats in 0..1."""
    path = root / asset / f'{asset}_1K-JPG_{map_name}.jpg'
    image = Image.open(path).convert('RGB').resize((SIZE, SIZE), Image.LANCZOS)
    return np.asarray(image, dtype=np.float64) / 255.0


def save(pixels, name):
    """Writes pixels in 0..1 as a JPEG beside the others."""
    data = (np.clip(pixels, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
    Image.fromarray(data, 'RGB').save(OUT / f'{name}.jpg', quality=90)


def graded(colour, brightness=1.0, saturation=1.0, contrast=1.0):
    """The colour scaled in brightness, pushed from or towards grey, and its
    light and dark spread from or drawn towards the picture's average."""
    average = colour.mean(axis=(0, 1), keepdims=True)
    colour = average + (colour - average) * contrast
    grey = colour.mean(axis=2, keepdims=True)
    return (grey + (colour - grey) * saturation) * brightness


def plain(root, asset, name, **grade):
    """A surface that is one material, its colour graded."""
    save(graded(load(root, asset, 'Color'), **grade), name)
    save(load(root, asset, 'NormalGL'), f'{name}_normal')


def grass_side(root, dirt, grass):
    """Earth under a ragged fringe of turf."""
    x = np.arange(SIZE) / SIZE
    # How far down the turf hangs in each column, as a fraction of the face:
    # waves that fit the picture a whole number of times, so it repeats.
    hang = (
        0.17
        + 0.035 * np.sin(2 * math.pi * 3 * x + 0.4)
        + 0.02 * np.sin(2 * math.pi * 7 * x + 1.9)
        + 0.03 * (1.0 - np.abs(np.sin(math.pi * 23 * x)))
        + 0.015 * (1.0 - np.abs(np.sin(math.pi * 41 * x + 0.6)))
    )
    y = (np.arange(SIZE) / SIZE)[:, None]
    edge = hang[None, :] - y
    # Turf where the column's fringe reaches, softened over a pixel.
    turf = np.clip(edge * SIZE + 0.5, 0.0, 1.0)[..., None]
    # The shade the fringe throws on the earth just under it.
    shade = 1.0 - 0.45 * np.clip(1.0 + edge * SIZE / 6.0, 0.0, 1.0)[..., None]
    shade = np.where(turf > 0.0, 1.0, shade)
    earth = load(root, dirt, 'Color') * shade
    # The turf seen from the side is the grass a little darker at its tips.
    blades = graded(load(root, grass, 'Color'), brightness=0.92)
    save(earth * (1.0 - turf) + blades * turf, 'grass_side')
    normal = load(root, dirt, 'NormalGL') * (1.0 - turf)
    save(normal + load(root, grass, 'NormalGL') * turf, 'grass_side_normal')


def gold(root, asset):
    """Rough gold, bevelled round its border."""
    i = np.arange(SIZE) + 0.5
    # Distance in pixels to the nearest edge, per axis and overall.
    dx = np.minimum(i, SIZE - i)[None, :].repeat(SIZE, 0)
    dy = np.minimum(i, SIZE - i)[:, None].repeat(SIZE, 1)
    bevel = 14.0
    height = np.clip(np.minimum(dx, dy) / bevel, 0.0, 1.0)
    height = height * height * (3.0 - 2.0 * height)
    # Slopes of the bevel, as a normal: x right, y up the picture.
    gy, gx = np.gradient(height * bevel * 0.6)
    n = np.stack([-gx, gy, np.ones_like(gx)], axis=2)
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    detail = load(root, asset, 'NormalGL') * 2.0 - 1.0
    # The metal's own grain on top of the bevel, its tilt added on.
    n[..., :2] += detail[..., :2]
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    save(n * 0.5 + 0.5, 'gold_normal')
    # Deeper and warmer than the photograph: with no sky for it to mirror,
    # a pale gold reads as yellow paint.
    colour = graded(load(root, asset, 'Color'), brightness=0.85, saturation=1.9)
    # The bevel a shade deeper, where the casting is thicker at its rim.
    save(colour * (0.78 + 0.22 * height[..., None]), 'gold')


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    root = Path(sys.argv[1]).expanduser()
    plain(root, 'Rock030', 'stone', brightness=1.3, saturation=0.9)
    plain(root, 'Ground106', 'dirt')
    plain(root, 'Grass004', 'grass_top')
    # The sand is a beach photographed in flat light: darker and with its
    # ripples drawn out, or a field of it is a blank cream under the sun.
    plain(root, 'Ground093A', 'sand', brightness=0.8, saturation=1.15,
          contrast=2.2)
    plain(root, 'Bricks085', 'brick')
    plain(root, 'Planks037A', 'planks', brightness=1.3, saturation=1.05)
    grass_side(root, 'Ground106', 'Grass004')
    gold(root, 'Metal048C')


if __name__ == '__main__':
    main()
