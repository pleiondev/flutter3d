#!/usr/bin/env python3
"""Turns the downloaded models and textures into the ones Wreck Reef ships.

    python3 tool/prepare_models.py /tmp/reef-downloads

The downloads directory holds each source unpacked into a folder of its own
name, exactly as `assets/CREDITS.md` lists them:

    dutch_ship_medium/   Poly Haven glTF, 1k: .gltf, .bin, textures/*_diff_1k.jpg
    marble_bust_01/      the same
    treasure_chest/      the same
    rock_07/ rock_09/    the same
    man/man.glb          Quaternius' "Man", from poly.pizza
    Ground093C/ Rock053/ ambientCG 1K-JPG zips, unzipped

Every glb this writes is static and self-contained: one mesh per material,
positions, normals and texture coordinates (and colours where the source had
them), the base colour texture embedded as a JPEG and nothing else. The game
draws every one of them with the sea floor's own material, plain but for the
picture, so a model's normal, roughness and occlusion maps would be bytes
shipped for nobody. The reef rock alone keeps its normal map: the wall is
drawn close enough for the relief of its rock to be seen, and that relief is
what the map is.

What is changed on the way is said beside each model below: the ship is cut
down to what a wooden hull keeps after a century on the bottom, and the man is
posed swimming, his skin baked into plain vertices. Run it again on the same
downloads and the result is the same.
"""

import io
import json
import math
import struct
import sys
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
MODELS = HERE.parent / "assets" / "models"
TEXTURES = HERE.parent / "assets" / "textures"

_COMPONENTS = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16,
               5125: np.uint32, 5126: np.float32}
_WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


class Source:
    """A glTF or glb read into its JSON and its buffers."""

    def __init__(self, path):
        self.path = Path(path)
        data = self.path.read_bytes()
        if data[:4] == b"glTF":
            length = struct.unpack("<I", data[12:16])[0]
            self.json = json.loads(data[20:20 + length])
            rest = data[20 + length:]
            self.buffers = [rest[8:8 + struct.unpack("<I", rest[:4])[0]]]
        else:
            self.json = json.loads(data)
            self.buffers = [(self.path.parent / b["uri"]).read_bytes()
                            for b in self.json["buffers"]]

    def accessor(self, index):
        """The accessor's elements as floats, normalised where it says so."""
        a = self.json["accessors"][index]
        view = self.json["bufferViews"][a["bufferView"]]
        kind = _COMPONENTS[a["componentType"]]
        width = _WIDTH[a["type"]]
        size = np.dtype(kind).itemsize * width
        stride = view.get("byteStride", size)
        start = view.get("byteOffset", 0) + a.get("byteOffset", 0)
        raw = self.buffers[view.get("buffer", 0)]
        rows = np.empty((a["count"], width), dtype=kind)
        for i in range(a["count"]):
            at = start + i * stride
            rows[i] = np.frombuffer(raw, dtype=kind, count=width, offset=at)
        out = rows.astype(np.float64)
        if a.get("normalized"):
            out /= float(np.iinfo(kind).max)
        return out

    def node_matrices(self, pose=None):
        """Every node's world matrix, with [pose]'s extra turns applied on
        top of the rest pose: for a joint, a list of turns made one after
        the other, each an axis in the model's own frame and degrees, turning
        the joint and all under it about where it is.

        The axis is the model's, not the joint's, because a rig's joints
        each point their own way — an upper arm's x is nobody's idea of
        forward — and a pose written as "the forearm forward ninety degrees"
        should mean that."""
        nodes = self.json["nodes"]
        parent = {c: i for i, n in enumerate(nodes) for c in n.get("children", [])}
        local = [_trs(n.get("translation", [0, 0, 0]),
                      n.get("rotation", [0, 0, 0, 1]),
                      n.get("scale", [1, 1, 1])) for n in nodes]
        world = [None] * len(nodes)

        def resolve(i):
            if world[i] is None:
                p = parent.get(i)
                w = local[i] if p is None else resolve(p) @ local[i]
                name = nodes[i].get("name")
                if pose and name in pose:
                    frame = w[:3, :3] / np.linalg.norm(w[:3, :3], axis=0, keepdims=True)
                    turned = np.eye(3)
                    for axis, degrees in pose[name]:
                        turned = _axis_angle(axis, math.radians(degrees)) @ turned
                    turn = np.eye(4)
                    turn[:3, :3] = frame.T @ turned @ frame
                    w = w @ turn
                world[i] = w
            return world[i]

        for i in range(len(nodes)):
            resolve(i)
        return world


