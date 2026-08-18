#!/usr/bin/env python3
"""The pieces both of this game's levels are built out of.

Two documents now — `make_first_steps.py` and `make_level.py` — and the moment
there were two, every helper in the second was something the first wanted. What
lives here is the vocabulary: a brush, a coin, a crate, a mover, a route guard
and the writer. What lives in each script is the *arrangement*, which is the
part worth reading.

Nothing here holds state between levels: `start()` resets the lists, and each
script calls it before it builds anything.
"""

import json
import sys
from pathlib import Path

# The shared writer, at the repository root: `dump` and `rounded` had a second
# consumer the day `apps/dungeon/tool/cryptkit.py` was written.
sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "tool"))
from leveldoc import dump, rounded  # noqa: E402

LEVELS = Path(__file__).resolve().parent.parent / "assets" / "levels"
COIN = "assets/models/coin.glb"

brushes: list[dict] = []
entities: list[dict] = []
fill_entities: list[dict] = []
keep_clear: list[tuple] = []
_coins = 0
_crates = 0


def start(clear=()):
    """Begins a document. `clear` is the ground the filling may not stand on."""
    global _coins, _crates
    brushes.clear()
    entities.clear()
    fill_entities.clear()
    keep_clear.clear()
    keep_clear.extend(clear)
    _coins = 0
    _crates = 0


def route(at, size, material, surface=None, casts=True, ramp=None):
    row = {"at": _r(at), "size": _r(size), "material": material}
    if surface:
        row["surface"] = surface
    # A fence is not architecture: see `Brush.castsShadow`. Omitted when true so
    # the documents do not grow a line per brush saying the obvious.
    if not casts:
        row["castsShadow"] = False
    if ramp:
        _check_ramp(ramp)
        row["ramp"] = ramp
    brushes.append(row)


# Which way a ramp climbs, in the words the level format uses.
RAMPS = ("+x", "-x", "+z", "-z")


def _check_ramp(ramp):
    """A typo here is a block where a slope was meant, and the reader would
    refuse the document — but it refuses it at load, in front of a player, and
    a generator that can say so at generate time should."""
    if ramp not in RAMPS:
        raise SystemExit(f"ramp {ramp!r} is not one of {', '.join(RAMPS)}")


def slope(at, size, material, uphill, surface=None):
    """A brush with a corner cut off, climbing towards `uphill`.

    There is no angle: the cut runs corner to corner, so the steepness is the
    size — `[8, 2, 8]` climbing `+z` is fourteen degrees, and it is read off
    the numbers rather than kept in agreement with a second one.
    """
    _check_ramp(uphill)
    row = {"at": _r(at), "size": _r(size), "material": material, "ramp": uphill}
    if surface:
        row["surface"] = surface
    brushes.append(row)


def fill(at, size, material, surface=None):
    x0, x1 = at[0] - size[0] / 2, at[0] + size[0] / 2
    z0, z1 = at[2] - size[2] / 2, at[2] + size[2] / 2
    for cx0, cx1, cz0, cz1 in keep_clear:
        if x0 < cx1 and x1 > cx0 and z0 < cz1 and z1 > cz0:
            raise SystemExit(f"filling at {at} size {size} sits on the route")
    row = {"at": _r(at), "size": _r(size), "material": material}
    if surface:
        row["surface"] = surface
    brushes.append(row)


def _r(v):
    return rounded(v)


def coin(at, name=None):
    """A coin, on the route if it is named and in the filling if it is not."""
    global _coins
    _coins += 1
    row = {
        "type": "collectible",
        "name": name or f"coin {_coins:03d}",
        "at": _r(at),
        "what": "coin",
        "model": COIN,
    }
    (entities if name else fill_entities).append(row)


def crate(at, name=None, size=1.4, mass=30.0):
    global _crates
    _crates += 1
    row = {
        "type": "crate",
        "name": name or f"crate {_crates:02d}",
        "at": _r(at),
        "size": [size, size, size],
        "mass": mass,
        "material": "wood",
    }
    (entities if name else fill_entities).append(row)


def spring(name, at, speed=15.0, size=2.6):
    entities.append({
        "type": "spring", "name": name, "at": _r(at),
        "size": [size, 0.4, size], "speed": speed, "material": "brass",
    })


