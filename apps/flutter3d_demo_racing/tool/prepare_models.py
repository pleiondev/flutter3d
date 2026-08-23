#!/usr/bin/env python3
"""Turns the downloaded car into the one this game ships.

    python3 tool/prepare_models.py ~/Downloads

Every step here is a change to somebody else's asset, so every step is also a
line in `assets/models/LICENSES.md` — the model is CC BY, which asks that
modifications be stated.

Run it again after re-downloading and the result is byte-identical; that is the
point of it being a script rather than a paragraph describing what was once done
by hand. The platformer has a script of the same shape and, so far, no shared
code: two of these is a coincidence, and the third is the one to extract.
"""

import json
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
MODELS = HERE.parent / 'assets' / 'models'

# What the maps are shrunk to. There are no compressed pixel formats on this
# stack — `flutter_gpu` exposes none — so every map costs raw RGBA in device
# memory whatever its PNG weighed. Twenty-four maps at 1024 is ninety-six
# megabytes of it; at 512 it is twenty-four.
TEXTURE_SIDE = 512

# Whether to turn the car half a turn about the vertical.
#
# **False, and that is the measured answer rather than the reasoned one.** The
# reasoning said True: glTF states that a model faces -Z, `SphereVehicle` drives
# towards +Z at a heading of nought, so half a turn reconciles them. The car
# then drove tail-first, which is the only test that settles it — this export
# already faces +Z, whatever the specification says exporters should do.
#
# Kept as a flag rather than deleted because the next model will have its own
# opinion, and the check is thirty seconds: drive forwards and look.
TURN_TO_FACE_FORWARD = False

# Extensions this stack does not implement. Neither is in `extensionsRequired`,
# so a loader is entitled to ignore them — but a loader that quietly ignores
# half a material is a car that looks wrong for a reason nobody can find, and a
# file that no longer claims them is a file that cannot be read two ways.
DROPPED_EXTENSIONS = ('KHR_materials_specular', 'KHR_materials_clearcoat')


def main() -> int:
    source = Path(sys.argv[1] if len(sys.argv) > 1 else '~/Downloads').expanduser()

    car = _read(source / '2002_mclaren_mp4-17.glb')
    _describe(car, 'as downloaded')
    _drop_extensions(car)
    _resize_images(car, TEXTURE_SIDE)
    # No scaling: the model measures 4.32 m nose to tail, which is what an
    # MP4-17 measures. A car resized to look right is a car whose mirrors are
    # the wrong size for the track it is on.
    if TURN_TO_FACE_FORWARD:
        _turn_root_about_y(car)

    MODELS.mkdir(parents=True, exist_ok=True)
    _write(car, MODELS / 'car.glb')
    return 0


def _describe(model, when: str) -> None:
    doc, _, name = model
    triangles = 0
    for mesh in doc.get('meshes', []):
        for prim in mesh['primitives']:
            if 'indices' in prim:
                triangles += doc['accessors'][prim['indices']]['count'] // 3
    print(f'{name} {when}: {len(doc.get("meshes", []))} meshes, '
          f'{triangles} triangles, {len(doc.get("images", []))} images')


def _read(path: Path):
    blob = path.read_bytes()
    json_len, kind = struct.unpack_from('<II', blob, 12)
    if kind != 0x4E4F534A:
        raise SystemExit(f'{path.name}: first chunk is not JSON')
    doc = json.loads(blob[20:20 + json_len].decode('utf-8'))
    bin_len, _ = struct.unpack_from('<II', blob, 20 + json_len)
    return doc, bytearray(blob[28 + json_len:28 + json_len + bin_len]), path.name


def _write(model, out: Path) -> None:
    doc, binary, name = model
    doc['buffers'][0]['byteLength'] = len(binary)
    text = json.dumps(doc, separators=(',', ':')).encode('utf-8')
    text += b' ' * ((4 - len(text) % 4) % 4)
    blob = bytearray(struct.pack('<III', 0x46546C67, 2,
                                 12 + 8 + len(text) + 8 + len(binary)))
    blob += struct.pack('<II', len(text), 0x4E4F534A) + text
    blob += struct.pack('<II', len(binary), 0x004E4942) + binary
    out.write_bytes(blob)
    print(f'{name} -> {out.name}  {len(blob) // 1024} KB')


def _drop_extensions(model) -> None:
    doc, _, _ = model
    used = [e for e in doc.get('extensionsUsed', [])
            if e not in DROPPED_EXTENSIONS]
    if used:
        doc['extensionsUsed'] = used
    else:
        doc.pop('extensionsUsed', None)

    for material in doc.get('materials', []):
        extensions = material.get('extensions')
        if not extensions:
            continue
        for name in DROPPED_EXTENSIONS:
            extensions.pop(name, None)
        if not extensions:
            material.pop('extensions', None)


def _png_size(data: bytes):
    """Width and height of a PNG, or None if it is not one."""
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        return None
    return struct.unpack('>II', data[16:24])


def _resize_images(model, side: int) -> None:
    """Shrinks the embedded images that are bigger than `side`.

    Only the ones that are bigger. `sips -Z` sets the long edge to the number
    given, which *enlarges* anything smaller — and this car carries a dozen maps
    of 256 pixels and under, which came back as 512s holding no more detail than
    before and four times the memory. The first run of this script made the file
    smaller by a fifth and its texture memory larger.
    """
    doc, binary, _ = model
    wanted = {i['bufferView'] for i in doc.get('images', []) if 'bufferView' in i}
    # `sips` is asked for PNG, so the declared type has to follow the bytes.
    for image in doc.get('images', []):
        if 'bufferView' in image:
            image['mimeType'] = 'image/png'

    pieces = []
    with tempfile.TemporaryDirectory() as work:
        for index, view in enumerate(doc['bufferViews']):
            start = view.get('byteOffset', 0)
            data = bytes(binary[start:start + view['byteLength']])
            size = _png_size(data) if index in wanted else None
            if size is not None and max(size) > side:
                scratch = Path(work) / f'{index}.png'
                scratch.write_bytes(data)
                subprocess.run(
                    ['sips', '-Z', str(side), '-s', 'format', 'png',
                     str(scratch), '--out', str(scratch)],
                    check=True, stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL)
                data = scratch.read_bytes()
            pieces.append(data)

    rebuilt = bytearray()
    for view, data in zip(doc['bufferViews'], pieces):
        while len(rebuilt) % 4:
            rebuilt.append(0)
        view['byteOffset'] = len(rebuilt)
        view['byteLength'] = len(data)
        rebuilt += data
    binary[:] = rebuilt


def _turn_root_about_y(model) -> None:
    """Folds half a turn about the vertical into the scene's roots.

    A half turn is a sign flip on the two horizontal axes, which is why this can
    be done to a matrix in place without composing anything.
    """
    doc, _, _ = model
    for index in doc['scenes'][doc.get('scene', 0)]['nodes']:
        node = doc['nodes'][index]
        if 'matrix' in node:
            m = list(node['matrix'])
            for column in range(4):
                m[column * 4 + 0] = -m[column * 4 + 0]
                m[column * 4 + 2] = -m[column * 4 + 2]
            node['matrix'] = m
        else:
            t = node.get('translation', [0.0, 0.0, 0.0])
            node['translation'] = [-t[0], t[1], -t[2]]
            scale = node.get('scale', [1.0, 1.0, 1.0])
            node['scale'] = [-scale[0], scale[1], -scale[2]]


if __name__ == '__main__':
    raise SystemExit(main())
