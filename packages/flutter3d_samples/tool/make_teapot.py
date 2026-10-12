#!/usr/bin/env python3
"""Writes `assets/teapot.obj`: the Utah teapot, tessellated here from its
Bezier patches.

    python3 tool/make_teapot.py

**Why it is generated rather than downloaded.** The OBJ this package used to
ship came from a repository that declares no licence, and a test fixture
published on pub.dev is redistributed with every download. The patches below
are Martin Newell's 1975 teapot as three.js carries them in
`examples/jsm/geometries/TeapotGeometry.js` (r160), whose code is MIT:

    The MIT License
    Copyright (c) 2010-2023 three.js authors
    Permission is hereby granted, free of charge, to any person obtaining a
    copy of this software and associated documentation files (the
    "Software"), to deal in the Software without restriction, including
    without limitation the rights to use, copy, modify, merge, publish,
    distribute, sublicense, and/or sell copies of the Software, and to
    permit persons to whom the Software is furnished to do so, subject to
    the following conditions: The above copyright notice and this
    permission notice shall be included in all copies or substantial
    portions of the Software. THE SOFTWARE IS PROVIDED "AS IS", WITHOUT
    WARRANTY OF ANY KIND, EXPRESS OR IMPLIED.

The tessellation is the classic one: six segments a patch edge, 32 patches,
2256 triangles once the triangles that collapse at the lid's knob and the
bottom's centre are dropped. Newell's units, not Blinn's: the teapot stands
3.15 tall with its rim at 2.4, as the file it replaces did. Y is up, the
spout points along +x, and the faces wind counter-clockwise seen from
outside. No normals and no materials, on purpose: this is the fixture for an
OBJ that has neither, so the loader has to generate smooth ones.

It writes `teapot.stl` beside it too, the same triangles as binary STL in
the form `StlWriter` gives (the header `flutter3d teapot`, each facet's
normal its own cross product, no attribute bytes): the fixture for a real
STL, which a person would bring in from a CAD tool in millimetres.
`f3d/teapot.f3d` is converted from the OBJ afterwards, from
`packages/flutter3d`:

    dart run flutter3d_build:convert ../flutter3d_samples/assets/teapot.obj \\
        -o ../flutter3d_samples/assets/f3d/teapot.f3d
"""

import math
import os
import struct

SEGMENTS = 6


def bernstein(t):
    s = 1.0 - t
    return (s * s * s, 3.0 * t * s * s, 3.0 * t * t * s, t * t * t)


def evaluate(points, u, v):
    bu, bv = bernstein(u), bernstein(v)
    x = y = z = 0.0
    for i in range(4):
        for j in range(4):
            w = bu[i] * bv[j]
            px, py, pz = points[i * 4 + j]
            x += w * px
            y += w * py
            z += w * pz
    # Newell's z is up; this file's y is.
    return (x, z, -y)


def key(p):
    return tuple(round(c, 5) + 0.0 for c in p)