def _quat(q):
    x, y, z, w = q
    return np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ])


def _axis_angle(axis, angle):
    axis = np.asarray(axis, dtype=np.float64)
    axis /= np.linalg.norm(axis)
    s = math.sin(angle / 2)
    return _quat([axis[0] * s, axis[1] * s, axis[2] * s, math.cos(angle / 2)])


def _trs(t, r, s):
    m = np.eye(4)
    m[:3, :3] = _quat(r) @ np.diag(s)
    m[:3, 3] = t
    return m


class Part:
    """Triangles of one material, in the model's final frame."""

    def __init__(self, positions, normals, uvs, colours, indices, material):
        self.positions = positions
        self.normals = normals
        self.uvs = uvs
        self.colours = colours
        self.indices = indices
        self.material = material


def read_parts(source, keep=None, pose=None):
    """The meshes of the nodes named in [keep] (all when None), each placed
    by its node and, when skinned, bent into [pose] and baked."""
    j = source.json
    world = source.node_matrices(pose)
    parts = []
    for i, node in enumerate(j["nodes"]):
        if "mesh" not in node or (keep is not None and node.get("name") not in keep):
            continue
        skin = j["skins"][node["skin"]] if "skin" in node else None
        joints = None
        if skin is not None:
            inverse = source.accessor(skin["inverseBindMatrices"]).reshape(-1, 4, 4)
            # Stored column-major: each row of sixteen is a transposed matrix.
            joints = [world[jt] @ inverse[k].T for k, jt in enumerate(skin["joints"])]
        for prim in j["meshes"][node["mesh"]]["primitives"]:
            a = prim["attributes"]
            p = source.accessor(a["POSITION"])
            n = source.accessor(a["NORMAL"]) if "NORMAL" in a else np.zeros_like(p)
            uv = source.accessor(a["TEXCOORD_0"]) if "TEXCOORD_0" in a else np.zeros((len(p), 2))
            colour = source.accessor(a["COLOR_0"]) if "COLOR_0" in a else None
            if colour is not None and colour.shape[1] == 3:
                colour = np.hstack([colour, np.ones((len(colour), 1))])
            if joints is not None:
                which = source.accessor(a["JOINTS_0"]).astype(int)
                weight = source.accessor(a["WEIGHTS_0"])
                hp = np.hstack([p, np.ones((len(p), 1))])
                outp = np.zeros_like(p)
                outn = np.zeros_like(n)
                for v in range(len(p)):
                    m = sum(weight[v, k] * joints[which[v, k]] for k in range(4))
                    outp[v] = (m @ hp[v])[:3]
                    outn[v] = m[:3, :3] @ n[v]
                p, n = outp, outn
            else:
                m = world[i]
                p = (m[:3, :3] @ p.T).T + m[:3, 3]
                n = (np.linalg.inv(m[:3, :3]).T @ n.T).T
            n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
            idx = (source.accessor(prim["indices"]).astype(np.uint32).ravel()
                   if "indices" in prim else np.arange(len(p), dtype=np.uint32))
            parts.append(Part(p, n, uv, colour, idx, prim.get("material", 0)))
    return parts


def place(parts, matrix):
    """Every part moved by [matrix], normals with it."""
    normal = np.linalg.inv(matrix[:3, :3]).T
    for part in parts:
        part.positions = (matrix[:3, :3] @ part.positions.T).T + matrix[:3, 3]
        part.normals = (normal @ part.normals.T).T
        part.normals /= np.maximum(
            np.linalg.norm(part.normals, axis=1, keepdims=True), 1e-9)