def checkpoint(name, z, order, respawn=None):
    entities.append({
        "type": "checkpoint", "name": name, "at": _r([0.0, 1.0, z]),
        "order": order, "respawn": _r([0.0, 0.0, respawn if respawn is not None else z]),
        "size": [24.0, 3.0, 1.0],
    })


def hazard(name, at, size, damage=None, instant=False):
    row = {"type": "hazard", "name": name, "at": _r(at), "size": _r(size)}
    if instant:
        row["instant"] = True
    else:
        row["damage"] = damage if damage is not None else 45.0
    entities.append(row)


def mover(kind, name, at, size, travel, speed, wait, phase=None):
    row = {
        "type": kind, "name": name, "at": _r(at), "size": _r(size),
        "travel": _r(travel), "speed": speed, "wait": wait, "material": "brass",
    }
    if phase is not None:
        row["phase"] = phase
    entities.append(row)


def oneway(name, at, size=(5.0, 0.3, 5.0)):
    """A platform you jump up through and land on top of."""
    entities.append({
        "type": "oneway", "name": name, "at": _r(at), "size": _r(size),
        "material": "wood",
    })


def conveyor(name, at, flow, size=(5.0, 0.4, 12.0)):
    """A floor that carries whoever stands on it. The belt does not move."""
    entities.append({
        "type": "conveyor", "name": name, "at": _r(at), "size": _r(size),
        "flow": _r(flow), "material": "brass",
    })


def crumbling(name, at, size=(3.5, 0.4, 3.5), delay=0.45, gone=2.5):
    entities.append({
        "type": "crumbling", "name": name, "at": _r(at), "size": _r(size),
        "delay": delay, "gone": gone, "material": "wood",
    })


def breakable(name, at, size=(2.0, 2.0, 2.0)):
    entities.append({
        "type": "breakable", "name": name, "at": _r(at), "size": _r(size),
        "material": "stone",
    })


def climbable(name, at, size=(1.2, 8.0, 1.2), swing=0.0, period=2.4, phase=0.0):
    """A ladder, or — with a swing on it — a rope."""
    row = {
        "type": "climbable", "name": name, "at": _r(at), "size": _r(size),
        "material": "wood",
    }
    if swing:
        row.update({"swing": swing, "period": period, "phase": phase,
                    "material": "brass"})
    entities.append(row)


def enemy(name, at, route, kind="patrol", speed=0.55, size=(0.7, 0.7, 0.7)):
    """Something that walks a route and hurts on contact."""
    entities.append({
        "type": "enemy", "name": name, "at": _r(at), "size": _r(size),
        "kind": kind, "speed": speed, "material": "brass",
        "route": [_r(point) for point in route],
    })


def lamp(name, at, size=(0.4, 1.6, 0.4)):
    """Something to see by, and something to see."""
    entities.append({
        "type": "lamp", "name": name, "at": _r(at), "size": _r(size),
        "material": "brass",
    })


def plate(name, target, at, size=(4.0, 2.0, 4.0)):
    """A volume that works a mechanism by being walked into.

    How a platformer opens a door. Nothing in this genre presses a use key —
    there is no such action and there should not be — so a gate with no plate in
    front of it is a gate that never opens, whatever key the player is holding.
    """
    entities.append({
        "type": "trigger", "name": name, "at": _r(at), "size": _r(size),
        "target": target, "once": False,
    })


def pillar(x, z, height, width=2.4, material="stone", top_coin=True):
    fill([x, height / 2, z], [width, height, width], material)
    if top_coin:
        coin([x, height + 0.8, z])


def hut(x, z, height, width=7.0, material="stone", top_coin=True):
    fill([x, height / 2, z], [width, height, width], material)
    if top_coin:
        coin([x, height + 0.8, z])


def plank(x, z, along_x, length, y, material="wood"):
    size = [length, 0.3, 2.0] if along_x else [2.0, 0.3, length]
    fill([x, y, z], size, material)


def ziggurat(x, z, levels, step_h, base, material="stone"):
    """A stepped block, coins on every terrace. Steps are climbable by design."""
    for i in range(levels):
        side = base - i * (base / (levels + 1))
        top = (i + 1) * step_h
        fill([x, top / 2, z], [side, top, side], material)
        coin([x + side / 2 - 1.0, top + 0.8, z])
        coin([x - side / 2 + 1.0, top + 0.8, z])




