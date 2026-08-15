#!/usr/bin/env python3
"""Rewrites a .glb with its embedded images resized.

    python3 tool/shrink_glb.py assets/models/penguin.glb 512

A character seen from six metres behind does not need 1024-pixel maps, and this
stack has no compressed texture formats — `flutter_gpu` exposes none — so every
image lands in device memory as raw RGBA whatever its PNG cost on disk. Four
1024s are 16 MB; four 512s are 4 MB.

Uses macOS `sips` rather than Pillow, which is not a dependency of anything here.
"""

import json
import struct
import subprocess
import sys
import tempfile
from pathlib import Path


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    path, side = Path(sys.argv[1]), int(sys.argv[2])

    blob = path.read_bytes()
    json_len, json_kind = struct.unpack_from('<II', blob, 12)
    if json_kind != 0x4E4F534A:
        raise SystemExit('first chunk is not JSON; not a glTF 2.0 binary')
    doc = json.loads(blob[20:20 + json_len].decode('utf-8'))
    bin_len, _ = struct.unpack_from('<II', blob, 20 + json_len)
    binary = bytearray(blob[28 + json_len:28 + json_len + bin_len])

    views = doc['bufferViews']
    # Rebuilt from scratch: resizing changes every length, so every offset after
    # the first image would be wrong if they were edited in place.
    pieces: list[bytes] = []
    with tempfile.TemporaryDirectory() as work:
        for index, view in enumerate(views):
            start = view.get('byteOffset', 0)
            data = bytes(binary[start:start + view['byteLength']])
            if index in _image_views(doc):
                data = _resized(data, side, Path(work) / f'{index}.png')
            pieces.append(data)

    rebuilt = bytearray()
    for view, data in zip(views, pieces):
        # Four-byte alignment, which the specification requires of every view.
        while len(rebuilt) % 4:
            rebuilt.append(0)
        view['byteOffset'] = len(rebuilt)
        view['byteLength'] = len(data)
        rebuilt += data
    while len(rebuilt) % 4:
        rebuilt.append(0)
    doc['buffers'][0]['byteLength'] = len(rebuilt)

    text = json.dumps(doc, separators=(',', ':')).encode('utf-8')
    text += b' ' * ((4 - len(text) % 4) % 4)

    out = bytearray()
    out += struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(text) + 8 + len(rebuilt))
    out += struct.pack('<II', len(text), 0x4E4F534A) + text
    out += struct.pack('<II', len(rebuilt), 0x004E4942) + rebuilt
    path.write_bytes(out)
    print(f'{path.name}: {len(blob) // 1024} KB -> {len(out) // 1024} KB')
    return 0


def _image_views(doc) -> set[int]:
    return {
        image['bufferView']
        for image in doc.get('images', [])
        if 'bufferView' in image
    }


def _resized(data: bytes, side: int, scratch: Path) -> bytes:
    scratch.write_bytes(data)
    subprocess.run(
        ['sips', '-Z', str(side), '-s', 'format', 'png', str(scratch),
         '--out', str(scratch)],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return scratch.read_bytes()


if __name__ == '__main__':
    raise SystemExit(main())
