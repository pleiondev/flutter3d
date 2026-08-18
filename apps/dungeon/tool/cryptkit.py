#!/usr/bin/env python3
"""The pieces this game's levels are built out of.

The platformer has `levelkit.py`, and this is its opposite number rather than a
copy of it. What differs is the vocabulary, and the vocabulary differs because
the shape of the game does: a platformer level is a **route** — a chain of
places to land, with air between them — and a crypt is a **plan**, rooms with
walls between them and doors in the walls.

So there is no `slope`, no `coin` and no `spring` here, and there is a `room`,
which the platformer has no use for at all. What the two share is the formatter,
and that lives at the repository root in `tool/leveldoc.py`.

**Walls are built, not drawn.** A room is six brushes with holes cut in them by
the doorways it is given, because a wall with a hole in it is four brushes and
getting those four right by hand is where hand-authored levels go wrong. Ask for
a room and its openings; the arithmetic is here.

Nothing holds state between documents: `start()` resets everything, and each
script calls it before it builds.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "tool"))
from leveldoc import dump, rounded  # noqa: E402

LEVELS = Path(__file__).resolve().parent.parent / "assets" / "levels"

brushes: list[dict] = []
entities: list[dict] = []
lights: list[dict] = []

#: How thick a wall, a floor and a ceiling are. One number, because a crypt
#: whose walls vary in thickness reads as a crypt somebody built twice.
THICK = 1.0

#: Where the ceiling goes when a room does not say. Head height plus enough that
#: a torch on the wall is not in your eye.
HEIGHT = 4.0


def start():
    brushes.clear()
    entities.clear()
    lights.clear()


# ── Architecture ────────────────────────────────────────────────────────────


def _box(at, size, material, casts=True):
    row = {"at": rounded(at), "size": rounded(size), "material": material}
    # A fence is not architecture: omitted when true, so the documents do not
    # grow a line per brush saying the obvious.
    if not casts:
        row["castsShadow"] = False
    brushes.append(row)
    return row


def _wall_with_holes(fixed, axis, span, base, height, holes, material):
    """One wall, in up to four pieces, with [holes] cut out of it.

    [holes] are (centre, width, sill, top) along the wall's own axis. A doorway
    is a hole from the floor up; a window is one that starts above head height.
    The pieces are: below each hole, above it, and the runs of solid wall
    between them.
    """
    holes = sorted(holes, key=lambda h: h[0] - h[1] / 2.0)
    cursor = span[0]
    for centre, width, sill, top in holes:
        left = centre - width / 2.0
        right = centre + width / 2.0
        if left > cursor:
            _piece(fixed, axis, cursor, left, base, base + height, material)
        if sill > base:
            _piece(fixed, axis, left, right, base, sill, material)
        if top < base + height:
            _piece(fixed, axis, left, right, top, base + height, material)
        cursor = right
    if cursor < span[1]:
        _piece(fixed, axis, cursor, span[1], base, base + height, material)


def _piece(fixed, axis, low, high, bottom, top, material):
    if high - low < 1e-6 or top - bottom < 1e-6:
        return
    along = (low + high) / 2.0
    thick = THICK
    if axis == "x":
        _box((along, (bottom + top) / 2.0, fixed),
             (high - low, top - bottom, thick), material)
    else:
        _box((fixed, (bottom + top) / 2.0, along),
             (thick, top - bottom, high - low), material)


def room(centre, size, *, height=HEIGHT, floor="floor", wall="wall",
         ceiling="ceiling", doors=(), ceilinged=True):
    """A room: floor, ceiling, and four walls with [doors] cut through them.

    [centre] is the middle of the floor and [size] is the inside, so two rooms
    whose centres are `size` apart share a wall rather than overlapping. Each
    door is `(side, offset, width, height)` where side is `north`, `south`,
    `east` or `west` and offset is along that wall from its middle.

    Sides are named by the axis, not by any compass in the fiction: **north is
    −Z**, which is the direction the camera faces at yaw zero, so "the door on
    the north wall" is the one ahead of you when you walk in facing forward.
    """
    cx, _, cz = centre
    w, _, d = size
    x0, x1 = cx - w / 2.0, cx + w / 2.0
    z0, z1 = cz - d / 2.0, cz + d / 2.0

    _box((cx, -THICK / 2.0, cz), (w + THICK * 2, THICK, d + THICK * 2), floor)
    if ceilinged:
        _box((cx, height + THICK / 2.0, cz),
             (w + THICK * 2, THICK, d + THICK * 2), ceiling)

    holes = {"north": [], "south": [], "east": [], "west": []}
    for side, offset, width, door_height in doors:
        if side not in holes:
            raise SystemExit(f"a room has a door on its {side!r} side")
        along = (cx if side in ("north", "south") else cz) + offset
        holes[side].append((along, width, 0.0, door_height))

    _wall_with_holes(z0 - THICK / 2.0, "x", (x0 - THICK, x1 + THICK), 0.0,
                     height, holes["north"], wall)
    _wall_with_holes(z1 + THICK / 2.0, "x", (x0 - THICK, x1 + THICK), 0.0,
                     height, holes["south"], wall)
    _wall_with_holes(x1 + THICK / 2.0, "z", (z0, z1), 0.0,
                     height, holes["east"], wall)
    _wall_with_holes(x0 - THICK / 2.0, "z", (z0, z1), 0.0,
                     height, holes["west"], wall)


def corridor(frm, to, *, width=3.0, height=3.0, floor="floor", wall="wall",
             ceiling="ceiling", doors=()):
    """A passage between two points, along one axis.

    Refuses a diagonal rather than building a staircase of boxes: a corridor
    that is not axis-aligned is either two corridors or a mistake, and both are
    better said by the caller.
    """
    (x0, _, z0), (x1, _, z1) = frm, to
    if abs(x0 - x1) > 1e-6 and abs(z0 - z1) > 1e-6:
        raise SystemExit(f"a corridor from {frm} to {to} is not straight")
    if abs(x0 - x1) > 1e-6:
        room(((x0 + x1) / 2.0, 0.0, z0), (abs(x1 - x0), 0.0, width),
             height=height, floor=floor, wall=wall, ceiling=ceiling,
             doors=doors)
    else:
        room((x0, 0.0, (z0 + z1) / 2.0), (width, 0.0, abs(z1 - z0)),
             height=height, floor=floor, wall=wall, ceiling=ceiling,
             doors=doors)


def pillar(at, *, size=(1.2, HEIGHT, 1.2), material="stone"):
    _box(at, size, material)


def stair(frm, to, *, width=3.0, steps=8, material="stone"):
    """A flight, as steps rather than a ramp.

    Boxes because this game's bodies climb: `CharacterController` steps up
    anything under its step height, and a stack of boxes is what that was
    written for. A ramp would need the collision wedge the platformer uses, and
    a crypt has no use for one anywhere else.
    """
    (x0, y0, z0), (x1, y1, z1) = frm, to
    for i in range(steps):
        t = (i + 1) / steps
        y = y0 + (y1 - y0) * t
        x = x0 + (x1 - x0) * t
        z = z0 + (z1 - z0) * t
        along_x = abs(x1 - x0) > abs(z1 - z0)
        run = (abs(x1 - x0) if along_x else abs(z1 - z0)) / steps
        _box((x, y / 2.0, z),
             (run if along_x else width, max(y, 0.1), width if along_x else run),
             material)


# ── Light ───────────────────────────────────────────────────────────────────


def torch(at, *, name, yaw=0.0, colour=(1.0, 0.68, 0.34), intensity=6.5,
          rng=13.0, shadow=True):
    """A torch on a wall, and the light it drives.

    One call rather than two, because the light and the fixture are the same
    thing said twice and a level where they disagree is a torch lighting the
    room next door. The fixture drives the light by name — see `LightFixture` —
    so the name is what ties them, and generating both here means it cannot be
    mistyped in one of them.
    """
    lights.append({
        "type": "point",
        "at": rounded(at),
        "color": list(colour),
        "intensity": intensity,
        "range": rng,
        "castsShadow": shadow,
        "name": name,
    })
    entities.append({
        "type": "torch",
        "at": rounded(_offset(at, yaw, 0.35)),
        "yaw": round(yaw, 4),
        "light": name,
    })


def lamp(at, *, name, colour=(1.0, 0.78, 0.42), intensity=5.0, rng=11.0):
    lights.append({
        "type": "point",
        "at": rounded(at),
        "color": list(colour),
        "intensity": intensity,
        "range": rng,
        "castsShadow": True,
        "name": name,
    })
    entities.append({"type": "lamp", "at": rounded(at), "light": name,
                     "color": list(colour)})


def _offset(at, yaw, distance):
    """A step along [yaw] from [at]. Yaw zero faces −Z."""
    import math
    return (at[0] - math.sin(yaw) * distance, at[1],
            at[2] - math.cos(yaw) * distance)


# ── What is in the rooms ────────────────────────────────────────────────────


def spawn(at, *, yaw=0.0):
    entities.append(
        {"type": "player_spawn", "at": rounded(at), "yaw": round(yaw, 4)})


def monster(kind, at):
    entities.append({"type": "monster", "at": rounded(at), "kind": kind})


def pickup(gives, at, *, amount=None, ammo=None):
    row = {"type": "pickup", "at": rounded(at), "gives": gives}
    if amount is not None:
        row["amount"] = amount
    if ammo is not None:
        row["ammo"] = ammo
    entities.append(row)


def door(name, at, *, key=None, size=(4.0, 5.0, 1.0), travel=(0.0, 4.4, 0.0),
         speed=2.2, wait=4.0, material="iron"):
    row = {
        "type": "door", "at": rounded(at), "name": name,
        "size": rounded(size), "travel": rounded(travel),
        "speed": speed, "wait": wait, "material": material,
    }
    if key:
        row["key"] = key
    entities.append(row)


def key(colour, at, *, name=None):
    entities.append({
        "type": "key", "at": rounded(at), "color": colour,
        "name": name or f"{colour}_key",
        "model": "assets/models/key.glb", "material": "keymetal",
        "size": [0.7, 0.7, 0.7], "tint": [0.95, 0.6, 0.2],
    })


def lift(name, at, *, size=(2.6, 0.5, 3.0), travel=(0.0, 3.0, 0.0), speed=1.5,
         wait=5.0, material="iron"):
    entities.append({
        "type": "lift", "at": rounded(at), "size": rounded(size),
        "travel": rounded(travel), "speed": speed, "wait": wait,
        "name": name, "material": material,
    })


def platform(name, at, *, size=(3.0, 0.4, 3.0), travel=(0.0, 0.0, -4.0),
             speed=1.1, wait=2.0, material="stone"):
    """A slab that goes back and forth on its own, with nothing to switch it."""
    entities.append({
        "type": "platform", "at": rounded(at), "size": rounded(size),
        "travel": rounded(travel), "speed": speed, "wait": wait,
        "name": name, "material": material,
    })


def button(target, at, *, size=(0.25, 0.7, 0.7)):
    entities.append({"type": "button", "at": rounded(at),
                     "size": rounded(size), "target": target})


def trigger(target, at, *, size=(4.0, 3.0, 2.0), once=False):
    entities.append({"type": "trigger", "at": rounded(at),
                     "size": rounded(size), "target": target, "once": once})


def note(at, text, *, yaw=0.0):
    entities.append({"type": "note", "at": rounded(at),
                     "yaw": round(yaw, 4), "text": text})


def exit_at(name, at):
    entities.append({"type": "exit", "at": rounded(at), "name": name})


# ── Writing it down ─────────────────────────────────────────────────────────

def _textured(name, *, base, roughness, texels, image=None):
    """A material with the crypt's three maps on it.

    The numbers are the ones the hand-authored crypt shipped with rather than a
    fresh guess: they were chosen against the textures by eye, and a generator
    that quietly re-lit the level while claiming to rebuild it would be a
    generator nobody could trust with the second one.
    """
    file = image or name
    return {
        "baseColor": list(base),
        "roughness": roughness,
        "texelsPerMetre": texels,
        "albedo": f"assets/textures/{file}_albedo.jpg",
        "normal": f"assets/textures/{file}_normal.png",
        "orm": f"assets/textures/{file}_orm.png",
    }


MATERIALS = {
    "floor": _textured("floor", base=(0.62, 0.6, 0.56, 1.0), roughness=0.9,
                       texels=0.5),
    "wall": _textured("wall", base=(0.7, 0.66, 0.6, 1.0), roughness=0.85,
                      texels=0.4),
    "ceiling": _textured("ceiling", base=(0.34, 0.32, 0.3, 1.0),
                         roughness=0.95, texels=0.35),
    "stone": _textured("stone", base=(0.68, 0.65, 0.6, 1.0), roughness=0.8,
                       texels=0.7),
    "iron": _textured("iron", base=(0.72, 0.7, 0.68, 1.0), roughness=0.6,
                      texels=1.2, image="metal"),
    # No maps: a key is a small bright thing and a metal texture on it at this
    # size is noise.
    "keymetal": {
        "baseColor": [0.92, 0.72, 0.26, 1.0],
        "roughness": 0.35,
        "metallic": 0.9,
    },
}


#: Things a player is meant to reach. One inside a wall is a key nobody can
#: take, and it looks perfectly fine in the document — which is why this is
#: checked rather than reviewed. The platformer's generator learned this the
#: expensive way: fourteen coins and a crate were inside the geometry of its two
#: shipped levels, all hand-authored, none caught by anything.
REACHABLE = ("pickup", "key")


def _buried():
    """Every reachable entity whose middle is inside a solid brush."""
    walled_in = []
    for row in entities:
        if row["type"] not in REACHABLE:
            continue
        x, y, z = row["at"]
        for brush in brushes:
            bx, by, bz = brush["at"]
            sx, sy, sz = brush["size"]
            if (abs(x - bx) < sx / 2.0 and abs(y - by) < sy / 2.0
                    and abs(z - bz) < sz / 2.0):
                walled_in.append(
                    f"  {row['type']} at {row['at']} is inside a "
                    f"{brush['material']} brush at {brush['at']}")
                break
    return walled_in


def write(filename, *, name, fog=(0.034, 0.034, 0.034), density=0.035,
          next_level=None, tool):
    """Writes the document and says what went into it."""
    walled_in = _buried()
    if walled_in:
        raise SystemExit(
            f"{len(walled_in)} things a player is meant to reach are inside "
            "solid brushes:\n" + "\n".join(walled_in))
    if not any(row["type"] == "player_spawn" for row in entities):
        raise SystemExit(f"{filename} has nowhere for the player to start")

    document = {
        "version": 1,
        "name": name,
        "generatedBy": tool,
        "fogColor": list(fog),
        "fogDensity": density,
        "materials": MATERIALS,
        "brushes": brushes,
        "lights": lights,
        "entities": entities,
    }
    if next_level:
        document["next"] = next_level

    out = LEVELS / filename
    out.write_text(dump(document, 0) + "\n")
    counts = {}
    for row in entities:
        counts[row["type"]] = counts.get(row["type"], 0) + 1
    print(f"{out.name}: {len(brushes)} brushes, {len(lights)} lights, "
          f"{len(entities)} entities "
          f"({', '.join(f'{v} {k}' for k, v in sorted(counts.items()))})")
