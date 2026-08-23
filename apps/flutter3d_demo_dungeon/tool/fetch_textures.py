#!/usr/bin/env python3
"""Fetches the level textures from ambientCG and packs them for the game.

Why a script rather than a folder of files somebody once downloaded: the
provenance of every texture in the game has to be checkable, and the only
honest way to record where an asset came from is to keep the thing that fetches
it. Re-running this reproduces the contents of assets/textures exactly.

ambientCG publishes under CC0. LICENSES.md is written from the same table that
drives the download, so the two cannot drift.

Each material becomes three files:

    <name>_albedo.jpg   base colour, sRGB
    <name>_normal.png   tangent-space normal, OpenGL convention (green up)
    <name>_orm.png      occlusion in red, roughness in green, metallic in blue

ORM is glTF's packing, which is what the renderer already binds. PNG for the
normal and the ORM because JPEG's chroma subsampling turns a normal map
blotchy and quantises roughness into visible bands; JPEG for the albedo, where
it costs nothing anybody can see.

Usage:  python3 tool/fetch_textures.py [--size 512]
"""

import argparse
import io
import os
import pathlib
import urllib.request
import zipfile

from PIL import Image

# The whole art bill of materials for the crypt. Adding a texture means adding
# a row here and running this again.
MATERIALS = [
    ("wall", "Bricks075A", "Irregular stone blocks, the walls of the crypt"),
    ("floor", "PavingStones151", "Grey setts, the floors"),
    ("ceiling", "Concrete042A", "Mottled grey, the ceilings"),
    ("stone", "PavingStones128", "Cut ashlar, pillars and stairs"),
    ("metal", "Metal046B", "Dark worn iron, doors and lifts"),
]

SOURCE = "https://ambientcg.com/get?file={asset}_1K-PNG.zip"
CREDIT = "https://ambientcg.com/view?id={asset}"

# urllib's default user agent is refused by the CDN.
AGENT = "flutter3d-dungeon/1.0 (texture fetch; https://ambientcg.com)"


def fetch(asset: str, cache: pathlib.Path) -> zipfile.ZipFile:
    archive = cache / f"{asset}_1K-PNG.zip"
    if not archive.exists():
        print(f"  downloading {asset}")
        request = urllib.request.Request(
            SOURCE.format(asset=asset), headers={"User-Agent": AGENT}
        )
        with urllib.request.urlopen(request, timeout=300) as response:
            archive.write_bytes(response.read())
    return zipfile.ZipFile(archive)


def read(zf: zipfile.ZipFile, asset: str, suffix: str) -> Image.Image | None:
    name = f"{asset}_1K-PNG_{suffix}.png"
    if name not in zf.namelist():
        return None
    return Image.open(io.BytesIO(zf.read(name)))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--size", type=int, default=512)
    parser.add_argument(
        "--out",
        default=str(pathlib.Path(__file__).resolve().parent.parent
                    / "assets" / "textures"),
    )
    parser.add_argument("--cache", default=os.environ.get("TMPDIR", "/tmp"))
    args = parser.parse_args()

    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    cache = pathlib.Path(args.cache) / "ambientcg"
    cache.mkdir(parents=True, exist_ok=True)
    size = (args.size, args.size)

    rows = []
    for name, asset, why in MATERIALS:
        print(f"{name} <- {asset}")
        zf = fetch(asset, cache)

        colour = read(zf, asset, "Color")
        if colour is None:
            raise SystemExit(f"{asset} has no colour map")
        colour.convert("RGB").resize(size, Image.LANCZOS).save(
            out / f"{name}_albedo.jpg", quality=88, optimize=True
        )

        # OpenGL convention: +Y is up. The renderer's tangent basis is built
        # with bitangent = cross(normal, tangent) * w and w = -1, which is what
        # NormalGL expects; NormalDX would invert every dent into a bump.
        normal = read(zf, asset, "NormalGL")
        if normal is None:
            raise SystemExit(f"{asset} has no NormalGL map")
        normal.convert("RGB").resize(size, Image.LANCZOS).save(
            out / f"{name}_normal.png", optimize=True
        )

        # A missing channel is the neutral value, not a failure: a material
        # with no occlusion map is unoccluded, and one with no metalness map is
        # a dielectric. Both are what the absent file means.
        white = Image.new("L", size, 255)
        black = Image.new("L", size, 0)

        def channel(suffix: str, fallback: Image.Image) -> Image.Image:
            image = read(zf, asset, suffix)
            if image is None:
                return fallback
            return image.convert("L").resize(size, Image.LANCZOS)

        Image.merge(
            "RGB",
            (
                channel("AmbientOcclusion", white),
                channel("Roughness", white),
                channel("Metalness", black),
            ),
        ).save(out / f"{name}_orm.png", optimize=True)

        rows.append((name, asset, why))

    licences = out / "LICENSES.md"
    licences.write_text(
        "# Texture provenance\n\n"
        "Every texture here was fetched by `tool/fetch_textures.py`, which is\n"
        "the record of where it came from. Re-run that script to reproduce\n"
        "this directory.\n\n"
        "All of it is from [ambientCG](https://ambientcg.com), published under\n"
        "[CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) — public\n"
        "domain, no attribution required. The credits below are given because\n"
        "not being required to say where something came from is a poor reason\n"
        "not to.\n\n"
        "| File prefix | Source | Licence | Used for |\n"
        "| --- | --- | --- | --- |\n"
        + "".join(
            f"| `{name}_*` | [{asset}]({CREDIT.format(asset=asset)}) | CC0 1.0 "
            f"| {why} |\n"
            for name, asset, why in rows
        )
        + "\nEach prefix has three files: `_albedo.jpg` (sRGB base colour),\n"
        "`_normal.png` (tangent space, OpenGL green-up) and `_orm.png`\n"
        "(occlusion in red, roughness in green, metallic in blue — glTF's\n"
        "packing).\n"
    )
    print(f"\nwrote {len(rows)} materials and LICENSES.md to {out}")


if __name__ == "__main__":
    main()
