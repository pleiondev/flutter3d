#!/usr/bin/env python3
"""Turns the downloaded packs into the two models this game ships.

    python3 tool/prepare_models.py ~/Downloads

Both packs are CC0, which asks for nothing — this script still exists because
the files as downloaded are not the files this game wants: a crowd unit is
built from six separate rigid parts under one armature, and both models
reference their texture as a sibling PNG rather than carrying it.

Run it again after re-downloading and the result is byte-identical, other
than the one step that shells out to `gltf-transform` (node_modules is not
vendored here, so that step needs network access the first time npx resolves
the package). The racing and platformer games have scripts of the same shape
and, so far, no shared code between the three.
"""

import json
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
MODELS = HERE.parent / 'assets' / 'models'

TEXTURE_SIDE = 512


def main() -> int:
    source = Path(sys.argv[1] if len(sys.argv) > 1 else '~/Downloads').expanduser()
    MODELS.mkdir(parents=True, exist_ok=True)

    _prepare_worker(source)
    _prepare_hall(source)
    return 0


# ------------------------------------------------------------------ worker


def _prepare_worker(source: Path) -> None:
    """`Blocky Characters`' `character-a.glb` -> `assets/models/worker.glb`.

    As downloaded this is six meshes — head, torso, two arms, two legs — each
    a rigid child of an armature bone, animated by moving the bone rather than
    by skinning. A crowd unit is drawn through `InstancedMeshNode`, which
    shares one mesh across every instance and cannot share six, so the six
    are joined into one before this ever reaches the engine. Animation is
    dropped in the same step: a crowd of a hundred does not carry a hundred
    independent clip players, and the six parts read as recognisably a person
    even standing in whatever pose the rig's rest position leaves them in.
    """
    with tempfile.TemporaryDirectory() as work:
        raw = _extract_glb(
            source, 'kenney_blocky-characters_20.zip',
            'Models/GLB format/character-a.glb',
        )
        texture = _extract(
            source, 'kenney_blocky-characters_20.zip',
            'Models/GLB format/Textures/texture-a.png',
        )

        doc, binary, name = _parse(raw)
        doc.pop('animations', None)
        _embed_image(doc, binary, 'Textures/texture-a.png', texture)
        _resize_images(doc, binary, TEXTURE_SIDE)
        joined_path = Path(work) / 'joined.glb'
        _write((doc, binary, name), Path(work) / 'stripped.glb')
        _run_gltf_transform_join(Path(work) / 'stripped.glb', joined_path)

        joined = _read_file(joined_path)
        # Scaled by height alone — the same call the platformer's own script
        # makes for its runner, and for the same reason: a low-poly figure's
        # width is however far its rest pose holds its arms, and only the
        # height is a measurement worth matching to `UnitSize.height` (1.2 m,
        # `packages/flutter3d_game_strategy/lib/bridge.dart`).
        #
        # Grounded rather than centred, unlike a `CuboidShape` unit: the model
        # already stands on its own feet at the local origin, once the join's
        # own baked bone offsets are folded in below, and `sync()` places a
        # unit at ground level with no added lift when a real mesh is set —
        # see `unitMesh` in `bridge.dart`.
        _ground_and_scale_root(joined, target_height=1.2)
        _rename_root(joined, 'worker')
        _write(joined, MODELS / 'worker.glb')


def _run_gltf_transform_join(src: Path, dst: Path) -> None:
    subprocess.run(
        ['npx', '--yes', '@gltf-transform/cli@latest', 'join', str(src), str(dst)],
        check=True,
    )


# -------------------------------------------------------------------- hall


def _prepare_hall(source: Path) -> None:
    """`Castle Kit`'s `tower-square.glb` -> `assets/models/hall.glb`.

    Already one mesh, one primitive, one node at the identity transform — the
    only thing wrong with it is the same thing wrong with the racing game's
    buildings before their own script ran: the texture is a sibling PNG,
    useless to a bundle that resolves nothing relative to an asset path.
    """
    raw = _extract_glb(
        source, 'kenney_castle-kit.zip', 'Models/GLB format/tower-square.glb',
    )
    texture = _extract(
        source, 'kenney_castle-kit.zip',
        'Models/GLB format/Textures/colormap.png',
    )
    doc, binary, name = _parse(raw)
    _embed_image(doc, binary, 'Textures/colormap.png', texture)
    _resize_images(doc, binary, TEXTURE_SIDE)
    _write((doc, binary, name), MODELS / 'hall.glb')


