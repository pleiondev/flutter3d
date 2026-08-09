#!/usr/bin/env python3
"""Packs a model's loose texture maps into the three files the game uses.

Downloaded models ship their maps however the artist exported them — usually
Base_Color, Normal, Roughness and Metallic as four separate images at 2K. The
game wants the same three files it uses for everything else:

    <name>_albedo.jpg   base colour
    <name>_normal.png   tangent space, OpenGL green-up
    <name>_orm.png      occlusion red, roughness green, metallic blue

Matching is by substring and case-insensitive, because "Base_Color.jpg",
"basecolor.png" and "albedo.jpg" are all the same thing and arguing with each
new artist about it is not work.

Usage:
  python3 tool/pack_maps.py --from ~/Downloads/key/textures --name key
"""

import argparse
import pathlib

from PIL import Image

# First match wins, so the more specific spelling goes first.
PATTERNS = {
    "albedo": ("base_color", "basecolor", "albedo", "diffuse", "color"),
    "normal": ("normalgl", "normal"),
    "roughness": ("roughness", "rough"),
    "metallic": ("metallic", "metalness", "metal"),
    "occlusion": ("ambientocclusion", "occlusion", "_ao", "ao_"),
}


def find(directory: pathlib.Path, kind: str) -> pathlib.Path | None:
    files = [f for f in sorted(directory.iterdir()) if f.is_file()]
    for pattern in PATTERNS[kind]:
        for f in files:
            if pattern in f.name.lower():
                # "Normal" would otherwise claim "NormalDX" as well; the
                # OpenGL one is what the renderer's handedness expects.
                if kind == "normal" and "dx" in f.name.lower():
                    continue
                return f
    return None


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--from", dest="source", required=True)
    parser.add_argument("--name", required=True)
    parser.add_argument("--size", type=int, default=512)
    parser.add_argument(
        "--out",
        default=str(pathlib.Path(__file__).resolve().parent.parent
                    / "assets" / "textures"),
    )
    args = parser.parse_args()

    source = pathlib.Path(args.source).expanduser()
    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    size = (args.size, args.size)

    albedo = find(source, "albedo")
    if albedo is None:
        raise SystemExit(f"no base colour map in {source}")
    Image.open(albedo).convert("RGB").resize(size, Image.LANCZOS).save(
        out / f"{args.name}_albedo.jpg", quality=90, optimize=True
    )
    print(f"albedo   <- {albedo.name}")

    normal = find(source, "normal")
    if normal is not None:
        Image.open(normal).convert("RGB").resize(size, Image.LANCZOS).save(
            out / f"{args.name}_normal.png", optimize=True
        )
        print(f"normal   <- {normal.name}")

    # A missing channel is its neutral value, not a failure: no occlusion map
    # means unoccluded, and no metalness map means a dielectric.
    def channel(kind: str, default: int) -> Image.Image:
        found = find(source, kind)
        if found is None:
            print(f"{kind:8} <- none, using {default}")
            return Image.new("L", size, default)
        print(f"{kind:8} <- {found.name}")
        return Image.open(found).convert("L").resize(size, Image.LANCZOS)

    Image.merge("RGB", (
        channel("occlusion", 255),
        channel("roughness", 255),
        channel("metallic", 0),
    )).save(out / f"{args.name}_orm.png", optimize=True)

    print(f"wrote {args.name}_* to {out}")


if __name__ == "__main__":
    main()
