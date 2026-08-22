#!/usr/bin/env python3
"""Draws the models a template gives a new game, as real glTF files.

    python3 tool/make_models.py

**This repository could not make a model.** `prepare_models.py` transforms ones
somebody downloaded, and everything else is built out of primitives at runtime
by the game that draws it — which is right for a game and useless to anything
else, because a program that is not that game has nothing to point at. A level
editor opening a new project is exactly that program.

So: a glTF 2.0 writer, in the standard library, out of primitives. No textures,
no skins, **no animations** — a shape, a colour, and where it sits.

## What it is, and what it is not

Not a modelling tool. Every model here is a handful of boxes, cylinders, cones
and spheres, in the sizes the genre packages already say those things are
(`PickupKind.defaultSize`, `Crate.defaultSize`, and the rest). What it buys is
that a monster in an editor is monster-shaped and monster-sized rather than a
half-metre cube with a word beside it — and that a new game gets that on the day
it is created, before anybody has drawn anything.

## Two things that look optional and are not

**`metallicFactor` is written.** glTF's default is 1.0 and this engine reads it
faithfully (`gltf_loader.dart`), so a material that leaves it out is fully
metallic — which without an environment map is very nearly black. Every model
generated without that line looks like a hole in the level.

**Normals are written.** The loader will generate flat ones for a mesh that has
none, by de-indexing it; a box needs its twenty-four vertices anyway, because
four per face is what a hard edge is.

## Why the coordinates are quantised

`math.sin` and `math.cos` are libm, and libm is not bit-identical across
platforms. One unit in the last place is one different byte, and this file is
checked by regenerating it and comparing — which would then fail on any machine
that is not the one it was written on. Every coordinate is rounded onto a
1/4096 m grid, which is a quarter of a millimetre, invisible at these sizes, and
turns "deterministic" from a hope into a property.
"""

import json
import math
import os
import struct
import zlib
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# The grid every coordinate lands on. See the note above.
GRID = 4096.0


def q(value):
    """[value] on the grid, as an exactly representable float."""
    return round(value * GRID) / GRID


class Mesh:
    """Triangles being accumulated, with a colour per run."""

    def __init__(self):
        self.positions = []
        self.normals = []
        self.uvs = []
        self.indices = []
        # One primitive per material: (first index, count, material)
        self.runs = []
        self.materials = []
        # PNGs to embed, in the order the materials name them.
        self.images = []

    def part(self, colour, glow=None, roughness=0.8, image=None):
        """Starts a run of triangles in a colour, and returns its index.

        [image] is PNG bytes to sample the base colour from — see `page`, the
        one model that needs a picture rather than a colour.
        """
        material = {
            'pbrMetallicRoughness': {
                'baseColorFactor': [q(c) for c in colour] + [1.0],
                # **Written, not defaulted.** See the note at the top.
                'metallicFactor': 0.0,
                'roughnessFactor': q(roughness),
            },
        }
        if image is not None:
            self.images.append(image)
            material['pbrMetallicRoughness']['baseColorTexture'] = {
                'index': len(self.images) - 1,
            }
        if glow is not None:
            material['emissiveFactor'] = [q(c) for c in glow]
        self.materials.append(material)
        self.runs.append([len(self.indices), 0, len(self.materials) - 1])
        return len(self.materials) - 1

    def triangle(self, a, b, c, na=None, nb=None, nc=None,
                 ta=None, tb=None, tc=None):
        normal = na or _normal(a, b, c)
        base = len(self.positions)
        points = ((a, na or normal, ta), (b, nb or normal, tb),
                  (c, nc or normal, tc))
        for point, n, uv in points:
            self.positions.append([q(v) for v in point])
            self.normals.append([q(v) for v in n])
            # **Every vertex gets one or none of them do.** A glTF attribute is
            # per mesh, so a file with one textured face still needs a
            # coordinate on every other vertex; nought is as good as any, since
            # nothing samples them.
            self.uvs.append([q(uv[0]), q(uv[1])] if uv else [0.0, 0.0])
        self.indices.extend([base, base + 1, base + 2])
        self.runs[-1][1] += 3

    def quad(self, a, b, c, d, na=None, nb=None, nc=None, nd=None,
             ta=None, tb=None, tc=None, td=None):
        self.triangle(a, b, c, na, nb, nc, ta, tb, tc)
        self.triangle(a, c, d, na, nc, nd, ta, tc, td)


