#!/usr/bin/env python3
"""Turns the downloaded monsters into the ones this game ships.

    python3 tool/prepare_monsters.py ~/Downloads

Every step here is a change to somebody else's asset, so every step is also a
line in `assets/models/LICENSES.md`. These are CC0, which asks for nothing at
all — the record is kept anyway, because not being required to say where
something came from is a poor reason not to.

Run it again on the same downloads and the result is byte-identical; that is the
point of it being a script rather than a paragraph describing what was done by
hand.

## Do not run these through `prepare_model.mjs`

That script is the other one in this directory and it would destroy them. It
runs `simplify`, `weld` and `unweld`, which rewrite the vertex buffer — and on a
**skinned** mesh that means the joint weights no longer describe the vertices
they are attached to, so the monster arrives as a bag of triangles hinged around
the origin. It was written for a static key and it is correct for one.

This is modelled on `apps/platformer/tool/prepare_models.py` instead, which does
exactly two things and touches no geometry. That is the script that prepared
`hero.glb`, which is rigged and which the engine's own tests render.
"""

import json
import struct
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
MODELS = HERE.parent / "assets" / "models"

#: Which download becomes which monster, and how tall it should end up.
#:
#: The heights are `MonsterDef.height` from
#: `packages/flutter3d_game_shooter/lib/sample.dart`, and matching them is not
#: cosmetic: the capsule these replace is the collision shape, so a model taller
#: than its own hitbox is a monster you shoot over the head of.
ROSTER = (
    # file            → asset            height  what it is
    ("frog.glb", "monster_runner.glb", 1.7, "Frog"),
    ("wizard.glb", "monster_shooter.glb", 1.8, "Wizard"),
    ("yeti.glb", "monster_tank.glb", 2.4, "Yeti"),
)

#: The exporter's prefix on every clip name.
#:
#: Stripped, because it is a fact about the Blender file rather than about the
#: animation — every clip in every one of these carries it, so it distinguishes
#: nothing. What it costs to leave is a game whose code says
#: `'CharacterArmature|Idle'`, which reads as a mistake somebody has not noticed
#: yet.
PREFIX = "CharacterArmature|"


def read(path: Path):
    """The JSON chunk and the binary chunk of a GLB."""
    data = path.read_bytes()
    if data[:4] != b"glTF":
        raise SystemExit(f"{path} is not a GLB")
    length = struct.unpack("<I", data[12:16])[0]
    document = json.loads(data[20:20 + length])
    rest = data[20 + length:]
    kind = struct.unpack("<I", rest[4:8])[0]
    if kind != 0x004E4942:
        raise SystemExit(f"{path}: expected a BIN chunk after the JSON")
    size = struct.unpack("<I", rest[0:4])[0]
    return document, rest[8:8 + size]


def write(document, binary, out: Path) -> None:
    text = json.dumps(document, separators=(",", ":")).encode()
    text += b" " * (-len(text) % 4)
    binary += b"\0" * (-len(binary) % 4)
    total = 12 + 8 + len(text) + 8 + len(binary)
    with out.open("wb") as f:
        f.write(b"glTF" + struct.pack("<II", 2, total))
        f.write(struct.pack("<II", len(text), 0x4E4F534A) + text)
        f.write(struct.pack("<II", len(binary), 0x004E4942) + binary)


def rendered_height(document) -> float:
    """How tall the model comes out, in metres.

    **Not the mesh bounds.** These are skinned, so the vertex positions are in
    the skin's own space — a fiftieth of a metre — and the size comes from the
    scale on the armature node above them. Reading one without the other is how
    a two-metre monster measures four centimetres.
    """
    lo, hi = 1e9, -1e9
    for mesh in document.get("meshes", []):
        for prim in mesh.get("primitives", []):
            a = document["accessors"][prim["attributes"]["POSITION"]]
            lo = min(lo, a["min"][1])
            hi = max(hi, a["max"][1])
    scale = 1.0
    for node in document.get("nodes", []):
        if node.get("name") == "CharacterArmature":
            scale = node.get("scale", [1.0, 1.0, 1.0])[1]
            break
    return (hi - lo) * scale


def scale_root(document, factor: float) -> None:
    """Folds [factor] into the scene's roots, so nothing scales at runtime."""
    for index in document["scenes"][document.get("scene", 0)]["nodes"]:
        node = document["nodes"][index]
        scale = node.get("scale", [1.0, 1.0, 1.0])
        node["scale"] = [s * factor for s in scale]


def strip_clip_prefix(document) -> int:
    renamed = 0
    for clip in document.get("animations", []):
        name = clip.get("name", "")
        if name.startswith(PREFIX):
            clip["name"] = name[len(PREFIX):]
            renamed += 1
    return renamed


def stamp(document, *, title: str, source: str) -> None:
    """Writes the provenance into the file, so it travels with it.

    The platformer's penguin carries the same, and the reason is written down
    there: a licence table beside a binary is a table somebody has to remember
    to update, and one inside it is one that arrives with the copy.
    """
    document.setdefault("asset", {})["extras"] = {
        "title": title,
        "author": "Quaternius (https://quaternius.com)",
        "license": "CC0 1.0 "
                   "(https://creativecommons.org/publicdomain/zero/1.0/)",
        "source": source,
        "modifiedBy": "apps/dungeon/tool/prepare_monsters.py",
    }


def main() -> int:
    source = Path(sys.argv[1] if len(sys.argv) > 1 else "~/Downloads").expanduser()
    MODELS.mkdir(parents=True, exist_ok=True)

    for name, out, height, title in ROSTER:
        path = source / name
        if not path.exists():
            print(f"missing: {path}\n"
                  f"  Download the Ultimate Monsters pack from\n"
                  f"  https://quaternius.com/packs/ultimatemonsters.html\n"
                  f"  or the single models from https://poly.pizza, and put\n"
                  f"  {name} in {source}.")
            return 1

        document, binary = read(path)
        was = rendered_height(document)
        scale_root(document, height / was)
        renamed = strip_clip_prefix(document)
        stamp(document, title=title, source=f"https://poly.pizza ({title})")
        write(document, binary, MODELS / out)
        print(f"{out}: {was:.2f} m -> {height:.2f} m, {renamed} clips renamed, "
              f"{(MODELS / out).stat().st_size // 1024} KB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
