#!/usr/bin/env python3
"""Turns the downloaded packs into the pieces and textures this game ships.

    python3 tool/prepare_models.py ~/Downloads

Every pack here is CC0 (see `assets/models/LICENSES.md`), which asks for
nothing. The script exists because the files as downloaded are not the files
this game wants:

* each Kenney model points at its texture as a sibling `Textures/*.png`, and
  several kits all call theirs `colormap.png`. The game picks the texture
  itself (`lib/src/kit.dart` — it needs the castle's in two team colours
  anyway), so the reference is taken out of the model and the texture is
  shipped once, under a name that says which kit it belongs to;
* the characters carry twenty-odd animation clips apiece, which a crowd drawn
  as one instanced batch never plays, so they are dropped;
* the ground textures arrive as 1024-pixel JPEGs with five maps beside them,
  and only the colour is used — the ground is painted once, at load, into a
  single picture of the whole map (`lib/src/ground_paint.dart`).

Nothing is moved, scaled or joined here: `lib/src/kit.dart` composes the
pieces in code, where a hall's layout is something a reader can see.
Run it again after re-downloading and the result is byte-identical.
"""

import json
import struct
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
MODELS = HERE.parent / 'assets' / 'models'
TEXTURES = HERE.parent / 'assets' / 'textures'

CASTLE = 'kenney_castle-kit.zip'
ARENA = 'kenney_mini-arena.zip'
BLOCKY = 'kenney_blocky-characters_20.zip'
NATURE = 'kenney_nature-kit.zip'

# (archive, member, shipped name)
PIECES = [
    *[(CASTLE, f'Models/GLB format/{name}.glb', f'castle-{name}.glb') for name in (
        'tower-hexagon-base', 'tower-hexagon-mid', 'tower-hexagon-roof', 'tower-square-base', 'tower-square-mid-windows',
        'tower-square-top-roof-high', 'wall', 'flag', 'flag-banner-long',
        'siege-ram',
    )],
    (ARENA, 'Models/GLB format/character-soldier.glb', 'arena-soldier.glb'),
    (ARENA, 'Models/GLB format/weapon-spear.glb', 'arena-spear.glb'),
    (BLOCKY, 'Models/GLB format/character-p.glb', 'blocky-p.glb'),
    (BLOCKY, 'Models/GLB format/character-k.glb', 'blocky-k.glb'),
    *[(NATURE, f'Models/GLTF format/{name}.glb', f'nature-{name}.glb') for name in (
        'tree_pineTallA_detailed', 'tree_pineRoundC', 'tree_oak',
        'tree_default', 'tree_detailed', 'stone_tallA', 'stone_largeA',
        'stone_smallA',
    )],
]

# (archive, member, shipped name, longest side)
IMAGES = [
    (CASTLE, 'Models/GLB format/Textures/colormap.png', 'castle-colormap.png', 512),
    (ARENA, 'Models/GLB format/Textures/colormap.png', 'arena-colormap.png', 512),
    (BLOCKY, 'Models/GLB format/Textures/texture-p.png', 'blocky-p.png', 512),
    (BLOCKY, 'Models/GLB format/Textures/texture-k.png', 'blocky-k.png', 512),
    ('Grass001_1K-JPG.zip', 'Grass001_1K-JPG_Color.jpg', 'grass.jpg', 512),
    ('Grass004_1K-JPG.zip', 'Grass004_1K-JPG_Color.jpg', 'meadow.jpg', 512),
    ('Ground048_1K-JPG.zip', 'Ground048_1K-JPG_Color.jpg', 'dirt.jpg', 512),
    ('Rock030_1K-JPG.zip', 'Rock030_1K-JPG_Color.jpg', 'rock.jpg', 512),
    ('Ground054_1K-JPG.zip', 'Ground054_1K-JPG_Color.jpg', 'sand.jpg', 512),
]


def main() -> int:
    source = Path(sys.argv[1] if len(sys.argv) > 1 else '~/Downloads').expanduser()
    MODELS.mkdir(parents=True, exist_ok=True)
    TEXTURES.mkdir(parents=True, exist_ok=True)
    for archive, member, name in PIECES:
        doc, binary = _parse(_extract(source, archive, member))
        _strip(doc)
        _write(doc, binary, MODELS / name)
    for archive, member, name, side in IMAGES:
        _image(_extract(source, archive, member), TEXTURES / name, side)
    return 0


def _strip(doc) -> None:
    """Drops the clips and every texture reference, in place.

    The buffer views the images used stay in the binary chunk unreferenced —
    harmless, and the Kenney files carry none: their images are external.
    """
    for key in ('animations', 'images', 'textures', 'samplers'):
        doc.pop(key, None)
    for material in doc.get('materials', []):
        pbr = material.get('pbrMetallicRoughness', {})
        pbr.pop('baseColorTexture', None)
        pbr.pop('metallicRoughnessTexture', None)
        for key in ('normalTexture', 'occlusionTexture', 'emissiveTexture'):
            material.pop(key, None)


def _image(data: bytes, out: Path, side: int) -> None:
    with tempfile.TemporaryDirectory() as work:
        scratch = Path(work) / out.name
        scratch.write_bytes(data)
        kind = 'jpeg' if out.suffix == '.jpg' else 'png'
        args = ['sips', '-Z', str(side), '-s', 'format', kind]
        if kind == 'jpeg':
            args += ['-s', 'formatOptions', '85']
        subprocess.run(args + [str(scratch), '--out', str(out)], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print(f'{out.name}  {out.stat().st_size // 1024} KB')


def _extract(source: Path, archive: str, member: str) -> bytes:
    with zipfile.ZipFile(source / archive) as zf:
        return zf.read(member)


def _parse(blob: bytes):
    json_len, kind = struct.unpack_from('<II', blob, 12)
    if kind != 0x4E4F534A:
        raise SystemExit('first chunk is not JSON')
    doc = json.loads(blob[20:20 + json_len].decode('utf-8'))
    bin_len, _ = struct.unpack_from('<II', blob, 20 + json_len)
    return doc, bytearray(blob[28 + json_len:28 + json_len + bin_len])


def _write(doc, binary: bytearray, out: Path) -> None:
    doc['buffers'][0]['byteLength'] = len(binary)
    text = json.dumps(doc, separators=(',', ':')).encode('utf-8')
    text += b' ' * ((4 - len(text) % 4) % 4)
    while len(binary) % 4:
        binary.append(0)
    blob = bytearray(struct.pack('<III', 0x46546C67, 2,
                                 12 + 8 + len(text) + 8 + len(binary)))
    blob += struct.pack('<II', len(text), 0x4E4F534A) + text
    blob += struct.pack('<II', len(binary), 0x004E4942) + binary
    out.write_bytes(blob)
    print(f'{out.name}  {len(blob) // 1024} KB')


if __name__ == '__main__':
    raise SystemExit(main())