def _normal(a, b, c):
    u = [b[i] - a[i] for i in range(3)]
    v = [c[i] - a[i] for i in range(3)]
    n = [
        u[1] * v[2] - u[2] * v[1],
        u[2] * v[0] - u[0] * v[2],
        u[0] * v[1] - u[1] * v[0],
    ]
    length = math.sqrt(sum(x * x for x in n))
    if length < 1e-9:
        return [0.0, 1.0, 0.0]
    return [x / length for x in n]


def _ring(segments):
    """Points around a unit circle, quantised.

    The one place trigonometry happens, so the one place that has to be pinned
    to the grid — everything downstream is addition.
    """
    return [
        (q(math.cos(2 * math.pi * i / segments)),
         q(math.sin(2 * math.pi * i / segments)))
        for i in range(segments)
    ]


# --- the primitives --------------------------------------------------------

def box(mesh, size, at=(0.0, 0.0, 0.0), colour=(0.7, 0.7, 0.7), glow=None,
        roughness=0.8):
    """A box, twenty-four vertices, because four per face is what an edge is."""
    mesh.part(colour, glow, roughness)
    hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
    x, y, z = at
    corners = [
        (x - hx, y - hy, z - hz), (x + hx, y - hy, z - hz),
        (x + hx, y + hy, z - hz), (x - hx, y + hy, z - hz),
        (x - hx, y - hy, z + hz), (x + hx, y - hy, z + hz),
        (x + hx, y + hy, z + hz), (x - hx, y + hy, z + hz),
    ]
    faces = [
        (4, 5, 6, 7), (1, 0, 3, 2), (3, 2, 6, 7),
        (0, 1, 5, 4), (5, 1, 2, 6), (0, 4, 7, 3),
    ]
    for face in faces:
        mesh.quad(*[corners[i] for i in face])


def tube(mesh, radius_top, radius_bottom, height, at=(0.0, 0.0, 0.0),
         colour=(0.7, 0.7, 0.7), glow=None, roughness=0.8, segments=16,
         capped=True):
    """A cylinder or a cone, depending on whether the top has a radius."""
    mesh.part(colour, glow, roughness)
    x, y, z = at
    top, bottom = y + height / 2, y - height / 2
    ring = _ring(segments)

    for i in range(segments):
        cx, cz = ring[i]
        nx, nz = ring[(i + 1) % segments]
        a = (x + nx * radius_bottom, bottom, z + nz * radius_bottom)
        b = (x + cx * radius_bottom, bottom, z + cz * radius_bottom)
        c = (x + cx * radius_top, top, z + cz * radius_top)
        d = (x + nx * radius_top, top, z + nz * radius_top)
        # Smooth around the side: the normal is the direction out of the axis,
        # which is what stops a sixteen-sided tube reading as sixteen planks.
        na = _out(nx, nz)
        nb = _out(cx, cz)
        if radius_top <= 1e-6:
            mesh.triangle(a, b, c, na, nb, nb)
        else:
            mesh.quad(a, b, c, d, na, nb, nb, na)

    if not capped:
        return
    for radius, level, up in ((radius_bottom, bottom, False), (radius_top, top, True)):
        if radius <= 1e-6:
            continue
        normal = [0.0, 1.0 if up else -1.0, 0.0]
        for i in range(1, segments - 1):
            points = [
                (x + ring[0][0] * radius, level, z + ring[0][1] * radius),
                (x + ring[i][0] * radius, level, z + ring[i][1] * radius),
                (x + ring[i + 1][0] * radius, level, z + ring[i + 1][1] * radius),
            ]
            if not up:
                points.reverse()
            mesh.triangle(*points, normal, normal, normal)


def _out(x, z):
    length = math.sqrt(x * x + z * z)
    if length < 1e-9:
        return [1.0, 0.0, 0.0]
    return [x / length, 0.0, z / length]


