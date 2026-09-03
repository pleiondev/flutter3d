#!/usr/bin/env python3
"""Writes `assets/levels/spire.json` — the fifth level, and the last one.

    python3 tool/make_spire.py

**Ten flights over a drop, and something on them that follows.** Every level
before this one is a floor with obstacles standing on it; this one is eleven
towers with nothing between them, and the nothing is what the level is made of.
Miss a jump and there is no ground to land on — the shaft is a hazard the whole
way down — so the checkpoints are the landings, and a flight is the distance
between two mistakes.

**The enemies are `hunter`s, and this is the level they were built for.** A
patrol walks its own posts and a leaper jumps the gaps in them; neither can
leave the platform it was put on. A hunter asks the level's navigation for the
way to where the player *is* and takes the jump links to get there, which on a
floor is a nuisance and on a staircase over a drop is the whole idea. They see
eight metres and forget you a second and a half after they stop seeing you: a
runner who keeps going is a runner who gets away, and one who stops to think
about a jump has company while thinking.

Nothing here is a new verb. Walk, jump, double jump — the same three the
tutorial opened with, at heights where getting them wrong costs the climb. What
the last level asks for is the first thing done well.

Held to the measured runner: 6 m/s, a jump of 1.8 m, 3.13 with both, about
7.5 m of gap. **Every rise is 1.8 and every gap is at most four**, and both of
those numbers are smaller than they look like they should be. The measured
7.5 m is a jump across the flat; a jump that also climbs nearly two metres is a
much shorter one, and the first draft of this stair used gaps of five and six —
which the autopilot cleared some of the time. A jump that works some of the time
is one a player misses over a hazard that kills, and a level whose difficulty is
whether the jump came off is a level with no difficulty in it at all. What is
hard here is the drop underneath and the thing following you, both of which stay
hard however good the player's timing is.

The vocabulary lives in `levelkit.py`; this file is the arrangement.
"""

from levelkit import *  # noqa: F403
import levelkit

W = 36.0
LENGTH = (-12.0, 154.0)

# How deep the shaft under the flights goes, and how high the walls stand. The
# towers are drawn down to the first of these so they read as columns rather
# than as slabs hanging in the air.
FLOOR = -9.0
TOP = 33.0

# The stair, written out one by one: every flight is a place a player stands and
# a place a jump is measured from, so none of them is generated.
#
#   z, depth, top, x, width
FLIGHTS = (
    (22.0, 8.0, 1.8, 0.0, 18.0),
    (33.0, 8.0, 3.6, -3.0, 16.0),
    (45.0, 8.0, 5.4, 3.0, 16.0),
    (56.5, 9.0, 7.2, 0.0, 18.0),
    (68.0, 8.0, 9.0, -3.0, 16.0),
    (80.0, 8.0, 10.8, 3.0, 16.0),
    (91.5, 9.0, 12.6, 0.0, 18.0),
    (103.0, 8.0, 14.4, -3.0, 16.0),
    (115.0, 8.0, 16.2, 3.0, 16.0),
    (126.5, 9.0, 18.0, 0.0, 20.0),
)

# The shelf the key is on: it stands *against* the first landing rather than out
# in the air beside it, and a metre and two tenths higher, so getting on it is a
# step up and getting off it is a step down.
#
# **The first version left two metres of shaft between the two**, which is a gap
# a runner walking sideways off a landing falls into: a jump of two metres at a
# walk of six drops half a metre in the crossing, and the shelf's face is where
# that half metre puts you. A detour off the route should cost a detour, not a
# life.
SPUR = (56.5, 9.0, 8.4, -13.5, 9.0)
SUMMIT = (140.0, 12.0, 19.0, 0.0, 24.0)

# Ground the filling may not stand on: the floor of the base, every flight, the
# spur the key is on, and the summit.
KEEP_CLEAR = [(-6.0, 6.0, LENGTH[0], 18.0)] + [
    (x - width / 2.0, x + width / 2.0, z - depth / 2.0, z + depth / 2.0)
    for z, depth, top, x, width in FLIGHTS + (SPUR, SUMMIT)
]

levelkit.start(KEEP_CLEAR)


def tower(z, depth, top, x, width, material="stone"):
    """A flight of the stair: a column out of the dark with a floor on it."""
    route([x, (top + FLOOR) / 2.0, z], [width, top - FLOOR, depth], material)


