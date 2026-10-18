#!/usr/bin/env python3
"""Turns the downloaded car into the one this game ships.

    python3 tool/prepare_models.py ~/Downloads/kenney_car-kit

The car is `race.glb` from Kenney's Car Kit, which is CC0: nothing here is
owed to anybody, but every change is still written down in
`assets_src/models/LICENSES.md`, so that what is in the repository can be told
apart from what was downloaded. A racing car with somebody's sponsors on it is
somebody's trademarks on a public repository; this one carries none.

Run it again on the same download and the result is byte-identical; that is the
point of it being a script rather than a paragraph describing what was once done
by hand.

Needs Pillow, for reading the colour atlas.
"""

import colorsys
import json
import struct
import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
MODELS = HERE.parent / 'assets_src' / 'models'

# The distance between the axles `SphereVehicle` steers by, m: the default of
# `VehicleTuning.wheelBase` in flutter3d_game_racing. The kit's car is drawn at
# no scale in particular, so it is scaled until its own axles are this far
# apart — the one length of the car the simulation knows. A car scaled to look
# right would be a car whose wheels turn somewhere its physics does not.
WHEEL_BASE = 2.7

# Which of the atlas's colours are the car's paint: the red the body is drawn
# in, its swatch from (227, 94, 73) to (235, 99, 70) — a hue within a tenth
# of a turn of red, saturated and bright. The blue-grey undertray and side
# pods, the dark glass and the tyres are other swatches and stay as they
# are. (Measured off the atlas: the first version of this took the blue-grey
# for the paint and painted the side pods, leaving every car red.)
PAINT_HUE = 0.1
PAINT_SATURATION = 0.5
PAINT_VALUE = 0.7


def main() -> int:
    source = Path(sys.argv[1] if len(sys.argv) > 1 else '~/Downloads/kenney_car-kit')
    models = source.expanduser() / 'Models' / 'GLB format'
    doc, binary = _read(models / 'race.glb')
    atlas_path = models / 'Textures' / 'colormap.png'
    atlas = Image.open(atlas_path).convert('RGB')

    _embed_image(doc, binary, atlas_path.read_bytes())
    _drop_texture_transform(doc)
    _split_paint(doc, binary, atlas)
    _scale_to_wheel_base(doc)

    MODELS.mkdir(parents=True, exist_ok=True)
    _write(doc, binary, MODELS / 'car.glb')
    return 0


def _read(path: Path):
    blob = path.read_bytes()
    json_len, kind = struct.unpack_from('<II', blob, 12)
    if kind != 0x4E4F534A:
        raise SystemExit(f'{path.name}: first chunk is not JSON')
    doc = json.loads(blob[20:20 + json_len].decode('utf-8'))
    bin_len, _ = struct.unpack_from('<II', blob, 20 + json_len)
    return doc, bytearray(blob[28 + json_len:28 + json_len + bin_len])


def _write(doc, binary: bytearray, out: Path) -> None:
    while len(binary) % 4:
        binary.append(0)
    doc['buffers'] = [{'byteLength': len(binary)}]
    text = json.dumps(doc, separators=(',', ':')).encode('utf-8')
    text += b' ' * ((4 - len(text) % 4) % 4)
    blob = bytearray(struct.pack('<III', 0x46546C67, 2,
                                 12 + 8 + len(text) + 8 + len(binary)))
    blob += struct.pack('<II', len(text), 0x4E4F534A) + text
    blob += struct.pack('<II', len(binary), 0x004E4942) + binary
    out.write_bytes(blob)
    print(f'race.glb -> {out.name}  {len(blob) // 1024} KB')


def _append(doc, binary: bytearray, data: bytes, target=None) -> int:
    """Appends [data] to the binary chunk as a new buffer view; its index."""
    while len(binary) % 4:
        binary.append(0)
    view = {'buffer': 0, 'byteOffset': len(binary), 'byteLength': len(data)}
    if target is not None:
        view['target'] = target
    binary += data
    doc['bufferViews'].append(view)
    return len(doc['bufferViews']) - 1


def _embed_image(doc, binary: bytearray, png: bytes) -> None:
    """The atlas into the file: the kit points at a PNG beside it, and an
    asset that needs a second file to draw is two assets."""
    view = _append(doc, binary, png)
    doc['images'] = [{'bufferView': view, 'mimeType': 'image/png', 'name': 'colormap'}]


def _drop_texture_transform(doc) -> None:
    """The kit writes `KHR_texture_transform` naming only the coordinate set
    the texture already uses — an identity this stack does not read, and a
    file that claims an extension it need not is a file two loaders can read
    two ways."""
    for material in doc.get('materials', []):
        info = material.get('pbrMetallicRoughness', {}).get('baseColorTexture')
        if info is not None:
            info.pop('extensions', None)
    used = [e for e in doc.get('extensionsUsed', []) if e != 'KHR_texture_transform']
    if used:
        doc['extensionsUsed'] = used
    else:
        doc.pop('extensionsUsed', None)


_COMPONENTS = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}
_FORMATS = {5126: 'f', 5125: 'I', 5123: 'H', 5121: 'B'}