def ball(mesh, radius, at=(0.0, 0.0, 0.0), colour=(0.7, 0.7, 0.7), glow=None,
         roughness=0.6, rings=8, segments=12, squash=1.0):
    """A sphere, or a squashed one — which is most of a head and all of a coin."""
    mesh.part(colour, glow, roughness)
    x, y, z = at

    def point(ring, segment):
        theta = math.pi * ring / rings
        phi = 2 * math.pi * segment / segments
        nx = q(math.sin(theta) * math.cos(phi))
        ny = q(math.cos(theta))
        nz = q(math.sin(theta) * math.sin(phi))
        return (
            (x + nx * radius, y + ny * radius * squash, z + nz * radius),
            [nx, ny, nz],
        )

    for ring in range(rings):
        for segment in range(segments):
            a, na = point(ring, segment)
            b, nb = point(ring + 1, segment)
            c, nc = point(ring + 1, segment + 1)
            d, nd = point(ring, segment + 1)
            if ring == 0:
                mesh.triangle(a, b, c, na, nb, nc)
            elif ring == rings - 1:
                mesh.triangle(a, b, d, na, nb, nd)
            else:
                mesh.quad(a, b, c, d, na, nb, nc, nd)


# --- the file --------------------------------------------------------------

def write_glb(mesh, name, path):
    """Writes [mesh] as a glTF 2.0 binary file."""
    binary = bytearray()
    views = []
    accessors = []

    def view(data, target):
        while len(binary) % 4:
            binary.append(0)
        offset = len(binary)
        binary.extend(data)
        views.append({
            'buffer': 0,
            'byteOffset': offset,
            'byteLength': len(data),
            **({'target': target} if target is not None else {}),
        })
        return len(views) - 1

    positions = b''.join(struct.pack('<fff', *p) for p in mesh.positions)
    normals = b''.join(struct.pack('<fff', *n) for n in mesh.normals)
    uvs = b''.join(struct.pack('<ff', *t) for t in mesh.uvs)
    indices = b''.join(struct.pack('<H', i) for i in mesh.indices)

    low = [min(p[i] for p in mesh.positions) for i in range(3)]
    high = [max(p[i] for p in mesh.positions) for i in range(3)]

    accessors.append({
        'bufferView': view(positions, 34962),
        'componentType': 5126,
        'count': len(mesh.positions),
        'type': 'VEC3',
        # Required by the specification. This engine works out its own bounds
        # from the vertices and never reads these, but a validator does, and so
        # does every other program that will ever open the file.
        'min': low,
        'max': high,
    })
    accessors.append({
        'bufferView': view(normals, 34962),
        'componentType': 5126,
        'count': len(mesh.normals),
        'type': 'VEC3',
    })
    textured = bool(mesh.images)
    if textured:
        accessors.append({
            'bufferView': view(uvs, 34962),
            'componentType': 5126,
            'count': len(mesh.uvs),
            'type': 'VEC2',
        })
    index_view = view(indices, 34963)

    primitives = []
    for first, count, material in mesh.runs:
        if count == 0:
            continue
        accessors.append({
            'bufferView': index_view,
            'byteOffset': first * 2,
            'componentType': 5123,
            'count': count,
            'type': 'SCALAR',
        })
        primitives.append({
            'attributes': {'POSITION': 0, 'NORMAL': 1, 'TEXCOORD_0': 2}
                if textured
                else {'POSITION': 0, 'NORMAL': 1},
            'indices': len(accessors) - 1,
            'material': material,
            'mode': 4,
        })

    while len(binary) % 4:
        binary.append(0)

    # Images live in the binary chunk like everything else: a bufferView with
    # no target, because a target is for vertex and index data.
    images = []
    samplers = []
    textures = []
    for png in mesh.images:
        images.append({'bufferView': view(png, None), 'mimeType': 'image/png'})
        textures.append({'sampler': 0, 'source': len(images) - 1})
    if textures:
        samplers.append({
            # Linear, with mips: a page read at a glancing angle across a room
            # is exactly where a nearest-neighbour sampler turns writing into
            # noise.
            'magFilter': 9729,
            'minFilter': 9987,
            'wrapS': 33071,
            'wrapT': 33071,
        })

    document = {
        'asset': {'version': '2.0', 'generator': 'tool/make_models.py'},
        'scene': 0,
        'scenes': [{'nodes': [0]}],
        'nodes': [{'mesh': 0, 'name': name}],
        'meshes': [{'name': name, 'primitives': primitives}],
        'materials': mesh.materials,
        **({'images': images, 'samplers': samplers, 'textures': textures}
           if textures else {}),
        'accessors': accessors,
        'bufferViews': views,
        'buffers': [{'byteLength': len(binary)}],
    }

    text = json.dumps(document, separators=(',', ':')).encode('utf-8')
    padding = (-len(text)) % 4
    total = 12 + 8 + len(text) + padding + 8 + len(binary)

    out = bytearray()
    out.extend(struct.pack('<III', 0x46546C67, 2, total))
    out.extend(struct.pack('<II', len(text) + padding, 0x4E4F534A))
    out.extend(text)
    # JSON chunks pad with spaces, binary chunks with zeros.
    out.extend(b' ' * padding)
    out.extend(struct.pack('<II', len(binary), 0x004E4942))
    out.extend(binary)

    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'wb') as file:
        file.write(bytes(out))
    return len(out)


