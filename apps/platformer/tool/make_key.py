#!/usr/bin/env python3
"""Builds the key both games ship, from nothing.

    python3 tool/make_key.py

**Because the old one could not be licensed.** `key.glb` came from an archive
with no licence file, no author and no trail back to one, and both games placed
it — so the credits screen had to say "author unknown, licence untraced" to the
player, and the game could not be released at all. Nobody could fix that by
looking harder: an asset with no provenance does not acquire one.

So this one has provenance by construction. It is a hundred lines of arithmetic
in this repository, which is the same answer `make_textures.py`, `make_sounds.py`
and `make_music.py` already give for their own assets. Run it again and the file
is byte-identical, which is the point of it being a script rather than a
paragraph describing what somebody once did in Blender.

## What a key is, geometrically

Three parts on one axis: a **bow** you would hold, a **shaft**, and the **bit**
at the end that turns the lock. The bow is a torus, the shaft a cylinder, and the
bit two boxes — which is enough, because this thing is eighty pixels across on
screen and is recognised by its silhouette rather than by its detail.

Flat-shaded on purpose. Every face gets its own vertices and its own normal, so
the mesh is bigger in vertices than it needs to be and reads as something cast in
metal rather than something smooth. It also removes the whole question of normal
averaging at the seams, which is where a hand-rolled generator usually goes
wrong.
"""

import json
import math
import struct
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
GAMES = HERE.parent.parent

# Metres, and copied from the one this replaces rather than invented. It
# measured 0.25 wide by 0.72 tall once its node scale was
# applied, and both games place it by that size — a level document says where a
# key is, not how big. So these are chosen to land there rather than to be
# right about keys.
BOW_RADIUS = 0.10
BOW_THICKNESS = 0.030
SHAFT_RADIUS = 0.028
SHAFT_LENGTH = 0.46
TOOTH = (0.022, 0.055, 0.038)

# How many segments go round the two round parts. Past these the silhouette
# stops changing and the file goes on growing — at 0.26 m on screen the bow is a
# ring whether it has twenty-four sides or two hundred.
BOW_SEGMENTS = 24
BOW_RING = 8
SHAFT_SEGMENTS = 12


def main() -> int:
    positions: list[tuple[float, float, float]] = []
    normals: list[tuple[float, float, float]] = []
    indices: list[int] = []

    def face(*corners: tuple[float, float, float]) -> None:
        """Adds one flat polygon, fanned into triangles and given one normal.

        Wound counter-clockwise seen from outside, which is what glTF means by
        front-facing — and getting it wrong is a key you can see the inside of.
        """
        first = len(positions)
        ax, ay, az = corners[0]
        bx, by, bz = corners[1]
        cx, cy, cz = corners[2]
        ux, uy, uz = bx - ax, by - ay, bz - az
        vx, vy, vz = cx - ax, cy - ay, cz - az
        nx, ny, nz = (uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx)
        length = math.sqrt(nx * nx + ny * ny + nz * nz) or 1.0
        normal = (nx / length, ny / length, nz / length)
        for corner in corners:
            positions.append(corner)
            normals.append(normal)
        for i in range(1, len(corners) - 1):
            indices.extend((first, first + i, first + i + 1))

    _bow(face)
    _shaft(face)
    _bit(face)
    _centre(positions)

    blob = _glb(positions, normals, indices)
    for game in ('platformer', 'dungeon'):
        out = GAMES / game / 'assets' / 'models' / 'key.glb'
        out.write_bytes(blob)
        print(f'{out.relative_to(GAMES.parent)}  '
              f'{len(positions)} vertices, {len(blob) // 1024} KB')
    return 0


def _centre(positions) -> None:
    """Puts the middle of the key at the origin.

    The one it replaces was centred — its exporter's node carried a translation
    that put it there — and a level document says *where* a key is, not how big
    or which end is which. A model whose origin was at its teeth would sink half
    of every key into the floor of both games at once.
    """
    lows = [min(p[i] for p in positions) for i in range(3)]
    highs = [max(p[i] for p in positions) for i in range(3)]
    shift = [-(lows[i] + highs[i]) / 2 for i in range(3)]
    for i, (x, y, z) in enumerate(positions):
        positions[i] = (x + shift[0], y + shift[1], z + shift[2])
    print(f'  {highs[0] - lows[0]:.3f} x {highs[1] - lows[1]:.3f} x '
          f'{highs[2] - lows[2]:.3f} m')


def _bow(face) -> None:
    """The ring at the top, as a torus lying in the XY plane."""
    centre = (0.0, BOW_RADIUS + SHAFT_LENGTH * 0.5, 0.0)
    for i in range(BOW_SEGMENTS):
        a0 = 2 * math.pi * i / BOW_SEGMENTS
        a1 = 2 * math.pi * (i + 1) / BOW_SEGMENTS
        for j in range(BOW_RING):
            b0 = 2 * math.pi * j / BOW_RING
            b1 = 2 * math.pi * (j + 1) / BOW_RING
            face(
                _torus(centre, a0, b0),
                _torus(centre, a1, b0),
                _torus(centre, a1, b1),
                _torus(centre, a0, b1),
            )


def _torus(centre, around: float, through: float):
    cx, cy, cz = centre
    r = BOW_RADIUS + BOW_THICKNESS * math.cos(through)
    return (
        cx + r * math.cos(around),
        cy + r * math.sin(around),
        cz + BOW_THICKNESS * math.sin(through),
    )


