#!/usr/bin/env python3
"""Writes the game's surface textures as tileable PNGs.

    python3 tool/make_textures.py

Generated rather than sourced, for the reason `assets/models/LICENSES.md`
records: `apps/flutter3d_demo_dungeon` carries a debt because its maps have no licence traced,
and a second game repeating that would repeat a known mistake. Everything here
is lattice noise and arithmetic written in this file.

Each material gets three maps, which is what `LevelMaterial` reads:

  * `<name>_albedo.png` — colour
  * `<name>_normal.png` — tangent-space normal, derived from the same height
    field the colour is shaded by, so the two never disagree
  * `<name>_orm.png` — occlusion, roughness, metallic in R, G, B, the glTF
    packing the engine already expects

Tileable by construction: the noise lattice wraps, so a floor made of many
brushes has no seam at their joins.
"""

import math
import struct
import zlib
from pathlib import Path

SIDE = 256
OUT = Path(__file__).resolve().parent.parent / "assets" / "textures"


# --- PNG, written by hand because Pillow is not a dependency of anything here ---


def write_png(path, rows):
    """`rows` is a list of `bytes`, one per scanline, RGB8."""
    raw = b"".join(b"\x00" + row for row in rows)

    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", SIDE, SIDE, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    path.write_bytes(png)
    print(f"  {path.name}  {len(png) // 1024} KB")


# --- noise ---


def _hash(x, y, seed):
    h = (x * 374761393 + y * 668265263 + seed * 1442695040888963407) & 0xFFFFFFFF
    h = (h ^ (h >> 13)) * 1274126177 & 0xFFFFFFFF
    return ((h ^ (h >> 16)) & 0xFFFF) / 65535.0


def _smooth(t):
    return t * t * (3.0 - 2.0 * t)


def value_noise(u, v, cells, seed):
    """Lattice noise on a `cells`×`cells` grid, wrapping at the edges."""
    x, y = u * cells, v * cells
    x0, y0 = int(math.floor(x)), int(math.floor(y))
    fx, fy = _smooth(x - x0), _smooth(y - y0)
    x0 %= cells
    y0 %= cells
    x1, y1 = (x0 + 1) % cells, (y0 + 1) % cells
    a = _hash(x0, y0, seed)
    b = _hash(x1, y0, seed)
    c = _hash(x0, y1, seed)
    d = _hash(x1, y1, seed)
    return (a + (b - a) * fx) + ((c + (d - c) * fx) - (a + (b - a) * fx)) * fy


def fbm(u, v, seed, octaves=4, cells=4):
    total, amplitude, weight = 0.0, 1.0, 0.0
    for i in range(octaves):
        total += value_noise(u, v, cells * (1 << i), seed + i * 17) * amplitude
        weight += amplitude
        amplitude *= 0.5
    return total / weight


# --- materials: each returns (colour, height, roughness, metallic) at (u, v) ---


def stone(u, v):
    # Blocks with mortar between them, and grain inside each block.
    rows, cols = 4, 4
    row = int(v * rows)
    # Every other course offset by half a block, the way a wall is laid.
    shift = 0.5 if row % 2 else 0.0
    bx = (u * cols + shift) % 1.0
    by = (v * rows) % 1.0
    edge = min(bx, 1.0 - bx, by, 1.0 - by)
    mortar = _smooth(min(1.0, edge / 0.06))

    grain = fbm(u, v, 11, cells=8)
    tone = 0.38 + 0.16 * grain
    colour = (tone * 0.98, tone * 0.97, tone)
    if mortar < 1.0:
        dark = 0.55 + 0.45 * mortar
        colour = tuple(c * dark for c in colour)
    height = mortar * (0.7 + 0.3 * grain)
    return colour, height, 0.82 - 0.1 * grain, 0.0