# --- what a template gives a new game --------------------------------------
#
# **Only the things whose size the game fixes.** A door is six metres wide in
# one level and four in another, because the level says so and the game builds
# it at that size — and a model has a size of its own that nothing rescales, so
# a door model would be a lie in every level but one. Those stay boxes drawn at
# the size the document gives them, which is what the game does too.
#
# Sizes are the genre packages' own: `PickupKind.defaultSize`, the `MonsterDef`
# figures in `sample.dart`, `CollectibleKind.defaultSize`, and the rest. A thing
# placed in an editor is then the size it will be when the game builds it.

IRON = (0.17, 0.16, 0.15)
FLESH = (0.42, 0.19, 0.17)
BONE = (0.78, 0.74, 0.66)
BRASS = (0.72, 0.55, 0.20)
WOOD = (0.45, 0.31, 0.17)
FLAME = (1.0, 0.55, 0.14)


def monster(mesh):
    """Something the height of a person and half again as wide as one.

    `MonsterDef` in the shooter's `sample.dart` says a runner is 0.35 across and
    1.7 tall. **Centred on its own origin**, because a monster's `at` is the
    middle of its capsule — the crypt puts one at y = 1.0 on a floor at y = 0.
    """
    tube(mesh, 0.30, 0.34, 0.95, at=(0.0, -0.12, 0.0), colour=FLESH)
    ball(mesh, 0.27, at=(0.0, 0.55, 0.0), colour=FLESH)
    # Eyes, lit, because a monster you can tell the front of is a monster you
    # can place facing the corridor.
    ball(mesh, 0.055, at=(0.10, 0.59, -0.22), colour=(0.9, 0.9, 0.2),
         glow=(0.9, 0.75, 0.1))
    ball(mesh, 0.055, at=(-0.10, 0.59, -0.22), colour=(0.9, 0.9, 0.2),
         glow=(0.9, 0.75, 0.1))
    box(mesh, (0.62, 0.14, 0.24), at=(0.0, 0.29, 0.0), colour=IRON)
    tube(mesh, 0.09, 0.09, 0.55, at=(0.0, -0.60, 0.10), colour=FLESH)


def pickup(mesh):
    """A box with something lit inside it. `PickupKind.defaultSize` is 0.45."""
    box(mesh, (0.40, 0.40, 0.40), colour=(0.85, 0.86, 0.88), roughness=0.4)
    box(mesh, (0.30, 0.09, 0.42), colour=(0.85, 0.2, 0.18),
        glow=(0.5, 0.06, 0.05))
    box(mesh, (0.09, 0.30, 0.42), colour=(0.85, 0.2, 0.18),
        glow=(0.5, 0.06, 0.05))


