#!/usr/bin/env python3
"""Turns the downloaded models into the ones this game ships.

    python3 tool/prepare_models.py ~/Downloads

Every step here is a change to somebody else's asset, so every step is also a
line in `assets/models/LICENSES.md` — both models are CC BY, which asks that
modifications be stated.

Run it again after re-downloading and the result is byte-identical; that is the
point of it being a script rather than a paragraph describing what was done by
hand.
"""

import json
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
MODELS = HERE.parent / 'assets' / 'models'


def main() -> int:
    source = Path(sys.argv[1] if len(sys.argv) > 1 else '~/Downloads').expanduser()

    penguin = _read(source / 'weathered_penguin-bot.glb')
    _resize_images(penguin, 512)
    # 7.846 m as exported. The runner's body is 1.8 m and the game does not
    # scale at runtime — see `_dressRunner`, which takes the shape of the model
    # path that is known to work.
    _transform_root(penguin, scale=1.8 / 7.845971085131168)
    _write(penguin, MODELS / 'penguin.glb')

    # The shooter's key, carried across on request. It is the one asset in the
    # repository whose licence is unrecorded — see `assets/models/LICENSES.md`,
    # which now says so in two games instead of one.
    key = _read(HERE.parent.parent / 'dungeon' / 'assets' / 'models' / 'key.glb')
    # 0.6 m tall and standing on its base. A fixture's model is placed at the
    # collider's centre, so it comes down half its height; a fifth again bigger
    # because a key on the floor of a 120-metre field is easy to miss.
    _transform_root(key, scale=1.2, drop=0.3)
    _write(key, MODELS / 'key.glb')

    coin = _read(source / 'stylized_coin.glb')
    _resize_images(coin, 512)
    # 0.8 m across as exported, and standing on the floor beneath its origin. A
    # fixture's model is placed at the collider's *centre*, so the drop is not
    # decoration: without it every coin hovers half a metre up.
    #
    # 0.6 m across. It was exported at 0.8, halved to 0.4 because at 0.8 the
    # coins read as dinner plates beside a 1.8 m runner, and then put back up
    # by half again once the field grew: on a hundred and twenty metres of
    # ground a 0.4 m coin is a speck. The trigger stays 0.5 m — a pickup that
    # is easier to take than it looks is the right way round.
    _transform_root(coin, scale=0.6 / 0.8, drop=0.8)
    _make_lit(coin)
    _write(coin, MODELS / 'coin.glb')
    return 0


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


def _resize_images(model, side: int) -> None:
    """Shrinks every embedded image.

    There are no compressed pixel formats on this stack — `flutter_gpu` exposes
    none — so a map costs raw RGBA in device memory whatever its PNG weighed.
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
            if index in wanted:
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


def _transform_root(model, *, scale: float, drop: float = 0.0) -> None:
    """Folds a scale, and optionally a downward shift, into the scene's roots.

    Baked rather than applied at run time because the path that loads a model
    reliably here is the one that only sets a position.
    """
    doc, _, _ = model
    for index in doc['scenes'][doc.get('scene', 0)]['nodes']:
        node = doc['nodes'][index]
        if 'matrix' in node:
            m = list(node['matrix'])
            for column in range(3):
                for row in range(3):
                    m[column * 4 + row] *= scale
            m[12] *= scale
            m[13] = m[13] * scale - drop * scale
            m[14] *= scale
            node['matrix'] = m
        else:
            node['scale'] = [v * scale for v in node.get('scale', [1.0, 1.0, 1.0])]
            t = node.get('translation', [0.0, 0.0, 0.0])
            node['translation'] = [t[0] * scale, t[1] * scale - drop * scale,
                                   t[2] * scale]


def _make_lit(model) -> None:
    """Drops `KHR_materials_unlit`, and this one is a bug report.

    **An unlit material in this engine draws its base colour and never samples
    its albedo texture.** The coin arrived flat beige, the same beige whatever
    was done to the image — resized, converted, declared correctly — and became
    a gold coin with a star on it the moment the extension came off. The
    engine's `LightingModel.unlit` sets `usesMaterialMaps: false` while leaving
    `usesAlbedoTexture` true, and something between those two loses the texture.

    Until that is fixed, an asset authored unlit is loaded lit here. It is a
    workaround in an asset pipeline, which is the wrong place for it, and it is
    written down twice — here and in `assets/models/LICENSES.md`.
    """
    doc, _, _ = model
    doc.pop('extensionsUsed', None)
    for material in doc.get('materials', []):
        material.pop('extensions', None)
        pbr = material.setdefault('pbrMetallicRoughness', {})
        pbr['metallicFactor'] = 0.85
        pbr['roughnessFactor'] = 0.35


if __name__ == '__main__':
    raise SystemExit(main())