# The shaft the whole climb stands in. Four and forty metres of wall, because a
# level that is a tower is a level whose sides are the thing keeping a player in
# it — and no shadow, for the reason `first_steps` gives on `walls()`.
for x in (-W / 2 - 0.5, W / 2 + 0.5):
    route([x, (FLOOR + TOP) / 2.0, (LENGTH[0] + LENGTH[1]) / 2.0],
          [1.0, TOP - FLOOR, LENGTH[1] - LENGTH[0]], "stone", casts=False)
for z in (LENGTH[0] - 0.5, LENGTH[1] + 0.5):
    route([0.0, (FLOOR + TOP) / 2.0, z],
          [W + 2.0, TOP - FLOOR, 1.0], "stone", casts=False)

# ------------------------------------------------------------------- the foot
route([0.0, -0.5, (LENGTH[0] + 18.0) / 2.0], [W, 1.0, 18.0 - LENGTH[0]],
      "stone")
spawn([0.0, 0.0, -8.0])
for i, (x, z) in enumerate(((0.0, -4.0), (-4.0, 0.0), (4.0, 0.0),
                            (0.0, 6.0))):
    coin([x, 0.8, z], f"the foot coin {i + 1}")
lamp("the foot lamp west", [-8.0, 1.0, -6.0])
lamp("the foot lamp east", [8.0, 1.0, -6.0])
checkpoint("the foot", -2.0, 1, respawn=-4.0)
for x in (-14.0, 14.0):
    hut(x, 2.0, 3.0, width=6.0)
    crate([x, 0.0, 10.0])

# ------------------------------------------------------------------ the shaft
# **The whole of the difficulty, and it is one entity.** Everything below the
# flights is fatal, so a missed jump is a death rather than a fall — which is
# what makes the landings worth their checkpoints and what a hazard means when
# it is `instant` rather than a large number. See `Hazard.instant`.
hazard("the shaft", [0.0, FLOOR / 2.0, (18.0 + 134.0) / 2.0],
       [W, -FLOOR, 134.0 - 18.0], instant=True)

# ----------------------------------------------------------------- the flights
for i, (z, depth, top, x, width) in enumerate(FLIGHTS):
    tower(z, depth, top, x, width)
    coin([x, top + 0.8, z], f"flight coin {i + 1}")
    # A ledge on the open side, half a metre away and a metre down: the flights
    # sit off centre by threes, and the room that leaves is the only place in
    # this level a coin can be that is not on the way up.
    away = 1.0 if x <= 0.0 else -1.0
    ledge = x + away * (width / 2.0 + 2.5)
    fill([ledge, top - 1.5, z], [4.0, 1.0, depth - 2.0], "stone")
    coin([ledge, top - 0.2, z], f"ledge coin {i + 1}")
    for dz in (-depth / 4.0, depth / 4.0):
        coin([x + away * 4.0, top + 0.8, z + dz])

checkpoint("the second flight", 33.0, 2, respawn=33.0, y=3.6, x=-3.0)
checkpoint("the first landing", 56.5, 3, respawn=56.5, y=7.2)
checkpoint("the high landing", 91.5, 4, respawn=91.5, y=12.6)
checkpoint("the crown", 124.0, 5, respawn=125.0, y=18.0)

# ------------------------------------------------------------------- the spur
# The key, a step up off the first landing's western side, with nothing under
# either of them.
tower(*SPUR)
key("the slate key", [SPUR[3], SPUR[2] + 1.0, SPUR[0]], "slate")
lamp("the key lamp", [SPUR[3], SPUR[2] + 1.0, SPUR[0] - 3.0])
for dz in (-2.5, 2.5):
    coin([SPUR[3], SPUR[2] + 0.8, SPUR[0] + dz])

# ---------------------------------------------------------------- the hunters
# Four of them, on the flights rather than the landings: a landing is where a
# player stops, and something waiting exactly where the game told you to rest is
# the cheap version of this. Eight metres of sight and a second and a half of
# memory — a runner who keeps moving outruns one, which is the difference
# between a level that is hard and a level that is unfair.
for i, (name, at) in enumerate((
    ("the first watcher", [8.0, 5.4, 45.0]),
    ("the second watcher", [8.0, 10.8, 80.0]),
    ("the third watcher", [-8.0, 14.4, 103.0]),
    ("the crown's watcher", [7.0, 18.0, 128.0]),
)):
    enemy(name, at, kind="hunter", sight=8.0, patience=1.5)