def key(mesh):
    """A bow, a shaft and two teeth. Half a metre, as both genres' keys are."""
    tube(mesh, 0.13, 0.13, 0.05, at=(0.0, 0.14, 0.0), colour=BRASS,
         roughness=0.25)
    tube(mesh, 0.07, 0.07, 0.05, at=(0.0, 0.14, 0.0), colour=(0.05, 0.05, 0.05),
         roughness=0.25)
    box(mesh, (0.05, 0.30, 0.05), at=(0.0, -0.06, 0.0), colour=BRASS,
        roughness=0.25)
    box(mesh, (0.11, 0.05, 0.05), at=(0.05, -0.14, 0.0), colour=BRASS,
        roughness=0.25)
    box(mesh, (0.11, 0.05, 0.05), at=(0.05, -0.05, 0.0), colour=BRASS,
        roughness=0.25)


def torch(mesh):
    """The crypt's own silhouette: a plate, an angled shaft, a cup, a flame.

    The numbers are `DungeonFixtures.buildLightFixture`'s, so a torch placed in
    an editor stands where the game will build one.
    """
    box(mesh, (0.16, 0.30, 0.06), at=(0.0, -0.18, 0.06), colour=IRON)
    tube(mesh, 0.035, 0.035, 0.42, at=(0.0, -0.06, -0.05), colour=IRON)
    tube(mesh, 0.075, 0.05, 0.10, at=(0.0, 0.10, -0.14), colour=IRON)
    ball(mesh, 0.085, at=(0.0, 0.21, -0.14), colour=FLAME, glow=FLAME,
         squash=1.5)


def hanging_lamp(mesh):
    """A globe with its stem going **up**, which is what the crypt's lamp is.

    `DungeonFixtures` puts the globe at the fixture's own origin and the stem
    above it: the thing hangs. The platformer's lamp is the same two parts the
    other way up and is a different model, because a model has no idea which
    game it is in and the two are not the same object.
    """
    ball(mesh, 0.17, colour=(1.0, 0.93, 0.72), glow=(0.9, 0.78, 0.5))
    tube(mesh, 0.03, 0.03, 0.60, at=(0.0, 0.47, 0.0), colour=IRON)
    box(mesh, (0.22, 0.05, 0.22), at=(0.0, 0.79, 0.0), colour=IRON)


def standing_lamp(mesh):
    """A globe on a post going **down** to the floor: the platformer's.

    `PlatformerLooks` draws the globe at the entity's own position and a post of
    the whole height below it — so the lamp stands, and its `at` is the light
    rather than the foot. The first version of this file gave both games the
    hanging one, and a lamp in a platformer came out upside down: a stem in the
    air with a bulb swinging under it.
    """
    ball(mesh, 0.20, colour=(1.0, 0.93, 0.72), glow=(0.9, 0.78, 0.5))
    box(mesh, (0.11, 1.60, 0.11), at=(0.0, -0.80, 0.0), colour=(0.22, 0.20, 0.18))
    box(mesh, (0.34, 0.06, 0.34), at=(0.0, -1.57, 0.0), colour=(0.22, 0.20, 0.18))


def _png(width, height, pixels):
    """A PNG, out of the standard library.

    Written here rather than shipped as a file for the same reason the geometry
    is: a picture generated from a few lines of code is a picture that can be
    regenerated and diffed, and one that arrives as bytes is a picture nobody
    can change without opening a paint program.
    """
    raw = bytearray()
    for y in range(height):
        raw.append(0)  # filter: none, so the bytes are the pixels
        for x in range(width):
            raw.extend(pixels[y * width + x])
    body = zlib.compress(bytes(raw), 9)

    def chunk(kind, data):
        return (struct.pack('>I', len(data)) + kind + data
                + struct.pack('>I', zlib.crc32(kind + data) & 0xFFFFFFFF))

    return (b'\x89PNG\r\n\x1a\n'
            + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
            + chunk(b'IDAT', body)
            + chunk(b'IEND', b''))