def main():
    index = {}
    positions = []
    triangles = []

    # Welded within a part (rim and body, handle, spout, lid, bottom), never
    # across two: where the handle's end touches the body, a shared vertex
    # would average two surfaces that meet at a sharp angle into a normal
    # that faces away from one of them.
    def vertex(part, p):
        k = key(p)
        if (part, k) not in index:
            index[(part, k)] = len(positions) + 1
            positions.append(k)
        return index[(part, k)]

    for number_, patch in enumerate(PATCHES):
        part = PART[number_]
        points = [VERTICES[i] for i in patch]
        grid = [
            [vertex(part, evaluate(points, a / SEGMENTS, b / SEGMENTS))
             for b in range(SEGMENTS + 1)]
            for a in range(SEGMENTS + 1)
        ]
        for a in range(SEGMENTS):
            for b in range(SEGMENTS):
                v00, v01 = grid[a][b], grid[a][b + 1]
                v10, v11 = grid[a + 1][b], grid[a + 1][b + 1]
                for tri in ((v00, v10, v01), (v10, v11, v01)):
                    if len(set(tri)) == 3:
                        triangles.append(tri)

    # Counter-clockwise from outside: the signed volume is positive.
    def volume(tris):
        total = 0.0
        for a, b, c in tris:
            (ax, ay, az), (bx, by, bz), (cx, cy, cz) = (
                positions[a - 1], positions[b - 1], positions[c - 1])
            total += (ax * (by * cz - bz * cy) - ay * (bx * cz - bz * cx)
                      + az * (bx * cy - by * cx))
        return total

    if volume(triangles) < 0:
        triangles = [(a, c, b) for a, b, c in triangles]

    def number(c):
        text = ('%.6f' % c).rstrip('0').rstrip('.')
        return '0' if text in ('-0', '') else text

    out = [
        '# The Utah teapot (Martin Newell, 1975), tessellated by',
        '# tool/make_teapot.py from the Bezier patches three.js carries (MIT).',
        '# %d vertices, %d triangles. Do not edit; run the script.'
        % (len(positions), len(triangles)),
        'o teapot',
    ]
    out += ['v %s %s %s' % tuple(number(c) for c in p) for p in positions]
    out += ['f %d %d %d' % t for t in triangles]
    here = os.path.dirname(os.path.abspath(__file__))
    with open(os.path.join(here, '..', 'assets', 'teapot.obj'), 'w') as f:
        f.write('\n'.join(out) + '\n')
    print('teapot.obj: %d vertices, %d triangles' % (len(positions), len(triangles)))

    stl = bytearray(b'flutter3d teapot'.ljust(80, b'\0'))
    stl += struct.pack('<I', len(triangles))
    for t in triangles:
        a, b, c = (positions[i - 1] for i in t)
        u = [b[k] - a[k] for k in range(3)]
        w = [c[k] - a[k] for k in range(3)]
        n = [u[1] * w[2] - u[2] * w[1], u[2] * w[0] - u[0] * w[2],
             u[0] * w[1] - u[1] * w[0]]
        length = math.sqrt(sum(x * x for x in n))
        n = [x / length for x in n] if length > 0 else [0.0, 0.0, 0.0]
        stl += struct.pack('<12fH', *n, *a, *b, *c, 0)
    with open(os.path.join(here, '..', 'assets', 'teapot.stl'), 'wb') as f:
        f.write(bytes(stl))
    print('teapot.stl: %d facets' % len(triangles))


# The part each patch belongs to, in the order below: 4 rim and 8 body
# patches (one surface), 4 handle, 4 spout, 8 lid, 4 bottom.
PART = (['body'] * 12 + ['handle'] * 4 + ['spout'] * 4 + ['lid'] * 8
        + ['bottom'] * 4)

# Newell's 32 patches as three.js lists them: 16 control-point indices each,
# rim, body, handle, spout, lid and bottom, into the table below.
PATCHES = [
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
    [3, 16, 17, 18, 7, 19, 20, 21, 11, 22, 23, 24, 15, 25, 26, 27],
    [18, 28, 29, 30, 21, 31, 32, 33, 24, 34, 35, 36, 27, 37, 38, 39],
    [30, 40, 41, 0, 33, 42, 43, 4, 36, 44, 45, 8, 39, 46, 47, 12],
    [12, 13, 14, 15, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59],
    [15, 25, 26, 27, 51, 60, 61, 62, 55, 63, 64, 65, 59, 66, 67, 68],
    [27, 37, 38, 39, 62, 69, 70, 71, 65, 72, 73, 74, 68, 75, 76, 77],
    [39, 46, 47, 12, 71, 78, 79, 48, 74, 80, 81, 52, 77, 82, 83, 56],
    [56, 57, 58, 59, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95],
    [59, 66, 67, 68, 87, 96, 97, 98, 91, 99, 100, 101, 95, 102, 103, 104],
    [68, 75, 76, 77, 98, 105, 106, 107, 101, 108, 109, 110, 104, 111, 112, 113],
    [77, 82, 83, 56, 107, 114, 115, 84, 110, 116, 117, 88, 113, 118, 119, 92],
    [120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135],
    [123, 136, 137, 120, 127, 138, 139, 124, 131, 140, 141, 128, 135, 142, 143, 132],
    [132, 133, 134, 135, 144, 145, 146, 147, 148, 149, 150, 151, 68, 152, 153, 154],
    [135, 142, 143, 132, 147, 155, 156, 144, 151, 157, 158, 148, 154, 159, 160, 68],
    [161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176],
    [164, 177, 178, 161, 168, 179, 180, 165, 172, 181, 182, 169, 176, 183, 184, 173],
    [173, 174, 175, 176, 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196],
    [176, 183, 184, 173, 188, 197, 198, 185, 192, 199, 200, 189, 196, 201, 202, 193],
    [203, 203, 203, 203, 204, 205, 206, 207, 208, 208, 208, 208, 209, 210, 211, 212],
    [203, 203, 203, 203, 207, 213, 214, 215, 208, 208, 208, 208, 212, 216, 217, 218],
    [203, 203, 203, 203, 215, 219, 220, 221, 208, 208, 208, 208, 218, 222, 223, 224],
    [203, 203, 203, 203, 221, 225, 226, 204, 208, 208, 208, 208, 224, 227, 228, 209],
    [209, 210, 211, 212, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 240],
    [212, 216, 217, 218, 232, 241, 242, 243, 236, 244, 245, 246, 240, 247, 248, 249],
    [218, 222, 223, 224, 243, 250, 251, 252, 246, 253, 254, 255, 249, 256, 257, 258],
    [224, 227, 228, 209, 252, 259, 260, 229, 255, 261, 262, 233, 258, 263, 264, 237],
    [265, 265, 265, 265, 266, 267, 268, 269, 270, 271, 272, 273, 92, 119, 118, 113],
    [265, 265, 265, 265, 269, 274, 275, 276, 273, 277, 278, 279, 113, 112, 111, 104],
    [265, 265, 265, 265, 276, 280, 281, 282, 279, 283, 284, 285, 104, 103, 102, 95],
    [265, 265, 265, 265, 282, 286, 287, 266, 285, 288, 289, 270, 95, 94, 93, 92],
]

