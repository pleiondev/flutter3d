#!/usr/bin/env python3
"""Fetches the weapon models from poly.pizza and orients them for the hand.

Why a script rather than two files somebody once downloaded: the same reason
`fetch_textures.py` gives. The provenance of every asset in this game has to be
checkable, and the only honest way to record where one came from is to keep the
thing that fetches it. Re-running this reproduces `assets/models/weapon_*.glb`
exactly, and LICENSES.md is written from the same table that drives the
download, so the two cannot drift.

**This one both fetches and prepares, unlike `prepare_monsters.py`.** The
monsters were downloaded by hand because their pack ships as a Google Drive
folder, and only their preparation is scripted. These have direct URLs, so the
stronger convention is available and is used.

Quaternius publishes the packs themselves as Blend, FBX and OBJ — no glTF at
all. poly.pizza is where the glTF comes from: it converts the uploads with
FBX2glTF, which is why every monster in this game says `FBX2glTF v0.9.7` in its
generator string. That is the only reason these are reachable without a
converter on the machine.

**The licence is per model, not per pack.** Quaternius' own pack pages say CC0,
and poly.pizza records some of the same author's uploads as CC-BY 3.0 — the
animated pistol is one. Both models here are the CC0 ones, and the licence in
the table below is the one poly.pizza states for that upload rather than the one
the pack page states for the set. Where two sources disagree about a licence,
the narrower claim is the safe one to record.

Usage:  python3 tool/fetch_weapons.py
"""

import json
import math
import struct
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
MODELS = HERE.parent / "assets" / "models"

#: Which download becomes which weapon, and how long it should end up.
#:
#: The lengths are the procedural blocks these replace, measured along the
#: barrel in `weapon_models.dart`, and matching them is not cosmetic: the rest
#: position, the bob and the recoil in `WeaponView` are all tuned against a
#: weapon of about this size, and a model twice as long is a barrel through the
#: middle of the screen.
#: `sits` is where the model has to end up in the holder's own space: the
#: **lowest point** of the blocks it replaces, and their middle along the
#: barrel. Both measured out of `weapon_models.dart` rather than guessed.
#:
#: **Length alone is not enough**, which the first version of this assumed. Both
#: models are drawn upward from their origin and both sets of blocks hang down
#: from theirs, so a pistol of the right length still floated seven centimetres
#: above the hand — "висит в воздухе" is what it looked like.
#:
#: **Nor is the middle**, which the second version used. A model is slimmer than
#: the blocks that stood in for it — the shotgun is ten centimetres deep against
#: their fifteen — so matching middles leaves the thin one's underside floating,
#: and the shotgun was still too high with its centre exactly right. The bottom
#: edge is what a player reads as where the weapon is held, so that is what is
#: matched.
ROSTER = (
    # poly.pizza id, file id, asset, length, sits (bottom y, centre z), title, licence
    ("J3i9KDQ3kt", "f5a88c73-af97-49ca-8650-4bde579d2f80",
     "weapon_pistol.glb", 0.30, (-0.147, -0.061), "Pistol", "CC0 1.0"),
    ("ZmPTnh7njL", "f71d6771-f512-4374-bd23-ba00b564db68",
     "weapon_shotgun.glb", 0.62, (-0.109, -0.118), "Shotgun", "CC0 1.0"),
)

AUTHOR = "Quaternius (https://quaternius.com)"

LICENCES = {
    "CC0 1.0": "CC0 1.0 (https://creativecommons.org/publicdomain/zero/1.0/)",
    "CC-BY 3.0": "CC-BY 3.0 (https://creativecommons.org/licenses/by/3.0/)",
}

#: Where the model points, and where a held weapon has to point.
#:
#: Both of these are modelled down +X. The view model is drawn by a camera
#: looking down -Z like every other camera in the engine, so the barrel has to
#: turn a quarter turn about Y to face away from the player. Baked here rather
#: than set on the node at load, for the same reason the monsters' scale is
#: baked: a transform the game has to remember to apply is a transform some
#: future call site will forget.
QUARTER_TURN = math.pi / 2.0


def read(path_or_bytes):
    """The JSON chunk and the binary chunk of a GLB."""
    data = (path_or_bytes if isinstance(path_or_bytes, bytes)
            else Path(path_or_bytes).read_bytes())
    if data[:4] != b"glTF":
        raise SystemExit("not a GLB")
    length = struct.unpack("<I", data[12:16])[0]
    document = json.loads(data[20:20 + length])
    rest = 20 + length
    binary_length = struct.unpack("<I", data[rest:rest + 4])[0]
    return document, data[rest + 8:rest + 8 + binary_length]