def _writing():
    """A page of handwriting, as a texture.

    **A blank page is not a note.** The model used to be a tan rectangle with a
    batten across the top, which in an editor reads as a card, a plaque or a
    piece of wood — anything but something to read. What makes it a note is
    that there is writing on it, and at the size one is ever seen the writing
    only has to be lines.

    Ink is laid down as short runs with gaps, ragged at the right-hand end the
    way a written line is, and the last line is short because a paragraph ends
    where it ends. Nothing here is random: the runs are a fixed table, so the
    file is the same bytes on every machine.
    """
    width, height = 48, 64
    paper = (0xE8, 0xDF, 0xC4)
    stain = (0xD8, 0xCB, 0xA6)
    ink = (0x3A, 0x2E, 0x22)
    pixels = [paper] * (width * height)

    def line(y, x0, x1, colour=ink):
        for x in range(max(0, x0), min(width, x1)):
            pixels[y * width + x] = colour

    # An older, browner edge, so the page does not read as printer paper.
    for y in range(height):
        for x in range(width):
            edge = min(x, y, width - 1 - x, height - 1 - y)
            if edge < 3:
                pixels[y * width + x] = stain

    # Eleven lines of writing, each a row of ink two pixels tall with a gap
    # where a word ends.
    rows = [
        (8, [(7, 20), (22, 33), (35, 41)]),
        (13, [(7, 15), (17, 30), (32, 40)]),
        (18, [(7, 26), (28, 38)]),
        (23, [(7, 13), (15, 31), (33, 41)]),
        (28, [(7, 22), (24, 36)]),
        (33, [(7, 18), (20, 29), (31, 40)]),
        (38, [(7, 25), (27, 34)]),
        (43, [(7, 16), (18, 33), (35, 39)]),
        (48, [(7, 28), (30, 41)]),
        (53, [(7, 14), (16, 27)]),
    ]
    for y, runs in rows:
        for x0, x1 in runs:
            line(y, x0, x1)
            line(y + 1, x0, x1)

    return _png(width, height, pixels)


def note(mesh):
    """A page on the wall, with writing on it.

    Nothing in either game draws one — a note is read, not drawn — so this is
    the only picture of one that exists, and the editor is the only thing that
    shows it.
    """
    box(mesh, (0.34, 0.44, 0.02), colour=(0.86, 0.82, 0.70), roughness=0.9)
    box(mesh, (0.36, 0.04, 0.03), at=(0.0, 0.22, 0.0), colour=WOOD)

    # The writing, on a quad a hair in front of the page so the two never
    # argue about which is nearer.
    mesh.part((1.0, 1.0, 1.0), roughness=0.9, image=_writing())
    z = 0.011
    mesh.quad(
        (-0.15, -0.19, z), (0.15, -0.19, z), (0.15, 0.17, z), (-0.15, 0.17, z),
        na=(0.0, 0.0, 1.0), nb=(0.0, 0.0, 1.0),
        nc=(0.0, 0.0, 1.0), nd=(0.0, 0.0, 1.0),
        ta=(0.0, 1.0), tb=(1.0, 1.0), tc=(1.0, 0.0), td=(0.0, 0.0),
    )


def spawn(mesh):
    """Where the player starts: a figure, **standing on** its own origin.

    A spawn's `at` is the feet and not the middle: the crypt's is at y = 0 on a
    floor whose top is y = 0. A figure centred on the origin would be a player
    buried to the waist.
    """
    tube(mesh, 0.34, 0.34, 0.04, at=(0.0, 0.02, 0.0), colour=(0.3, 0.8, 0.35),
         glow=(0.12, 0.4, 0.15))
    tube(mesh, 0.20, 0.24, 0.90, at=(0.0, 0.55, 0.0), colour=(0.25, 0.55, 0.85))
    ball(mesh, 0.20, at=(0.0, 1.20, 0.0), colour=(0.85, 0.72, 0.58))


def coin(mesh):
    """A disc on edge, spinning is the game's business. 0.5, as the platformer's
    `CollectibleKind.defaultSize` says."""
    tube(mesh, 0.18, 0.18, 0.05, at=(0.0, 0.0, 0.0), colour=(1.0, 0.82, 0.25),
         glow=(0.45, 0.33, 0.05), roughness=0.25)
    tube(mesh, 0.12, 0.12, 0.07, at=(0.0, 0.0, 0.0), colour=(1.0, 0.90, 0.45),
         glow=(0.5, 0.4, 0.08), roughness=0.25)