def moss(u, v):
    # Organic and uneven: two noise fields, one for tufts and one for damp.
    tuft = fbm(u, v, 3, cells=6)
    damp = fbm(u, v, 29, octaves=3, cells=3)
    green = 0.34 + 0.30 * tuft
    colour = (0.16 + 0.14 * damp, green, 0.14 + 0.10 * tuft)
    return colour, tuft, 0.95 - 0.15 * damp, 0.0


def brass(u, v):
    # Brushed: noise stretched along one axis, which is what makes metal read
    # as metal at a glance.
    streak = fbm(u * 0.15, v, 7, cells=8)
    spot = fbm(u, v, 71, octaves=2, cells=2)
    tone = 0.62 + 0.28 * streak
    colour = (tone, tone * 0.78, tone * 0.34)
    return colour, streak * 0.4, 0.28 + 0.25 * spot, 0.9


def ice(u, v):
    # Cracks: ridged noise, which is |2n-1| inverted — cheap and convincing.
    ridge = 1.0 - abs(2.0 * fbm(u, v, 41, cells=5) - 1.0)
    crack = _smooth(min(1.0, max(0.0, (ridge - 0.72) / 0.12)))
    tone = 0.72 + 0.2 * fbm(u, v, 43, octaves=3, cells=3)
    colour = (tone * 0.78, tone * 0.9, tone)
    colour = tuple(c * (1.0 - 0.35 * crack) for c in colour)
    return colour, 1.0 - crack, 0.12 + 0.3 * crack, 0.0


def wood(u, v):
    # Planks along one axis, with rings inside each.
    planks = 5
    p = (v * planks) % 1.0
    seam = _smooth(min(1.0, min(p, 1.0 - p) / 0.05))
    rings = fbm(u * 3.0, v * 0.3, 59, cells=6)
    tone = 0.34 + 0.20 * rings
    colour = (tone, tone * 0.72, tone * 0.46)
    colour = tuple(c * (0.6 + 0.4 * seam) for c in colour)
    return colour, seam * (0.6 + 0.4 * rings), 0.7 + 0.2 * rings, 0.0


MATERIALS = {
    "stone": stone,
    "moss": moss,
    "brass": brass,
    "ice": ice,
    "wood": wood,
}


def build(name, shade):
    OUT.mkdir(parents=True, exist_ok=True)
    print(f"{name}:")

    colours, heights, orm = [], [], []
    for j in range(SIDE):
        v = j / SIDE
        crow, hrow, orow = [], [], []
        for i in range(SIDE):
            u = i / SIDE
            colour, height, rough, metal = shade(u, v)
            crow.append(colour)
            hrow.append(height)
            orow.append((1.0, rough, metal))
        colours.append(crow)
        heights.append(hrow)
        orm.append(orow)

    def byte(x):
        return max(0, min(255, int(x * 255.0 + 0.5)))

    write_png(
        OUT / f"{name}_albedo.png",
        [bytes(byte(c) for px in row for c in px) for row in colours],
    )
    write_png(
        OUT / f"{name}_orm.png",
        [bytes(byte(c) for px in row for c in px) for row in orm],
    )

    # Normals from the height field by central differences. The scale is in
    # texels, so a taller `strength` is a deeper-looking surface without
    # touching the geometry.
    strength = 2.5
    rows = []
    for j in range(SIDE):
        row = bytearray()
        for i in range(SIDE):
            left = heights[j][(i - 1) % SIDE]
            right = heights[j][(i + 1) % SIDE]
            up = heights[(j - 1) % SIDE][i]
            down = heights[(j + 1) % SIDE][i]
            nx, ny, nz = (left - right) * strength, (up - down) * strength, 1.0
            length = math.sqrt(nx * nx + ny * ny + nz * nz)
            row += bytes(
                (
                    byte(nx / length * 0.5 + 0.5),
                    byte(ny / length * 0.5 + 0.5),
                    byte(nz / length * 0.5 + 0.5),
                )
            )
        rows.append(bytes(row))
    write_png(OUT / f"{name}_normal.png", rows)


if __name__ == "__main__":
    for name, shade in MATERIALS.items():
        build(name, shade)