# And two that only walk, for the contrast: on the landings, slowly, where they
# can be gone round.
enemy("the first warden", [-7.0, 7.2, 59.0], [[7.0, 7.2, 59.0]], speed=0.35)
enemy("the second warden", [-7.0, 12.6, 94.0], [[7.0, 12.6, 94.0]],
      speed=0.4)

# ----------------------------------------------------------------- the summit
tower(*SUMMIT)
checkpoint("the threshold", 136.0, 6, respawn=136.0, y=SUMMIT[2])

# The slate gate, and its plate in front of it. Eight metres of wall on a
# platform twenty-four across, against a double jump of 3.13: the way through is
# the door, and the door wants the key off the spur.
for x in (-8.0, 8.0):
    route([x, SUMMIT[2] + 4.0, 140.0], [8.0, 8.0, 2.0], "stone")
gate("the slate gate", [0.0, SUMMIT[2] + 2.5, 140.0], "slate",
     size=(8.0, 5.0, 2.0))
# **The plate is five metres deep and starts at the summit's own lip**, which is
# further back and wider than any other plate in the game. A door rises 5.2 m at
# six metres a second, which is nine tenths of a second, and a runner arriving at
# a walk of six covers five and a half in that time: a plate three metres out
# means meeting the door half open, and a door half open is one that carries its
# visitor up with it. Standing on the top step of the tower is the moment the
# door should start moving.
plate("the slate gate's plate", "the slate gate", [0.0, SUMMIT[2] + 1.6, 136.5],
      size=(8.0, 3.0, 5.0))
lamp("the gate lamp west", [-6.0, SUMMIT[2] + 1.0, 137.0])
lamp("the gate lamp east", [6.0, SUMMIT[2] + 1.0, 137.0])

for i, (x, z) in enumerate(((-4.0, 143.0), (4.0, 143.0), (0.0, 137.0))):
    coin([x, SUMMIT[2] + 0.8, z], f"summit coin {i + 1}")
for i, (x, z) in enumerate(((-2.8, 143.8), (0.0, 145.0), (2.8, 143.8))):
    coin([x, SUMMIT[2] + 2.4, z], f"the beacon's ring {i + 1}")
# `route` rather than `fill` for the two corner blocks, and the difference is
# not stylistic: the summit's whole footprint is in `KEEP_CLEAR`, so generated
# filling is refused there — which is the guard doing its job. Something meant
# to stand on the route is part of the route.
for x in (-10.0, 10.0):
    route([x, SUMMIT[2] + 1.5, 134.5], [3.0, 3.0, 3.0], "stone")
    coin([x, SUMMIT[2] + 3.8, 134.5])
    crate([x, SUMMIT[2], 143.0])

exit_at("the beacon", [0.0, SUMMIT[2] + 1.5, 144.5], "The spire is climbed.")

LIGHTS = [SUN] + [
    point_light(at, c, range=r)
    for at, c, r in (
        ([0.0, 6.0, 0.0], [1.0, 0.9, 0.7], 40.0),
        ([0.0, 8.0, 33.0], [0.85, 0.9, 1.0], 40.0),
        ([0.0, 13.0, 56.5], [1.0, 0.9, 0.75], 44.0),
        ([0.0, 15.0, 80.0], [0.8, 0.88, 1.0], 42.0),
        ([0.0, 18.0, 91.5], [1.0, 0.9, 0.75], 44.0),
        ([0.0, 21.0, 115.0], [0.8, 0.88, 1.0], 42.0),
        ([0.0, 24.0, 126.5], [1.0, 0.92, 0.8], 46.0),
        ([0.0, 25.0, 143.0], [1.0, 1.0, 0.9], 50.0),
    )
]

levelkit.write(
    "spire.json",
    name="Spire",
    lights=LIGHTS,
    fog=(0.04, 0.05, 0.09),
    density=0.005,
    # No `next`: this is where the game ends, and `PlatformerSimulation`'s
    # `nextLevel` being null is the whole of how the credits know it.
    tool="tool/make_spire.py",
)