def enemy(mesh):
    """The platformer's, which is 0.7 of a cube and walks a route."""
    box(mesh, (0.52, 0.42, 0.52), at=(0.0, 0.05, 0.0), colour=(0.55, 0.22, 0.5))
    ball(mesh, 0.09, at=(0.14, 0.16, -0.24), colour=(1.0, 1.0, 1.0),
         glow=(0.5, 0.5, 0.5))
    ball(mesh, 0.09, at=(-0.14, 0.16, -0.24), colour=(1.0, 1.0, 1.0),
         glow=(0.5, 0.5, 0.5))
    box(mesh, (0.12, 0.18, 0.12), at=(0.20, -0.26, 0.0), colour=(0.3, 0.12, 0.3))
    box(mesh, (0.12, 0.18, 0.12), at=(-0.20, -0.26, 0.0), colour=(0.3, 0.12, 0.3))


def checkpoint(mesh):
    """A post with a flag. `CheckpointKind.markerSize` is 0.35 by 2.2."""
    tube(mesh, 0.06, 0.06, 2.10, colour=BONE)
    box(mesh, (0.44, 0.30, 0.03), at=(0.24, 0.85, 0.0), colour=(0.2, 0.75, 0.35),
        glow=(0.06, 0.3, 0.12))


def exit_arch(mesh):
    """A way down: a frame round a dark opening.

    `ExitKind` has no size of its own, and the crypt's editor entry says
    1.8 by 2.6 by 0.4 — a doorway. Drawn as a frame rather than as a slab, so
    that what it marks reads as something to walk through.
    """
    box(mesh, (0.16, 2.60, 0.30), at=(-0.82, 0.0, 0.0), colour=IRON)
    box(mesh, (0.16, 2.60, 0.30), at=(0.82, 0.0, 0.0), colour=IRON)
    box(mesh, (1.80, 0.16, 0.30), at=(0.0, 1.22, 0.0), colour=IRON)
    # The dark inside it, lit a little so the frame is not a hole in an unlit
    # wall — which is a hole nobody can find.
    box(mesh, (1.48, 2.44, 0.06), at=(0.0, -0.08, -0.10),
        colour=(0.05, 0.05, 0.06), glow=(0.02, 0.03, 0.05))



# The crypt's own marks.
#
# **The editor was drawing coloured boxes for half of what a level contains**,
# and the models to draw instead already existed — they are the same functions
# the shooter template ships. What the crypt's `assets/models/` had was the
# monsters (downloaded, CC0) and the key (generated by the platformer's own
# script); everything else was a box with a tint derived from the type's name.
#
# Not the torch and the lamp: those two are drawn from `editor.json`'s `parts`,
# built out of the engine's primitives from the game's own fixture numbers, so a
# torch placed in the editor stands exactly where the game will build one.
CRYPT = {
    'note': note,
    'pickup': pickup,
    'player_spawn': spawn,
    'exit': exit_arch,
}

MODELS = {
    'shooter': {
        'monster': monster,
        'pickup': pickup,
        'key': key,
        'torch': torch,
        'lamp': hanging_lamp,
        'note': note,
        'player_spawn': spawn,
    },
    'platformer': {
        'collectible': coin,
        'key': key,
        'enemy': enemy,
        'lamp': standing_lamp,
        'checkpoint': checkpoint,
        'player_spawn': spawn,
    },
}


def main():
    for name, build in sorted(CRYPT.items()):
        mesh = Mesh()
        build(mesh)
        path = os.path.join(
            HERE, 'apps', 'dungeon', 'assets', 'models', f'{name}.glb',
        )
        size = write_glb(mesh, name, path)
        print(f'dungeon/{name}: {len(mesh.indices) // 3} triangles, {size} bytes')

    for genre, models in MODELS.items():
        for name, build in sorted(models.items()):
            mesh = Mesh()
            build(mesh)
            path = os.path.join(
                HERE, 'apps', 'editor', 'assets', 'templates', genre,
                f'model.{name}.glb',
            )
            size = write_glb(mesh, name, path)
            print(f'{genre}/{name}: {len(mesh.indices) // 3} triangles, {size} bytes')


if __name__ == '__main__':
    main()