def bounds(parts):
    every = np.vstack([p.positions for p in parts])
    return every.min(axis=0), every.max(axis=0)


def keep_triangles(part, test):
    """Only the triangles whose centre [test] passes, and only the vertices
    they use."""
    tri = part.indices.reshape(-1, 3)
    centres = part.positions[tri].mean(axis=1)
    tri = tri[np.array([test(c) for c in centres], dtype=bool)]
    used, remap = np.unique(tri.ravel(), return_inverse=True)
    part.positions = part.positions[used]
    part.normals = part.normals[used]
    part.uvs = part.uvs[used]
    if part.colours is not None:
        part.colours = part.colours[used]
    part.indices = remap.astype(np.uint32)


def jpeg(path, size):
    """[path] resized to fit [size] pixels a side, as JPEG bytes."""
    image = Image.open(path).convert("RGB")
    image.thumbnail((size, size), Image.LANCZOS)
    out = io.BytesIO()
    image.save(out, format="JPEG", quality=85, optimize=True)
    return out.getvalue()


def write_glb(path, parts, materials, anchors=None):
    """[parts] as one self-contained glb. [materials] maps a source material
    index to (name, base colour factor, JPEG bytes or None); [anchors] are
    empty nodes, name to (position, rotation quaternion), a game can hang
    things on."""
    blob = bytearray()
    views, accessors, meshes, nodes = [], [], [], []

    def add(array, kind, target=None):
        while len(blob) % 4:
            blob.append(0)
        data = np.ascontiguousarray(array, dtype=kind).tobytes()
        view = {"buffer": 0, "byteOffset": len(blob), "byteLength": len(data)}
        if target:
            view["target"] = target
        views.append(view)
        blob.extend(data)
        return len(views) - 1

    def accessor(array, kind, type_, component, target, minmax=False):
        a = {"bufferView": add(array, kind, target), "componentType": component,
             "count": len(array), "type": type_}
        if minmax:
            a["min"] = array.min(axis=0).tolist()
            a["max"] = array.max(axis=0).tolist()
        accessors.append(a)
        return len(accessors) - 1

    order = sorted(materials)
    gltf_materials, images, textures = [], [], []
    for index in order:
        name, factor, picture = materials[index]
        m = {"name": name, "pbrMetallicRoughness": {
            "baseColorFactor": list(factor), "metallicFactor": 0.0,
            "roughnessFactor": 0.9}}
        if picture is not None:
            images.append({"bufferView": add(np.frombuffer(picture, np.uint8), np.uint8),
                           "mimeType": "image/jpeg"})
            textures.append({"source": len(images) - 1})
            m["pbrMetallicRoughness"]["baseColorTexture"] = {"index": len(textures) - 1}
        gltf_materials.append(m)

    for index in order:
        mine = [p for p in parts if p.material == index and len(p.indices)]
        if not mine:
            continue
        base, pos, nor, uv, col, idx = 0, [], [], [], [], []
        for p in mine:
            pos.append(p.positions)
            nor.append(p.normals)
            uv.append(p.uvs)
            col.append(p.colours if p.colours is not None
                       else np.ones((len(p.positions), 4)))
            idx.append(p.indices + base)
            base += len(p.positions)
        attributes = {
            "POSITION": accessor(np.vstack(pos), np.float32, "VEC3", 5126, 34962, True),
            "NORMAL": accessor(np.vstack(nor), np.float32, "VEC3", 5126, 34962),
            "TEXCOORD_0": accessor(np.vstack(uv), np.float32, "VEC2", 5126, 34962),
        }
        if any(p.colours is not None for p in mine):
            attributes["COLOR_0"] = accessor(np.vstack(col), np.float32, "VEC4", 5126, 34962)
        meshes.append({"name": materials[index][0], "primitives": [{
            "attributes": attributes,
            "indices": accessor(np.concatenate(idx), np.uint32, "SCALAR", 5125, 34963),
            "material": order.index(index)}]})
        nodes.append({"name": materials[index][0], "mesh": len(meshes) - 1})
    for name, (position, rotation) in (anchors or {}).items():
        nodes.append({"name": name, "translation": [float(v) for v in position],
                      "rotation": [float(v) for v in rotation]})

    document = {
        "asset": {"version": "2.0", "generator": "flutter3d_demo_reef/tool/prepare_models.py"},
        "scene": 0, "scenes": [{"nodes": list(range(len(nodes)))}],
        "nodes": nodes, "meshes": meshes, "materials": gltf_materials,
        "accessors": accessors, "bufferViews": views,
        "buffers": [{"byteLength": len(blob)}],
    }
    if images:
        document["images"] = images
        document["textures"] = textures
    text = json.dumps(document, separators=(",", ":")).encode()
    text += b" " * (-len(text) % 4)
    while len(blob) % 4:
        blob.append(0)
    out = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(text) + 8 + len(blob))
    out += struct.pack("<II", len(text), 0x4E4F534A) + text
    out += struct.pack("<II", len(blob), 0x004E4942) + bytes(blob)
    path.write_bytes(out)
    print(f"{path.relative_to(HERE.parent)}: {len(out) / 1e6:.2f} MB, "
          f"{sum(len(p.indices) for p in parts) // 3} triangles")


