#!/usr/bin/env python3
"""Writes `assets/levels/first_steps.json` — the level you play first.

    python3 tool/make_first_steps.py

**A teaching level, and the teaching is the whole design.** Every room shows a
verb somewhere it cannot hurt you, and then asks for it somewhere it can. That
order is not decoration: a player who meets a nine-metre gap having never
dashed reads it as a wall, and a player who has already dashed for a coin over
solid ground reads it as a gap.

Six rooms, in the order the verbs build on each other — walk, jump, double
jump, wall jump, dash, crouch — and then one guard to land on, because the
seventh verb is the one that needs something else in the world to exist.

**Nothing here kills.** Every pit has a floor two metres down and a stair back
up: falling costs the walk back, which is the right price for a mistake made
while learning, and the big level is where a fall costs a life. The rooms are
sized against what the runner measurably does — 1.8 m of jump, 3.13 m with
both, 7.5 m of gap, 18 m/s of dash — so a gap that is meant to need a dash is
one a double jump genuinely cannot cross.

The vocabulary lives in `levelkit.py`, shared with `make_level.py`.
"""

from levelkit import *  # noqa: F403
import levelkit

levelkit.start()

WIDE = 22.0

# The ground under everything, in two levels: the walked floor, and the one two
# metres below it that catches anybody who misses.
def room(z0, z1, *, y=0.0, material="moss", surface=None, width=WIDE):
    route([0.0, y - 0.5, (z0 + z1) / 2.0], [width, 1.0, z1 - z0], material,
          surface=surface)


def catch(z0, z1, material="stone"):
    """The floor of a pit, and the stair out of it.

    Every brush here butts against its neighbours rather than overlapping them:
    the validator warns about overlapping volumes and it is right to — two faces
    in the same plane z-fight, which looks like the level flickering.
    """
    route([0.0, -2.5, (z0 + z1) / 2.0], [WIDE, 1.0, z1 - z0], material)
    # Back up, inside the pit, so the way out is forwards. The top step's face
    # is flush with the floor it leads onto and its volume stops short of it.
    route([0.0, -1.5, z1 - 2.4], [WIDE, 1.0, 1.6], material)
    route([0.0, -0.5, z1 - 0.8], [WIDE, 1.0, 1.6], material)


def walls(z0, z1, *, height=16.0, material="stone"):
    """Sides, so a teaching level cannot be walked out of.

    Tall enough to cover the rooms that are up in the air: six metres was the
    first attempt and the autopilot climbed the chimney, walked off the top of
    the world at x = 12.5 and finished the level from outside it.
    """
    route([-WIDE / 2 - 0.5, height / 2 - 1.0, (z0 + z1) / 2.0],
          [1.0, height, z1 - z0], material)
    route([WIDE / 2 + 0.5, height / 2 - 1.0, (z0 + z1) / 2.0],
          [1.0, height, z1 - z0], material)


LENGTH = (-10.0, 108.0)
walls(*LENGTH)
route([0.0, 7.0, LENGTH[0] - 0.5], [WIDE + 2, 16.0, 1.0], "stone")
route([0.0, 7.0, LENGTH[1] + 0.5], [WIDE + 2, 16.0, 1.0], "stone")

entities.append({"type": "player_spawn", "at": [0.0, 0.0, -8.0]})

# ------------------------------------------------------------------ walking --
# Nothing to do but go forward, and three coins to make going forward the
# obvious thing. A level that opens with a decision opens with a player
# standing still.
room(-10.0, 8.0)
for i, z in enumerate((-4.0, 0.0, 4.0)):
    coin([0.0, 0.8, z], f"first coin {i + 1}")
lamp("the first lamp", [-6.0, 1.0, -2.0])
lamp("the second lamp", [6.0, 1.0, -2.0])

# ------------------------------------------------------------------ jumping --
# A gap of three metres: a single jump crosses seven, so this is a gap you
# cannot fail at, which is the point of the first one.
checkpoint("the first post", 8.0, 1, respawn=6.0)
catch(8.0, 14.0)
room(14.0, 24.0)
coin([0.0, 2.2, 11.0], "the jump coin")

# ------------------------------------------------------------------- twice ---
# A shelf at 2.6 m — over a single jump's 1.8 and under a double's 3.13 — with
# a coin on it, and then a gap of six that needs the same move to cross.
checkpoint("the second post", 22.0, 2, respawn=21.0)
route([0.0, 1.3, 26.0], [WIDE, 2.6, 4.0], "stone")
coin([0.0, 3.6, 26.0], "the high coin")
catch(28.0, 36.0)
room(36.0, 46.0)
coin([0.0, 3.0, 32.0], "the second jump coin")