def write(path: Path, document, binary: bytes) -> None:
    """A GLB back out, with both chunks padded the way the format wants."""
    text = json.dumps(document, separators=(",", ":")).encode("utf-8")
    text += b" " * (-len(text) % 4)
    body = binary + b"\0" * (-len(binary) % 4)
    total = 12 + 8 + len(text) + 8 + len(body)
    out = bytearray()
    out += b"glTF" + struct.pack("<II", 2, total)
    out += struct.pack("<I", len(text)) + b"JSON" + text
    out += struct.pack("<I", len(body)) + b"BIN\0" + body
    path.write_bytes(bytes(out))


def _matrix(node):
    """A node's local transform as a column-major 4x4."""
    if "matrix" in node:
        return list(node["matrix"])
    tx, ty, tz = node.get("translation", [0.0, 0.0, 0.0])
    x, y, z, w = node.get("rotation", [0.0, 0.0, 0.0, 1.0])
    scale = node.get("scale", [1.0, 1.0, 1.0])
    columns = (
        (1 - 2 * (y * y + z * z), 2 * (x * y + z * w), 2 * (x * z - y * w)),
        (2 * (x * y - z * w), 1 - 2 * (x * x + z * z), 2 * (y * z + x * w)),
        (2 * (x * z + y * w), 2 * (y * z - x * w), 1 - 2 * (x * x + y * y)),
    )
    out = [0.0] * 16
    for c in range(3):
        for r in range(3):
            out[c * 4 + r] = columns[c][r] * scale[c]
    out[12], out[13], out[14], out[15] = tx, ty, tz, 1.0
    return out


def _times(a, b):
    out = [0.0] * 16
    for c in range(4):
        for r in range(4):
            out[c * 4 + r] = sum(a[k * 4 + r] * b[c * 4 + k] for k in range(4))
    return out


def measured_bounds(document):
    """How long the model is along its longest axis, in metres as it stands.

    **The node hierarchy has to be walked**, and the first version of this did
    not: it took the accessor bounds alone, which are the mesh's own numbers
    before any parent scales them. Both of these files carry a scale up on a
    parent node — the pistol's mesh measures two centimetres and the pistol is
    almost two metres — so the factor came out a hundred times too small and the
    weapon arrived thirty metres long.

    No skinning to account for, unlike the monsters: nothing here is rigged, so
    a vertex is drawn where its node puts it.
    """
    low = [1e9] * 3
    high = [-1e9] * 3
    identity = [1.0 if i % 5 == 0 else 0.0 for i in range(16)]
    stack = [(index, identity)
             for index in document["scenes"][document.get("scene", 0)]["nodes"]]
    while stack:
        index, parent = stack.pop()
        node = document["nodes"][index]
        world = _times(parent, _matrix(node))
        if "mesh" in node:
            for prim in document["meshes"][node["mesh"]]["primitives"]:
                accessor = document["accessors"][prim["attributes"]["POSITION"]]
                if "min" not in accessor:
                    continue
                # Every corner of the box, because a rotation turns the box and
                # transforming two opposite corners would miss the other six.
                for bits in range(8):
                    corner = [accessor["max" if bits >> axis & 1 else "min"][axis]
                              for axis in range(3)]
                    for axis in range(3):
                        value = sum(world[c * 4 + axis] * corner[c]
                                    for c in range(3)) + world[12 + axis]
                        low[axis] = min(low[axis], value)
                        high[axis] = max(high[axis], value)
        for child in node.get("children", []):
            stack.append((child, world))
    return low, high


def reparent(document, scale: float) -> None:
    """Puts every scene root under one node that turns and shrinks the lot.

    A new node rather than editing the roots' own transforms: a root may carry
    a rotation of its own, and composing two quaternions here to save one node
    is arithmetic with nothing checking it.
    """
    nodes = document.setdefault("nodes", [])
    scene = document["scenes"][document.get("scene", 0)]
    holder = {
        "name": "held",
        "children": list(scene["nodes"]),
        # A quarter turn about Y, as a quaternion: (0, sin(a/2), 0, cos(a/2)).
        "rotation": [0.0, math.sin(QUARTER_TURN / 2.0), 0.0,
                     math.cos(QUARTER_TURN / 2.0)],
        "scale": [scale, scale, scale],
        "translation": [0.0, 0.0, 0.0],
    }
    nodes.append(holder)
    scene["nodes"] = [len(nodes) - 1]