# --------------------------------------------------------------- zip / glb


def _extract(source: Path, archive: str, member: str) -> bytes:
    import zipfile
    with zipfile.ZipFile(source / archive) as zf:
        return zf.read(member)


def _extract_glb(source: Path, archive: str, member: str) -> bytes:
    return _extract(source, archive, member)


def _read_file(path: Path):
    return _parse(path.read_bytes())


def _parse(blob: bytes):
    json_len, kind = struct.unpack_from('<II', blob, 12)
    if kind != 0x4E4F534A:
        raise SystemExit('first chunk is not JSON')
    doc = json.loads(blob[20:20 + json_len].decode('utf-8'))
    bin_len, _ = struct.unpack_from('<II', blob, 20 + json_len)
    return doc, bytearray(blob[28 + json_len:28 + json_len + bin_len]), 'model.glb'


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


def _embed_image(doc, binary: bytearray, uri: str, data: bytes) -> None:
    """Turns an external `uri` image into a buffer view, in place."""
    while len(binary) % 4:
        binary.append(0)
    view_index = len(doc['bufferViews'])
    doc['bufferViews'].append(
        {'buffer': 0, 'byteOffset': len(binary), 'byteLength': len(data)},
    )
    binary.extend(data)
    for image in doc.get('images', []):
        if image.get('uri') == uri:
            image.pop('uri', None)
            image['bufferView'] = view_index
            image['mimeType'] = 'image/png'


def _resize_images(doc, binary: bytearray, side: int) -> None:
    """Shrinks every embedded image bigger than `side`. See the racing
    game's own `prepare_models.py` for why only the bigger ones move."""
    wanted = {i['bufferView'] for i in doc.get('images', []) if 'bufferView' in i}
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


def _png_size(data: bytes):
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        return None
    return struct.unpack('>II', data[16:24])


def _ground_and_scale_root(model, *, target_height: float) -> None:
    """Recentres X/Z on the origin, sets Y so the model stands on it, and
    scales by height alone, folded into the single root node `join` leaves.

    Derived from this model's own bounds rather than assumed: local vertex Y
    ran -1.0..1.7 (2.7 m), X ran -1.0..0.6 (a rest pose is not symmetric,
    whichever arm it favours), Z ran -0.4..0.4. `s = target_height /
    local_height`; the translation is solved so the scaled minimum Y lands on
    0 and the scaled X/Z centres land on 0.
    """
    doc, _, _ = model
    min_v = [1e9, 1e9, 1e9]
    max_v = [-1e9, -1e9, -1e9]
    for mesh in doc['meshes']:
        for prim in mesh['primitives']:
            acc = doc['accessors'][prim['attributes']['POSITION']]
            for i in range(3):
                min_v[i] = min(min_v[i], acc['min'][i])
                max_v[i] = max(max_v[i], acc['max'][i])

    height = max_v[1] - min_v[1]
    scale = target_height / height
    center_x = (min_v[0] + max_v[0]) / 2.0
    center_z = (min_v[2] + max_v[2]) / 2.0

    translation = [
        -scale * center_x,
        -scale * min_v[1],
        -scale * center_z,
    ]

    root_index = doc['scenes'][doc.get('scene', 0)]['nodes'][0]
    node = doc['nodes'][root_index]
    node.pop('matrix', None)
    node['scale'] = [scale, scale, scale]
    node['translation'] = translation


def _rename_root(model, name: str) -> None:
    doc, _, _ = model
    root_index = doc['scenes'][doc.get('scene', 0)]['nodes'][0]
    doc['nodes'][root_index]['name'] = name


if __name__ == '__main__':
    raise SystemExit(main())
