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


#: glTF component types, as (struct code, size in bytes).
_COMPONENTS = {5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2),
               5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}

#: How many components each accessor type holds.
_COUNTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def _elements(document, binary, index):
    """Every element of accessor [index], as tuples."""
    a = document["accessors"][index]
    view = document["bufferViews"][a["bufferView"]]
    code, size = _COMPONENTS[a["componentType"]]
    count = _COUNTS[a["type"]]
    stride = view.get("byteStride") or size * count
    base = view.get("byteOffset", 0) + a.get("byteOffset", 0)
    return [struct.unpack_from("<" + code * count, binary, base + i * stride)
            for i in range(a["count"])]


def _times(a, b):
    """Column-major 4x4 product, `a * b`."""
    out = [0.0] * 16
    for column in range(4):
        for row in range(4):
            out[column * 4 + row] = sum(
                a[k * 4 + row] * b[column * 4 + k] for k in range(4))
    return out


def _local(node):
    """A node's own transform, as a column-major matrix."""
    if "matrix" in node:
        return list(node["matrix"])
    tx, ty, tz = node.get("translation", [0.0, 0.0, 0.0])
    x, y, z, w = node.get("rotation", [0.0, 0.0, 0.0, 1.0])
    scale = node.get("scale", [1.0, 1.0, 1.0])
    m = [1 - 2 * (y * y + z * z), 2 * (x * y + z * w), 2 * (x * z - y * w), 0,
         2 * (x * y - z * w), 1 - 2 * (x * x + z * z), 2 * (y * z + x * w), 0,
         2 * (x * z + y * w), 2 * (y * z - x * w), 1 - 2 * (x * x + y * y), 0,
         0, 0, 0, 1]
    for column in range(3):
        for row in range(3):
            m[column * 4 + row] *= scale[column]
    m[12], m[13], m[14] = tx, ty, tz
    return m


def _world(document, parents, index):
    m = _local(document["nodes"][index])
    while index in parents:
        index = parents[index]
        m = _times(_local(document["nodes"][index]), m)
    return m


def rendered_height(document, binary) -> float:
    """How tall the model comes out on screen, in metres.

    **Skinned the way the shader skins it**, which is the whole point of this
    function and the reason it is forty lines rather than four.

    What was here before took the mesh's own bounding box and multiplied it by
    the scale on the armature node — a proxy, and a wrong one. A skinned vertex
    is not drawn where the accessor says it is: it is drawn at
    `jointWorld * inverseBind * v`, blended over the joints it names, and the
    two disagree whenever those matrices are not one shared transform — which
    they are not, because this script's own `scale_root` scales the hierarchy
    without touching the inverse binds it was authored against.

    The proxy was out by 1.6x on the frog, 1.1x on the wizard and 0.95x on the
    yeti, all in the same run: three monsters asked to be 1.7, 1.8 and 2.4 came
    out 2.74, 2.03 and 2.28. The frog fills a four-metre corridor and the
    player shoots over the head of a hitbox half its size.

    So this does the arithmetic the vertex shader does. It is slow — every
    vertex, in Python — and it runs three times, once per download.
    """
    parents = {}
    for index, node in enumerate(document.get("nodes", [])):
        for child in node.get("children", []):
            parents[child] = index

    low, high = 1e9, -1e9
    for node in document.get("nodes", []):
        if "mesh" not in node or "skin" not in node:
            continue
        skin = document["skins"][node["skin"]]
        binds = _elements(document, binary, skin["inverseBindMatrices"])
        joints = [_times(_world(document, parents, j), list(binds[k]))
                  for k, j in enumerate(skin["joints"])]

        for prim in document["meshes"][node["mesh"]]["primitives"]:
            places = _elements(document, binary, prim["attributes"]["POSITION"])
            named = _elements(document, binary, prim["attributes"]["JOINTS_0"])
            weights = _elements(document, binary, prim["attributes"]["WEIGHTS_0"])
            for place, uses, shares in zip(places, named, weights):
                total = sum(shares) or 1.0
                y = 0.0
                for joint, share in zip(uses, shares):
                    if share == 0.0:
                        continue
                    m = joints[joint]
                    y += (share / total) * (
                        m[1] * place[0] + m[5] * place[1] + m[9] * place[2]
                        + m[13])
                low, high = min(low, y), max(high, y)

    if high < low:
        raise SystemExit("no skinned mesh in this file")
    return high - low


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
        was = rendered_height(document, binary)
        scale_root(document, height / was)
        renamed = strip_clip_prefix(document)
        stamp(document, title=title, source=f"https://poly.pizza ({title})")
        write(document, binary, MODELS / out)
        print(f"{out}: {was:.2f} m -> {height:.2f} m, {renamed} clips renamed, "
              f"{(MODELS / out).stat().st_size // 1024} KB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