def settle(document, sits) -> None:
    """Slides the held model so it rests where [sits] says.

    Measured after [reparent] rather than reasoned about before it: the turn
    sends X to Z, so the offset needed in the holder's space is not the offset
    read off the model, and working it out on paper is arithmetic with nothing
    checking it. Measuring twice costs one more walk of a forty-node file.

    Bottom edge in Y, middle in Z, and X centred on nought rather than taken
    from the table — both weapons are symmetric about their own barrel, and a
    hand holding one off to the side is a hand holding it wrong.
    """
    low, high = measured_bounds(document)
    middle = [(low[axis] + high[axis]) / 2.0 for axis in range(3)]
    holder = document["nodes"][-1]
    holder["translation"] = [
        -middle[0],
        sits[0] - low[1],
        sits[1] - middle[2],
    ]


#: How bright the lightest part of a weapon comes out, linear.
#:
#: The value `weapon_models.dart` gives its gunmetal blocks, so a model and the
#: block it replaces sit at the same level in the same corridor.
LIT = 0.30


def relight(document) -> None:
    """Makes the weapon something a torch can pick out.

    **It arrived black.** Two reasons, and both are already written down one
    file away, in the comment above `_metal` in `weapon_models.dart`:

    *Metallic.* A metal surface reflects its surroundings and has almost no
    diffuse response, so with no environment map to reflect it renders very
    nearly black. This channel has no image-based lighting — it needs mip levels
    the engine cannot render to — and these arrive at `metallicFactor` 0.4. The
    blocks solved it by being a dark dielectric, and so does this.

    *Dark.* The base colours are darker again than that: the pistol's lightest
    material is 0.0998 against the blocks' 0.30, and its darkest is 0.0216. In a
    crypt lit by one torch that is not dark gunmetal, it is black.

    Scaled rather than replaced, and by one factor for the whole file, so the
    parts keep their relation to each other — a barrel stays lighter than the
    grip. Normalised off the lightest material rather than fixed, so the third
    weapon somebody adds is lit by the same rule and not by a number that
    happened to suit these two.
    """
    materials = document.get("materials", [])
    lightest = 0.0
    for material in materials:
        colour = material.get("pbrMetallicRoughness", {}).get(
            "baseColorFactor", [1.0, 1.0, 1.0, 1.0])
        lightest = max(lightest, max(colour[:3]))
    if lightest <= 0.0:
        raise SystemExit("every material is pure black; nothing to scale")

    scale = LIT / lightest
    for material in materials:
        pbr = material.setdefault("pbrMetallicRoughness", {})
        colour = pbr.get("baseColorFactor", [1.0, 1.0, 1.0, 1.0])
        pbr["baseColorFactor"] = [
            min(1.0, channel * scale) for channel in colour[:3]
        ] + [colour[3]]
        # Written out rather than left to default, and that matters: glTF's
        # default `metallicFactor` is **1.0**, so a material that says nothing
        # is fully metallic and therefore black here.
        pbr["metallicFactor"] = 0.0


def stamp(document, title: str, licence: str, source: str) -> None:
    """Writes who made this and under what, into the file itself.

    The same shape `prepare_monsters.py` writes. A LICENSES.md entry can be
    separated from its file by a copy; this cannot.
    """
    asset = document.setdefault("asset", {})
    asset.setdefault("version", "2.0")
    asset["extras"] = {
        "title": title,
        "author": AUTHOR,
        "license": LICENCES[licence],
        "source": f"https://poly.pizza/m/{source} ({title})",
        "modifiedBy": "apps/flutter3d_demo_dungeon/tool/fetch_weapons.py",
    }


def fetch(file_id: str) -> bytes:
    url = f"https://static.poly.pizza/{file_id}.glb"
    request = urllib.request.Request(url, headers={"User-Agent": "flutter3d"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read()


def main() -> None:
    MODELS.mkdir(parents=True, exist_ok=True)
    for model_id, file_id, out, length, sits, title, licence in ROSTER:
        document, binary = read(fetch(file_id))
        low, high = measured_bounds(document)
        was = max(high[axis] - low[axis] for axis in range(3))
        if was <= 0.0:
            raise SystemExit(f"{out}: no geometry to measure")
        reparent(document, length / was)
        settle(document, sits)
        relight(document)
        stamp(document, title, licence, model_id)
        write(MODELS / out, document, binary)
        held = document["nodes"][-1]["translation"]
        print(f"{out}: {was:.2f} -> {length:.2f} along the barrel, "
              f"rests at {held[1] + low[1] * (length / was):+.3f}, "
              f"{licence}, {(MODELS / out).stat().st_size // 1024} KiB")


if __name__ == "__main__":
    main()