VERTICES = [
    (1.4, 0, 2.4),
    (1.4, -0.784, 2.4),
    (0.784, -1.4, 2.4),
    (0, -1.4, 2.4),
    (1.3375, 0, 2.53125),
    (1.3375, -0.749, 2.53125),
    (0.749, -1.3375, 2.53125),
    (0, -1.3375, 2.53125),
    (1.4375, 0, 2.53125),
    (1.4375, -0.805, 2.53125),
    (0.805, -1.4375, 2.53125),
    (0, -1.4375, 2.53125),
    (1.5, 0, 2.4),
    (1.5, -0.84, 2.4),
    (0.84, -1.5, 2.4),
    (0, -1.5, 2.4),
    (-0.784, -1.4, 2.4),
    (-1.4, -0.784, 2.4),
    (-1.4, 0, 2.4),
    (-0.749, -1.3375, 2.53125),
    (-1.3375, -0.749, 2.53125),
    (-1.3375, 0, 2.53125),
    (-0.805, -1.4375, 2.53125),
    (-1.4375, -0.805, 2.53125),
    (-1.4375, 0, 2.53125),
    (-0.84, -1.5, 2.4),
    (-1.5, -0.84, 2.4),
    (-1.5, 0, 2.4),
    (-1.4, 0.784, 2.4),
    (-0.784, 1.4, 2.4),
    (0, 1.4, 2.4),
    (-1.3375, 0.749, 2.53125),
    (-0.749, 1.3375, 2.53125),
    (0, 1.3375, 2.53125),
    (-1.4375, 0.805, 2.53125),
    (-0.805, 1.4375, 2.53125),
    (0, 1.4375, 2.53125),
    (-1.5, 0.84, 2.4),
    (-0.84, 1.5, 2.4),
    (0, 1.5, 2.4),
    (0.784, 1.4, 2.4),
    (1.4, 0.784, 2.4),
    (0.749, 1.3375, 2.53125),
    (1.3375, 0.749, 2.53125),
    (0.805, 1.4375, 2.53125),
    (1.4375, 0.805, 2.53125),
    (0.84, 1.5, 2.4),
    (1.5, 0.84, 2.4),
    (1.75, 0, 1.875),
    (1.75, -0.98, 1.875),
    (0.98, -1.75, 1.875),
    (0, -1.75, 1.875),
    (2, 0, 1.35),
    (2, -1.12, 1.35),
    (1.12, -2, 1.35),
    (0, -2, 1.35),
    (2, 0, 0.9),
    (2, -1.12, 0.9),
    (1.12, -2, 0.9),
    (0, -2, 0.9),
    (-0.98, -1.75, 1.875),
    (-1.75, -0.98, 1.875),
    (-1.75, 0, 1.875),
    (-1.12, -2, 1.35),
    (-2, -1.12, 1.35),
    (-2, 0, 1.35),
    (-1.12, -2, 0.9),
    (-2, -1.12, 0.9),
    (-2, 0, 0.9),
    (-1.75, 0.98, 1.875),
    (-0.98, 1.75, 1.875),
    (0, 1.75, 1.875),
    (-2, 1.12, 1.35),
    (-1.12, 2, 1.35),
    (0, 2, 1.35),
    (-2, 1.12, 0.9),
    (-1.12, 2, 0.9),
    (0, 2, 0.9),
    (0.98, 1.75, 1.875),
    (1.75, 0.98, 1.875),
    (1.12, 2, 1.35),
    (2, 1.12, 1.35),
    (1.12, 2, 0.9),
    (2, 1.12, 0.9),
    (2, 0, 0.45),
    (2, -1.12, 0.45),
    (1.12, -2, 0.45),
    (0, -2, 0.45),
    (1.5, 0, 0.225),
    (1.5, -0.84, 0.225),
    (0.84, -1.5, 0.225),
    (0, -1.5, 0.225),
    (1.5, 0, 0.15),
    (1.5, -0.84, 0.15),
    (0.84, -1.5, 0.15),
    (0, -1.5, 0.15),
    (-1.12, -2, 0.45),
    (-2, -1.12, 0.45),
    (-2, 0, 0.45),
    (-0.84, -1.5, 0.225),
    (-1.5, -0.84, 0.225),
    (-1.5, 0, 0.225),
    (-0.84, -1.5, 0.15),
    (-1.5, -0.84, 0.15),
    (-1.5, 0, 0.15),
    (-2, 1.12, 0.45),
    (-1.12, 2, 0.45),
    (0, 2, 0.45),
    (-1.5, 0.84, 0.225),
    (-0.84, 1.5, 0.225),
    (0, 1.5, 0.225),
    (-1.5, 0.84, 0.15),
    (-0.84, 1.5, 0.15),
    (0, 1.5, 0.15),
    (1.12, 2, 0.45),
    (2, 1.12, 0.45),
    (0.84, 1.5, 0.225),
    (1.5, 0.84, 0.225),
    (0.84, 1.5, 0.15),
    (1.5, 0.84, 0.15),
    (-1.6, 0, 2.025),
    (-1.6, -0.3, 2.025),
    (-1.5, -0.3, 2.25),
    (-1.5, 0, 2.25),
    (-2.3, 0, 2.025),
    (-2.3, -0.3, 2.025),
    (-2.5, -0.3, 2.25),
    (-2.5, 0, 2.25),
    (-2.7, 0, 2.025),
    (-2.7, -0.3, 2.025),
    (-3, -0.3, 2.25),
    (-3, 0, 2.25),
    (-2.7, 0, 1.8),
    (-2.7, -0.3, 1.8),
    (-3, -0.3, 1.8),
    (-3, 0, 1.8),
    (-1.5, 0.3, 2.25),
    (-1.6, 0.3, 2.025),
    (-2.5, 0.3, 2.25),
    (-2.3, 0.3, 2.025),
    (-3, 0.3, 2.25),
    (-2.7, 0.3, 2.025),
    (-3, 0.3, 1.8),
    (-2.7, 0.3, 1.8),
    (-2.7, 0, 1.575),
    (-2.7, -0.3, 1.575),
    (-3, -0.3, 1.35),
    (-3, 0, 1.35),
    (-2.5, 0, 1.125),
    (-2.5, -0.3, 1.125),
    (-2.65, -0.3, 0.9375),
    (-2.65, 0, 0.9375),
    (-2, -0.3, 0.9),
    (-1.9, -0.3, 0.6),
    (-1.9, 0, 0.6),
    (-3, 0.3, 1.35),
    (-2.7, 0.3, 1.575),
    (-2.65, 0.3, 0.9375),
    (-2.5, 0.3, 1.125),
    (-1.9, 0.3, 0.6),
    (-2, 0.3, 0.9),
    (1.7, 0, 1.425),
    (1.7, -0.66, 1.425),
    (1.7, -0.66, 0.6),
    (1.7, 0, 0.6),
    (2.6, 0, 1.425),
    (2.6, -0.66, 1.425),
    (3.1, -0.66, 0.825),
    (3.1, 0, 0.825),
    (2.3, 0, 2.1),
    (2.3, -0.25, 2.1),
    (2.4, -0.25, 2.025),
    (2.4, 0, 2.025),
    (2.7, 0, 2.4),
    (2.7, -0.25, 2.4),
    (3.3, -0.25, 2.4),
    (3.3, 0, 2.4),
    (1.7, 0.66, 0.6),
    (1.7, 0.66, 1.425),
    (3.1, 0.66, 0.825),
    (2.6, 0.66, 1.425),
    (2.4, 0.25, 2.025),
    (2.3, 0.25, 2.1),
    (3.3, 0.25, 2.4),
    (2.7, 0.25, 2.4),
    (2.8, 0, 2.475),
    (2.8, -0.25, 2.475),
    (3.525, -0.25, 2.49375),
    (3.525, 0, 2.49375),
    (2.9, 0, 2.475),
    (2.9, -0.15, 2.475),
    (3.45, -0.15, 2.5125),
    (3.45, 0, 2.5125),
    (2.8, 0, 2.4),
    (2.8, -0.15, 2.4),
    (3.2, -0.15, 2.4),
    (3.2, 0, 2.4),
    (3.525, 0.25, 2.49375),
    (2.8, 0.25, 2.475),
    (3.45, 0.15, 2.5125),
    (2.9, 0.15, 2.475),
    (3.2, 0.15, 2.4),
    (2.8, 0.15, 2.4),
    (0, 0, 3.15),
    (0.8, 0, 3.15),
    (0.8, -0.45, 3.15),
    (0.45, -0.8, 3.15),
    (0, -0.8, 3.15),
    (0, 0, 2.85),
    (0.2, 0, 2.7),
    (0.2, -0.112, 2.7),
    (0.112, -0.2, 2.7),
    (0, -0.2, 2.7),
    (-0.45, -0.8, 3.15),
    (-0.8, -0.45, 3.15),
    (-0.8, 0, 3.15),
    (-0.112, -0.2, 2.7),
    (-0.2, -0.112, 2.7),
    (-0.2, 0, 2.7),
    (-0.8, 0.45, 3.15),
    (-0.45, 0.8, 3.15),
    (0, 0.8, 3.15),
    (-0.2, 0.112, 2.7),
    (-0.112, 0.2, 2.7),
    (0, 0.2, 2.7),
    (0.45, 0.8, 3.15),
    (0.8, 0.45, 3.15),
    (0.112, 0.2, 2.7),
    (0.2, 0.112, 2.7),
    (0.4, 0, 2.55),
    (0.4, -0.224, 2.55),
    (0.224, -0.4, 2.55),
    (0, -0.4, 2.55),
    (1.3, 0, 2.55),
    (1.3, -0.728, 2.55),
    (0.728, -1.3, 2.55),
    (0, -1.3, 2.55),
    (1.3, 0, 2.4),
    (1.3, -0.728, 2.4),
    (0.728, -1.3, 2.4),
    (0, -1.3, 2.4),
    (-0.224, -0.4, 2.55),
    (-0.4, -0.224, 2.55),
    (-0.4, 0, 2.55),
    (-0.728, -1.3, 2.55),
    (-1.3, -0.728, 2.55),
    (-1.3, 0, 2.55),
    (-0.728, -1.3, 2.4),
    (-1.3, -0.728, 2.4),
    (-1.3, 0, 2.4),
    (-0.4, 0.224, 2.55),
    (-0.224, 0.4, 2.55),
    (0, 0.4, 2.55),
    (-1.3, 0.728, 2.55),
    (-0.728, 1.3, 2.55),
    (0, 1.3, 2.55),
    (-1.3, 0.728, 2.4),
    (-0.728, 1.3, 2.4),
    (0, 1.3, 2.4),
    (0.224, 0.4, 2.55),
    (0.4, 0.224, 2.55),
    (0.728, 1.3, 2.55),
    (1.3, 0.728, 2.55),
    (0.728, 1.3, 2.4),
    (1.3, 0.728, 2.4),
    (0, 0, 0),
    (1.425, 0, 0),
    (1.425, 0.798, 0),
    (0.798, 1.425, 0),
    (0, 1.425, 0),
    (1.5, 0, 0.075),
    (1.5, 0.84, 0.075),
    (0.84, 1.5, 0.075),
    (0, 1.5, 0.075),
    (-0.798, 1.425, 0),
    (-1.425, 0.798, 0),
    (-1.425, 0, 0),
    (-0.84, 1.5, 0.075),
    (-1.5, 0.84, 0.075),
    (-1.5, 0, 0.075),
    (-1.425, -0.798, 0),
    (-0.798, -1.425, 0),
    (0, -1.425, 0),
    (-1.5, -0.84, 0.075),
    (-0.84, -1.5, 0.075),
    (0, -1.5, 0.075),
    (0.798, -1.425, 0),
    (1.425, -0.798, 0),
    (0.84, -1.5, 0.075),
    (1.5, -0.84, 0.075),
]


if __name__ == "__main__":
    main()