def _rotation_to_quat(m):
    """A rotation matrix as a glTF quaternion (x, y, z, w)."""
    w = math.sqrt(max(0.0, 1 + m[0, 0] + m[1, 1] + m[2, 2])) / 2
    x = math.copysign(math.sqrt(max(0.0, 1 + m[0, 0] - m[1, 1] - m[2, 2])) / 2, m[2, 1] - m[1, 2])
    y = math.copysign(math.sqrt(max(0.0, 1 - m[0, 0] + m[1, 1] - m[2, 2])) / 2, m[0, 2] - m[2, 0])
    z = math.copysign(math.sqrt(max(0.0, 1 - m[0, 0] - m[1, 1] + m[2, 2])) / 2, m[1, 0] - m[0, 1])
    return [x, y, z, w]


def _hash(x, z):
    """A fixed pseudo-random number in [0, 1) for a lattice point."""
    h = (int(x) * 374761393 + int(z) * 668265263) & 0x7FFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0x7FFFFFFF
    return (h & 0xFFFF) / 0xFFFF


def _ragged(x, scale):
    """A line that wanders by about a metre: where rot stopped."""
    i = math.floor(x / scale)
    t = x / scale - i
    t = t * t * (3 - 2 * t)
    return _hash(i, 7) * (1 - t) + _hash(i + 1, 7) * t


def ship(downloads):
    """The Dutch ship, cut down to her bottom.

    The hull alone, without the rigging and the sails, scaled to the
    eighteen metres the game's timbers are laid out for, her keel at nought
    and her length along +x, bow forward. Then everything above a ragged line
    a couple of metres up the side goes, the line lower amidships on the port
    side where she broke, as wooden wrecks are found: the bottom kept by the
    sand, the upper works long gone to worm and current."""
    src = downloads / "dutch_ship_medium"
    parts = read_parts(Source(src / "dutch_ship_medium.gltf"),
                       keep={"dutch_ship_medium_hull"})
    low, high = bounds(parts)
    scale = 18.6 / (high[0] - low[0])
    # A little broader than she was built: the game's side timbers stand
    # 2.6 m either side of her keel, and the planking drawn should be where
    # a diver bumps into them.
    beam = 5.2 / (high[2] - low[2])
    m = np.diag([scale, scale, beam, 1.0])
    m[:3, 3] = [-(low[0] + high[0]) / 2 * scale, -low[1] * scale, -(low[2] + high[2]) / 2 * beam]
    place(parts, m)

    def kept(c):
        x, y, z = c
        line = 2.0 + 1.2 * _ragged(x, 1.7)
        # Higher at her ends, where the stem and the stern post stood.
        line += 1.4 * max(0.0, abs(x) - 6.5)
        # The breach: her port side open amidships, down nearly to the bilge.
        if z < -0.4 and -7.5 < x < 3.0:
            line = 0.9 + 0.8 * _ragged(x, 0.9)
        return y < line

    for part in parts:
        keep_triangles(part, kept)
    write_glb(MODELS / "wreck.glb", parts, {
        parts[0].material: ("hull", (1, 1, 1, 1),
                            jpeg(src / "textures/dutch_ship_medium_hull_diff_1k.jpg", 1024)),
    })