# ---------------------------------------------------------------- the shaft --
checkpoint("the third post", 44.0, 3, respawn=43.0)
# The floor of the chimney, which the first version simply did not have: the
# blocks either side stand on nothing, the slot between them was a hole, and
# the runner walked into the room and fell out of the level.
room(46.0, 58.0)

# **Two metres apart**, which is a chimney rather than a room. The runner is
# 0.7 across and its wall probe reaches 0.14, so a slot much wider than this is
# one it falls down the middle of without touching either side — four metres
# was the first attempt and the autopilot sat at the bottom of it. The engine's
# own wall-jump test uses 1.8 for the same reason.
#
# Six metres tall, because a climb reaches just over seven and that is measured
# rather than guessed: at eight the autopilot got to 7.1 and stayed there,
# which is exactly what a player would have done.
route([-6.0, 3.0, 52.0], [10.0, 6.0, 10.0], "stone")
route([6.0, 3.0, 52.0], [10.0, 6.0, 10.0], "stone")
route([0.0, 3.0, 57.5], [2.0, 6.0, 1.0], "stone")
coin([0.0, 3.0, 52.0], "the shaft coin one")
coin([0.0, 5.5, 52.0], "the shaft coin two")

# The floor at the top, level with the blocks' own tops. **Not inside the
# slot**: the first version put it at the chimney's top between the walls,
# which is a lid, and the climb stopped dead against it.
route([0.0, 5.5, 64.0], [WIDE, 1.0, 12.0], "stone")
coin([0.0, 7.0, 62.0], "the ledge coin")

# ----------------------------------------------------------------- the dash --
# Nine metres, and a double jump crosses seven and a half. Shown first: a coin
# out along solid ground that a dash reaches in a moment, so the move is worth
# trying before it is needed.
checkpoint("the fourth post", 66.0, 4, respawn=66.0)
coin([0.0, 7.0, 68.0], "the dash coin")
route([0.0, 5.5, 84.0], [WIDE, 1.0, 10.0], "stone")
coin([0.0, 8.0, 74.0], "the gap coin")

# And a shallow floor under the gap, with a stair up to the far side: a miss
# costs a few seconds, not a walk back to the start.
route([0.0, 4.0, 74.5], [WIDE, 1.0, 9.0], "stone")
route([0.0, 4.875, 77.0], [WIDE, 0.75, 2.0], "stone")
route([0.0, 5.625, 78.5], [WIDE, 0.75, 1.0], "stone")

# ---------------------------------------------------------------- crouching --
# A metre of headroom, over a floor that carries on: the slab is thick enough
# that jumping at it is obviously not the answer.
checkpoint("the fifth post", 88.0, 5, respawn=88.0)
route([0.0, 9.0, 94.0], [WIDE, 5.0, 8.0], "stone")
route([0.0, 5.5, 96.0], [WIDE, 1.0, 14.0], "stone")
coin([0.0, 6.8, 94.0], "the crawl coin")

# ----------------------------------------------------------------- the guard -
# One thing that walks, on a route across the way out, with the exit behind it.
enemy("the guard", [-6.0, 6.0, 101.0], [[6.0, 6.0, 101.0]], speed=0.3)
coin([0.0, 6.8, 101.0], "the guard's coin")

entities.append({
    "type": "exit",
    "name": "the way on",
    "at": [0.0, 7.5, 104.0],
    "size": [5.0, 3.0, 3.0],
    "text": "First steps.",
})

LIGHTS = [
    SUN,
    {"at": [0.0, 6.0, 0.0], "color": [1.0, 0.94, 0.8], "intensity": 24.0, "range": 30.0},
    {"at": [0.0, 6.0, 30.0], "color": [1.0, 0.94, 0.8], "intensity": 24.0, "range": 32.0},
    {"at": [0.0, 9.0, 56.0], "color": [0.85, 0.92, 1.0], "intensity": 26.0, "range": 34.0},
    {"at": [0.0, 11.0, 76.0], "color": [1.0, 0.9, 0.7], "intensity": 26.0, "range": 36.0},
    {"at": [0.0, 11.0, 100.0], "color": [0.9, 1.0, 0.9], "intensity": 26.0, "range": 34.0},
]

levelkit.write(
    "first_steps.json",
    name="First Steps",
    lights=LIGHTS,
    # Where the game goes when this is finished. `Level.next` has been read into
    # `PlatformerSimulation.levelNext` since the package was written and passed
    # through unused, because there was nowhere to go.
    next_level="assets/levels/ascent.json",
    tool="tool/make_first_steps.py",
)