def _shaft(face) -> None:
    """The stem, a closed cylinder down the Y axis."""
    top = SHAFT_LENGTH * 0.5
    bottom = -SHAFT_LENGTH * 0.5
    rim = []
    for i in range(SHAFT_SEGMENTS):
        a0 = 2 * math.pi * i / SHAFT_SEGMENTS
        a1 = 2 * math.pi * (i + 1) / SHAFT_SEGMENTS
        p0 = (SHAFT_RADIUS * math.cos(a0), 0.0, SHAFT_RADIUS * math.sin(a0))
        p1 = (SHAFT_RADIUS * math.cos(a1), 0.0, SHAFT_RADIUS * math.sin(a1))
        face(
            (p0[0], bottom, p0[2]),
            (p1[0], bottom, p1[2]),
            (p1[0], top, p1[2]),
            (p0[0], top, p0[2]),
        )
        rim.append(p0)

    # The two caps. Fanned from the centre rather than left open: a hole in a
    # solid is only invisible until the camera is inside it.
    face(*[(x, top, z) for x, _, z in rim])
    face(*[(x, bottom, z) for x, _, z in reversed(rim)])


def _bit(face) -> None:
    """The two teeth at the bottom, which are what makes it read as a key."""
    width, height, depth = TOOTH
    base = -SHAFT_LENGTH * 0.5
    for level, offset in ((base + 0.02, 0.0), (base + 0.11, 0.0)):
        x0, x1 = SHAFT_RADIUS * 0.5, SHAFT_RADIUS * 0.5 + width * 2.2
        y0, y1 = level, level + height
        z0, z1 = offset - depth * 0.5, offset + depth * 0.5
        _box(face, x0, x1, y0, y1, z0, z1)


def _box(face, x0, x1, y0, y1, z0, z1) -> None:
    face((x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1))
    face((x1, y0, z0), (x0, y0, z0), (x0, y1, z0), (x1, y1, z0))
    face((x1, y0, z1), (x1, y0, z0), (x1, y1, z0), (x1, y1, z1))
    face((x0, y0, z0), (x0, y0, z1), (x0, y1, z1), (x0, y1, z0))
    face((x0, y1, z1), (x1, y1, z1), (x1, y1, z0), (x0, y1, z0))
    face((x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1))


def _glb(positions, normals, indices) -> bytes:
    """Packs the mesh into a single-buffer binary glTF."""
    vertex_bytes = bytearray()
    for (px, py, pz), (nx, ny, nz) in zip(positions, normals):
        vertex_bytes += struct.pack('<6f', px, py, pz, nx, ny, nz)
    index_bytes = struct.pack(f'<{len(indices)}H', *indices)
    index_bytes += b'\x00' * ((4 - len(index_bytes) % 4) % 4)
    binary = bytes(vertex_bytes) + index_bytes

    lows = [min(p[i] for p in positions) for i in range(3)]
    highs = [max(p[i] for p in positions) for i in range(3)]

    doc = {
        'asset': {
            'version': '2.0',
            # Where it came from, in the file itself. The credits read from
            # `credits.dart`, but a model that travels should carry its own
            # provenance — that is exactly what the old key did not have.
            'generator': 'flutter3d apps/platformer/tool/make_key.py',
            'copyright': 'CC0 1.0 — generated by this repository, no rights reserved',
        },
        'scene': 0,
        'scenes': [{'nodes': [0]}],
        'nodes': [{'mesh': 0, 'name': 'key'}],
        'materials': [{
            'name': 'brass',
            'pbrMetallicRoughness': {
                # Warm and bright: it has to be found on a dark floor, and the
                # doors it opens are named by colour.
                'baseColorFactor': [0.92, 0.72, 0.26, 1.0],
                'metallicFactor': 0.9,
                'roughnessFactor': 0.35,
            },
        }],
        'meshes': [{
            'name': 'key',
            'primitives': [{
                'attributes': {'POSITION': 0, 'NORMAL': 1},
                'indices': 2,
                'material': 0,
            }],
        }],
        'buffers': [{'byteLength': len(binary)}],
        'bufferViews': [
            {'buffer': 0, 'byteOffset': 0,
             'byteLength': len(vertex_bytes), 'byteStride': 24, 'target': 34962},
            {'buffer': 0, 'byteOffset': len(vertex_bytes),
             'byteLength': len(index_bytes), 'target': 34963},
        ],
        'accessors': [
            {'bufferView': 0, 'byteOffset': 0, 'componentType': 5126,
             'count': len(positions), 'type': 'VEC3',
             'min': lows, 'max': highs},
            {'bufferView': 0, 'byteOffset': 12, 'componentType': 5126,
             'count': len(normals), 'type': 'VEC3'},
            {'bufferView': 1, 'byteOffset': 0, 'componentType': 5123,
             'count': len(indices), 'type': 'SCALAR'},
        ],
    }

    text = json.dumps(doc, separators=(',', ':')).encode('utf-8')
    text += b' ' * ((4 - len(text) % 4) % 4)
    blob = bytearray(struct.pack('<III', 0x46546C67, 2,
                                 12 + 8 + len(text) + 8 + len(binary)))
    blob += struct.pack('<II', len(text), 0x4E4F534A) + text
    blob += struct.pack('<II', len(binary), 0x004E4942) + bytes(binary)
    return bytes(blob)


if __name__ == '__main__':
    sys.exit(main())
