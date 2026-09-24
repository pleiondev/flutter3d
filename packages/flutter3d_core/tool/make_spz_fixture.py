"""Writes `test/formats/fixtures/splat/spz/` — `C6`.

    python3 -m venv /tmp/spz && /tmp/spz/bin/pip install spz
    /tmp/spz/bin/python tool/make_spz_fixture.py

**Written by the format's own reference library, not by this repository.**
The `spz` package is Niantic's C++ reader and writer behind a Python binding;
a fixture written by a Dart encoder of our own would share every
misunderstanding of the format with the Dart reader it is meant to check. So
the cloud below is packed by the reference as version 2 (gzip, three-byte
quaternions), 3 (gzip, smallest-three quaternions) and 4 (zstd, one stream per
attribute), and each is then *unpacked by the reference* and written out as a
PLY — the twin the test holds `parseSplatSpz` to.

The twins are the reference's decoding of the quantised file, not the floats
the cloud started as, so the test compares to float precision rather than to
the quantisation step. They are in PLY's own axes (right, down, front), which
is what the reference converts to when asked; the files store right, up,
back, so the test also proves the axis turn.

Checked in, so the test does not need this script or the library, and
regenerated only on purpose.
"""

import math
import os

import numpy as np
import spz

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'test', 'formats', 'fixtures', 'splat', 'spz')

COUNT = 48
DEGREE = 2  # 8 higher-band coefficients a splat, so the band order shows.


def cloud():
    """A deterministic cloud in PLY axes, spread over what a file can hold."""
    rng = np.random.default_rng(80)
    g = spz.GaussianCloud()
    g.sh_degree = DEGREE
    g.antialiased = False
    g.positions = rng.uniform(-3.0, 3.0, COUNT * 3).astype(np.float32)
    g.scales = rng.uniform(-5.0, -0.5, COUNT * 3).astype(np.float32)
    quats = rng.normal(size=(COUNT, 4))
    quats /= np.linalg.norm(quats, axis=1, keepdims=True)
    g.rotations = quats.reshape(-1).astype(np.float32)  # xyzw
    g.alphas = rng.uniform(-4.0, 4.0, COUNT).astype(np.float32)
    g.colors = rng.uniform(-2.5, 2.5, COUNT * 3).astype(np.float32)
    dim = (DEGREE + 1) ** 2 - 1
    g.sh = rng.uniform(-0.9, 0.9, COUNT * dim * 3).astype(np.float32)
    return g


def main():
    os.makedirs(OUT, exist_ok=True)
    source = cloud()
    for version in (2, 3, 4):
        pack = spz.PackOptions()
        pack.version = version
        pack.from_coord = spz.RDF
        spz_path = os.path.join(OUT, f'cloud_v{version}.spz')
        assert spz.save_spz(source, pack, spz_path), spz_path

        unpack = spz.UnpackOptions()
        unpack.to_coord = spz.RDF
        decoded = spz.load_spz(spz_path, unpack)
        assert decoded.num_points == COUNT

        twin = spz.PackOptions()
        twin.from_coord = spz.RDF
        ply_path = os.path.join(OUT, f'cloud_v{version}.ply')
        assert spz.save_splat_to_ply(decoded, twin, ply_path), ply_path
        print(f'wrote {spz_path} ({os.path.getsize(spz_path)} bytes) and '
              f'{ply_path} ({os.path.getsize(ply_path)} bytes)')


if __name__ == '__main__':
    main()