def _values(doc, binary, index):
    accessor = doc['accessors'][index]
    view = doc['bufferViews'][accessor['bufferView']]
    width = _COMPONENTS[accessor['type']]
    kind = _FORMATS[accessor['componentType']]
    size = struct.calcsize('<' + kind)
    stride = view.get('byteStride', width * size)
    start = view.get('byteOffset', 0) + accessor.get('byteOffset', 0)
    return [struct.unpack_from('<' + kind * width, binary, start + i * stride)
            for i in range(accessor['count'])]


def _accessor(doc, binary, rows, kind, target):
    """A new float or index accessor holding [rows]."""
    width = len(rows[0])
    fmt = '<' + ('f' if kind == 5126 else 'I') * width
    data = b''.join(struct.pack(fmt, *row) for row in rows)
    view = _append(doc, binary, data, target)
    accessor = {
        'bufferView': view,
        'componentType': kind,
        'count': len(rows),
        'type': {1: 'SCALAR', 2: 'VEC2', 3: 'VEC3', 4: 'VEC4'}[width],
    }
    if kind == 5126 and width == 3:
        accessor['min'] = [min(r[k] for r in rows) for k in range(3)]
        accessor['max'] = [max(r[k] for r in rows) for k in range(3)]
    doc['accessors'].append(accessor)
    return len(doc['accessors']) - 1


def _is_paint(atlas: Image.Image, u: float, v: float) -> bool:
    width, height = atlas.size
    r, g, b = atlas.getpixel((min(int(u * width), width - 1),
                              min(int(v * height), height - 1)))
    hue, saturation, value = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
    red = hue < PAINT_HUE or hue > 1.0 - PAINT_HUE
    return red and saturation > PAINT_SATURATION and value > PAINT_VALUE


def _white_texel(atlas: Image.Image):
    """The middle of the first eight-texel square of white in the atlas, as a
    texture coordinate: what the paint samples, so that the colour a game
    gives it is the colour drawn."""
    width, height = atlas.size
    for y in range(0, height - 8):
        for x in range(0, width - 8):
            if all(min(atlas.getpixel((x + i, y + j))) >= 250
                   for i in range(8) for j in range(8)):
                return ((x + 4) / width, (y + 4) / height)
    raise SystemExit('colormap.png: no white to paint with')


def _split_paint(doc, binary: bytearray, atlas: Image.Image) -> None:
    """The body's paint as a primitive and a material of its own, `paint`.

    The kit draws the whole car from one colour atlas through one material, so
    a game that tints a rival tints its tyres and its glass with it. Each
    triangle of the body whose middle samples the body's swatch goes to the
    paint, with its own copies of its corners sampling white; everything else
    keeps the atlas.
    """
    body = next(m for m in doc['meshes'] if m['name'] == 'body')
    primitive = body['primitives'][0]
    attributes = primitive['attributes']
    uvs = _values(doc, binary, attributes['TEXCOORD_0'])
    indices = [row[0] for row in _values(doc, binary, primitive['indices'])]
    paint, trim = [], []
    # Every triangle by the middle of its corners' coordinates in the atlas.
    for t in range(0, len(indices), 3):
        corners = indices[t:t + 3]
        u = sum(uvs[i][0] for i in corners) / 3
        v = sum(uvs[i][1] for i in corners) / 3
        (paint if _is_paint(atlas, u, v) else trim).append(corners)

    white = _white_texel(atlas)
    used = sorted({i for tri in paint for i in tri})
    remap = {old: new for new, old in enumerate(used)}
    painted = {'attributes': {}, 'material': len(doc['materials'])}
    for name, index in attributes.items():
        rows = _values(doc, binary, index)
        rows = [white if name == 'TEXCOORD_0' else rows[i] for i in used]
        painted['attributes'][name] = _accessor(doc, binary, rows, 5126, 34962)
    painted['indices'] = _accessor(
        doc, binary, [(remap[i],) for tri in paint for i in tri], 5125, 34963)
    primitive['indices'] = _accessor(
        doc, binary, [(i,) for tri in trim for i in tri], 5125, 34963)
    body['primitives'].append(painted)

    material = json.loads(json.dumps(doc['materials'][primitive['material']]))
    material['name'] = 'paint'
    doc['materials'].append(material)
    print(f'body: {len(paint)} triangles of paint, {len(trim)} of trim')


def _scale_to_wheel_base(doc) -> None:
    """One root over the kit's five, scaled so its axles are WHEEL_BASE apart."""
    nodes = doc['nodes']
    front = next(n for n in nodes if n['name'] == 'wheel-front-left')['translation'][2]
    back = next(n for n in nodes if n['name'] == 'wheel-back-left')['translation'][2]
    scale = WHEEL_BASE / abs(front - back)
    scene = doc['scenes'][doc.get('scene', 0)]
    nodes.append({'name': 'car', 'scale': [scale] * 3, 'children': scene['nodes']})
    scene['nodes'] = [len(nodes) - 1]
    print(f'scaled by {scale:.4f} to a {WHEEL_BASE} m wheel base')


if __name__ == '__main__':
    raise SystemExit(main())