#: The swimming pose: each joint's turns over the man's rest pose, axes in
#: his standing frame (x his left, y up, z the way he faces) and degrees.
#: Upper arms a little forward of his sides and the forearms folded across
#: in front of him, so lying down his hands meet under his chest; legs from
#: the hip a little apart in a kick, knees eased; feet pointed along the
#: shins as fins hold them; and the head tipped back to look ahead.
SWIM = {
    "UpperArm.L": [((1, 0, 0), -25.0)],
    "UpperArm.R": [((1, 0, 0), -25.0)],
    "LowerArm.L": [((1, 0, 0), -65.0), ((0, 1, 0), -65.0)],
    "LowerArm.R": [((1, 0, 0), -65.0), ((0, 1, 0), 65.0)],
    "UpperLeg.L": [((1, 0, 0), -10.0)],
    "UpperLeg.R": [((1, 0, 0), 6.0)],
    "LowerLeg.L": [((1, 0, 0), 22.0)],
    "LowerLeg.R": [((1, 0, 0), 12.0)],
    "Foot.L": [((1, 0, 0), 60.0)],
    "Foot.R": [((1, 0, 0), 60.0)],
    "Neck": [((1, 0, 0), -25.0)],
    "Head": [((1, 0, 0), -25.0)],
}

#: The joints whose place the game hangs gear on.
ANCHORS = ("Head", "Torso", "Foot.L", "Foot.R", "Palm.L", "Palm.R")


def diver(downloads):
    """Quaternius' man, posed swimming and laid down.

    His skin is baked: every vertex moved by its joints into [SWIM] and the
    skeleton then dropped, so the game draws plain vertices with the sea's
    own material. He is scaled to 1.75 m and laid along +x, head forward,
    back up, his middle at the origin; the joints in [ANCHORS] go along as
    empty nodes, so the mask, the tank and the fins are put where his head,
    back and feet are."""
    source = Source(downloads / "man" / "man.glb")
    parts = read_parts(source, pose=SWIM)
    world = source.node_matrices(SWIM)
    names = [n.get("name") for n in source.json["nodes"]]
    standing = {name: world[names.index(name)] for name in ANCHORS}
    # Measured standing, before laying him down: height along y.
    rest = read_parts(source)
    low, high = bounds(rest)
    scale = 1.75 / (high[1] - low[1])
    middle = (low + high) / 2
    # Standing he looks along +z with his head up +y; lying, his head is +x
    # and his face looks down −y.
    lay = np.array([[0, 1, 0], [0, 0, -1], [-1, 0, 0]], dtype=np.float64)
    m = np.eye(4)
    m[:3, :3] = lay * scale
    m[:3, 3] = -(lay @ middle) * scale
    place(parts, m)
    anchors = {}
    for name, joint in standing.items():
        at = m @ joint[:, 3]
        turn = lay @ joint[:3, :3]
        turn /= np.linalg.norm(turn, axis=0, keepdims=True)
        anchors[name] = (at[:3], _rotation_to_quat(turn))
    materials = source.json["materials"]
    write_glb(MODELS / "diver.glb", parts, {
        i: (materials[i]["name"], tuple(materials[i]["pbrMetallicRoughness"]["baseColorFactor"]), None)
        for i in {p.material for p in parts}
    }, anchors=anchors)