MATERIALS = {
    name: {
        "roughness": 1.0,
        "albedo": f"assets/textures/{name}_albedo.png",
        "normal": f"assets/textures/{name}_normal.png",
        "orm": f"assets/textures/{name}_orm.png",
        "texelsPerMetre": texels,
    }
    for name, texels in (
        ("moss", 0.5), ("stone", 0.5), ("brass", 1.0), ("wood", 0.7), ("ice", 0.4)
    )
}
MATERIALS["brass"]["metallic"] = 1.0

SUN = {
    # Steep-ish, and it can afford to be: the renderer has cascades, so the near
    # shadow map is four centimetres a texel rather than fourteen.
    "type": "directional",
    "direction": [-0.35, -0.85, 0.4],
    "color": [1.0, 0.96, 0.88],
    "intensity": 2.6,
    "castsShadow": True,
}




# Things a player is meant to reach. A brush through one of these is a coin
# nobody can take and a crate nobody can push, and it looks perfectly fine in
# the document — which is why this is checked rather than reviewed.
REACHABLE = ("collectible", "crate", "key")


def _buried():
    """Every reachable entity whose middle is inside a solid brush.

    **The founding bug of this project, still live when it was measured.**
    Fourteen coins and a crate sat inside the geometry of the two shipped
    levels — including three in a crawlspace and a crate at the foot of the
    chimney, all authored by hand, all invisible in the JSON, and none of them
    caught by anything. The validator did not look, the autopilot walked past
    them, and a coin you cannot take looks exactly like a coin you have not
    taken yet.

    The centre rather than the whole box, deliberately: a coin whose edge grazes
    a wall is fine and common, and a check that fails on that is a check people
    switch off. A centre inside solid is never right.
    """
    def _solid_at(b, at):
        """Whether a point inside this brush's box is inside the brush itself.

        **A ramp's box is half empty**, and that half is exactly where a coin
        wants to hang: above the slope, in the air over the thin end. Answering
        from the box would bury every one of them and teach the author to stop
        believing this check — which is worse than not having it.
        """
        ramp = b.get("ramp")
        if not ramp:
            return True
        c, s = b["at"], b["size"]
        axis = 0 if ramp[1] == "x" else 2
        sign = 1.0 if ramp[0] == "+" else -1.0
        # How far up the climb the point is, from nought at the thin end to one
        # at the tall one, and the surface's height there.
        along = (sign * (at[axis] - c[axis]) / (s[axis] / 2) + 1.0) / 2.0
        return at[1] < c[1] - s[1] / 2 + s[1] * along

    out = []
    for e in entities + fill_entities:
        if e.get("type") not in REACHABLE:
            continue
        at = e.get("at")
        if not at:
            continue
        for b in brushes:
            c, s = b["at"], b["size"]
            if all(c[i] - s[i] / 2 + 0.01 < at[i] < c[i] + s[i] / 2 - 0.01
                   for i in range(3)) and _solid_at(b, at):
                # The brush is named too. Working out *which* one buried a coin
                # by reading coordinates is the slow half of fixing it.
                out.append(f'  {e.get("name") or e["type"]} at {at} '
                           f'is inside the {b["material"]} at {c} size {s}')
                break
    return out


def write(filename, *, name, lights, fog=(0.05, 0.07, 0.12), density=0.004,
          next_level=None, tool=None):
    """Writes the document and says what went into it."""
    walled_in = _buried()
    if walled_in:
        raise SystemExit(
            f"{len(walled_in)} things a player is meant to reach are inside "
            "solid brushes:\n" + "\n".join(walled_in))

    document = {
        "version": 1,
        "name": name,
        "generatedBy": tool or "tool/levelkit.py",
        "fogColor": list(fog),
        "fogDensity": density,
        "materials": MATERIALS,
        "brushes": brushes,
        "lights": lights,
        "entities": entities + fill_entities,
    }
    if next_level:
        document["next"] = next_level

    out = LEVELS / filename
    out.write_text(dump(document, 0) + "\n")
    print(f"{out.name}: {len(brushes)} brushes, "
          f"{len(entities) + len(fill_entities)} entities, {_coins} coins, "
          f"{_crates} crates")