def prop(downloads, name, out, height=None, size=512):
    """A Poly Haven model as it comes, its base on y = 0 and centred over
    the origin, scaled to [height] metres tall when that is given."""
    src = downloads / name
    parts = read_parts(Source(src / f"{name}.gltf"))
    low, high = bounds(parts)
    scale = 1.0 if height is None else height / (high[1] - low[1])
    m = np.diag([scale, scale, scale, 1.0])
    m[:3, 3] = [-(low[0] + high[0]) / 2 * scale, -low[1] * scale, -(low[2] + high[2]) / 2 * scale]
    place(parts, m)
    write_glb(MODELS / out, parts, {
        parts[0].material: (name, (1, 1, 1, 1),
                            jpeg(src / f"textures/{name}_diff_1k.jpg", size)),
    })


def textures(downloads):
    """The sand and the reef rock the floor is drawn with.

    The sand's ripples are there in its picture but faint, a few shades
    either way of its mean, and under a few metres of water with the
    caustics running over them they were gone: its contrast is stretched
    two and a half times about the mean.

    The rock carries its height in its alpha, from the published
    displacement map, half at the bottom of a crevice and one on a crest.
    The game draws the reef over the sand cut where that alpha times the
    vertex's share of rock falls below a half, so where the reef gives out
    the sand fills its hollows first and its crests stand out of the sand
    last, rather than the rock ending along a line."""
    sand = downloads / "Ground093C" / "Ground093C_1K-JPG_Color.jpg"
    picture = np.asarray(Image.open(sand).convert("RGB"), dtype=np.float64)
    mean = picture.reshape(-1, 3).mean(axis=0)
    picture = np.clip(mean + (picture - mean) * 2.5, 0, 255).astype(np.uint8)
    out = io.BytesIO()
    image = Image.fromarray(picture)
    image.thumbnail((1024, 1024), Image.LANCZOS)
    image.save(out, format="JPEG", quality=85, optimize=True)
    (TEXTURES / "sand.jpg").write_bytes(out.getvalue())
    print("assets/textures/sand.jpg")

    rock = downloads / "Rock053"
    colour = Image.open(rock / "Rock053_1K-JPG_Color.jpg").convert("RGB")
    height = np.asarray(
        Image.open(rock / "Rock053_1K-JPG_Displacement.jpg").convert("L"),
        dtype=np.float64)
    low, high = np.percentile(height, (2, 98))
    height = np.clip((height - low) / (high - low), 0, 1)
    alpha = Image.fromarray((127.5 + 127.5 * height).astype(np.uint8))
    image = colour.copy()
    image.putalpha(alpha.resize(colour.size, Image.LANCZOS))
    # 768 a side: an alpha channel keeps it a PNG, and at 1024 that is
    # two and a half megabytes for a picture seen through the water.
    image.thumbnail((768, 768), Image.LANCZOS)
    image.save(TEXTURES / "reef_rock.png", optimize=True)
    print("assets/textures/reef_rock.png")
    relief(downloads)


def relief(downloads):
    """The reef rock's relief: its published normal map, the OpenGL one
    (green up the picture), at the colour's 768 a side so the two lie on
    each other texel for texel."""
    rock = downloads / "Rock053"
    image = Image.open(rock / "Rock053_1K-JPG_NormalGL.jpg").convert("RGB")
    image.thumbnail((768, 768), Image.LANCZOS)
    image.save(TEXTURES / "reef_rock_normal.jpg", quality=90, optimize=True)
    print("assets/textures/reef_rock_normal.jpg")


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    downloads = Path(sys.argv[1])
    MODELS.mkdir(parents=True, exist_ok=True)
    TEXTURES.mkdir(parents=True, exist_ok=True)
    ship(downloads)
    diver(downloads)
    prop(downloads, "marble_bust_01", "bust.glb", height=0.5)
    prop(downloads, "treasure_chest", "chest.glb", height=0.42)
    prop(downloads, "rock_07", "rock_07.glb", height=1.0)
    prop(downloads, "rock_09", "rock_09.glb", height=1.0)
    textures(downloads)


if __name__ == "__main__":
    main()
