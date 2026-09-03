#!/usr/bin/env python3
"""Writes `assets/levels/cisterns.json` — the third level, and the wet one.

    python3 tool/make_cisterns.py

**Water is the hazard, and how deep it is is the difficulty.** Ascent kills with
a drop and a spike; this level has one thing that hurts, and it hurts more the
further in you are. The wading pool at the start costs a little health and a
walk back to the edge; the race under the belts costs more; the great cistern
in the middle is deep, and deep water is a life. A player learns the rule where
it is cheap and meets it where it is not, which is the order `first_steps`
taught the verbs in.

Three ways across the deep water, because a crossing with one way over is a
doorway: the pilings down the middle, a barge along either side, and the weir —
a line of stones to the key island and on to the far shore. The barges are the
scenic route; the stones are the one the tests walk, because a moving platform
is something a player times and an autopilot gets lucky on.

Forty metres by a hundred and eighty-four. Sizes are held to the measured
runner — 6 m/s, a jump of 1.8 m, 3.13 with both, about 7.5 m of gap — and
every hop over water here is well inside the first of those numbers.

The vocabulary lives in `levelkit.py`; this file is the arrangement.
"""

from levelkit import *  # noqa: F403
import levelkit

W = 40.0
LENGTH = (-14.0, 170.0)

# Ground the filling may not stand on: the walked line, the weir, both barge
# lanes, and the wading stones.
KEEP_CLEAR = [
    (-4.0, 4.0, LENGTH[0], LENGTH[1]),
    (12.0, 18.0, 78.0, 114.0),
    (-12.0, -6.0, 78.0, 114.0),
    (5.0, 11.0, 78.0, 114.0),
    (-5.0, 5.0, 2.0, 24.0),
]

levelkit.start(KEEP_CLEAR)


def quay(z0, z1, material="stone"):
    """Dry floor, top at nought."""
    route([0.0, -0.5, (z0 + z1) / 2.0], [W, 1.0, z1 - z0], material)


def basin(name, z0, z1, depth, damage=None):
    """A floor below the waterline and the water over it.

    Shallow water damages and deep water kills: `damage` is what wading costs a
    second, and `None` is a drowning. The floor is moss, because a cistern's
    bed is weed.
    """
    route([0.0, -depth - 0.5, (z0 + z1) / 2.0], [W, 1.0, z1 - z0], "moss")
    hazard(name, [0.0, -depth / 2.0, (z0 + z1) / 2.0], [W, depth, z1 - z0],
           damage=damage, instant=damage is None)


def stone(x, z, floor, top=0.4, width=3.0):
    """A stepping stone rising out of a basin whose bed is at `floor`."""
    route([x, (floor + top) / 2.0, z], [width, top - floor, width], "stone")


# The walls, so nobody swims out of the level. Fourteen metres, and they cast no
# shadow: see `Brush.castsShadow` and the note on `walls()` in first_steps.
for x in (-W / 2 - 0.5, W / 2 + 0.5):
    route([x, 6.0, (LENGTH[0] + LENGTH[1]) / 2.0],
          [1.0, 14.0, LENGTH[1] - LENGTH[0]], "stone", casts=False)
for z in (LENGTH[0] - 0.5, LENGTH[1] + 0.5):
    route([0.0, 6.0, z], [W + 2.0, 14.0, 1.0], "stone", casts=False)

# ------------------------------------------------------------------- the quay
quay(LENGTH[0], 2.0)
spawn([0.0, 0.0, -10.0])
for i, (x, z) in enumerate(((-3.0, -6.0), (3.0, -6.0), (0.0, -2.0))):
    coin([x, 0.8, z], f"quay coin {i + 1}")
lamp("the quay lamp west", [-8.0, 1.0, -8.0])
lamp("the quay lamp east", [8.0, 1.0, -8.0])
checkpoint("the quay", 0.0, 1, respawn=-2.0)

# ------------------------------------------------------------ the wading pool
# Shallow: the bed is 1.2 m down, wading costs fifteen a second, and getting out
# is a jump onto the far quay. Four stones across it, a metre and a half apart,
# which is a hop you cannot miss — and the first thing the level says about
# water is that it is better not to be in it.
#
# **Fifteen rather than the twenty it was written with, and the arithmetic is
# the argument.** Twenty-two metres of pool at a walk of six is three and seven
# tenths of a second in the water, which at twenty a second is three quarters of
# everything a runner has — for the room whose whole job is to teach that water
# hurts. Health comes back on dying and nowhere else, so the price of the
# *lesson* was the rest of the level.
basin("the shallows", 2.0, 24.0, 1.2, damage=15.0)
for i, (x, z) in enumerate(((0.0, 5.5), (-3.0, 10.0), (3.0, 14.5), (0.0, 19.0))):
    stone(x, z, -1.2)
    coin([x, 1.2, z], f"stone coin {i + 1}")

# ---------------------------------------------------------------- the landing
quay(24.0, 40.0)
checkpoint("the landing", 27.0, 2, respawn=26.0)
# The first thing that walks, across the way, slow enough to walk round.
enemy("the warden", [-8.0, 0.0, 34.0], [[8.0, 0.0, 34.0]], speed=0.35)
coin([0.0, 0.8, 34.0], "the warden's coin")
for x in (-14.0, 14.0):
    hut(x, 32.0, 3.6, width=6.0)
    crate([x, 0.0, 37.5])

# -------------------------------------------------------------- the belt hall
# Three belts over the race. The middle one runs against you at three and a
# half against a walk of six, which is a slow way across with a coin every four
# metres; the outer two run with you and pay less. Off the side of any of them
# is water that costs thirty a second and a jump back out.
#
# **Their decks stand a quarter of a metre clear of the waterline**, and that
# gap is the point of the number rather than a rounding of it. A belt whose top
# is flush with the top of the water is a belt whose passenger's box touches the
# hazard's box exactly, and whether that counts as an overlap is a question
# about the broadphase's comparisons — which is not a question a level should be
# asking. A step of 0.25 is under the runner's step height and reads as nothing.
basin("the race", 40.0, 64.0, 1.0, damage=30.0)
conveyor("the slow belt", [0.0, 0.0, 52.0], [0.0, 0.0, -3.5], size=(5.0, 0.5, 24.0))
conveyor("the west belt", [-7.0, 0.0, 52.0], [0.0, 0.0, 4.0], size=(5.0, 0.5, 24.0))
conveyor("the east belt", [7.0, 0.0, 52.0], [0.0, 0.0, 4.0], size=(5.0, 0.5, 24.0))
for i, z in enumerate((44.0, 48.0, 52.0, 56.0, 60.0)):
    coin([0.0, 0.8, z], f"belt coin {i + 1}")
for z in (46.0, 58.0):
    coin([-7.0, 0.8, z])
    coin([7.0, 0.8, z])

# ----------------------------------------------------------------- the sluice
quay(64.0, 80.0)
checkpoint("the sluice", 67.0, 3, respawn=66.0)
lamp("the sluice lamp", [0.0, 1.0, 70.0])
for x in (-15.0, -10.0):
    crate([x, 0.0, 72.0])
pillar(-15.0, 77.0, 2.6, width=3.0)
pillar(15.0, 68.0, 3.4, width=3.0)

# **A post at the head of the weir, off the centre line, and it is there because
# of where a death puts you.** The sluice's post is on the walked line at z = 67;
# a player who drowns half way along the weir comes back to it, and the shortest
# way from there to where they were is a diagonal straight across four metres of
# deep water. So they drown again, and again, on the way to the same place. A
# checkpoint is not only a saving of progress — it is a statement about which
# direction the level is walked in from here, and this one says "along the
# stones". Twenty-four metres wide from x = 3, so the pilings down the middle do
# not collect it and a player crossing there keeps the sluice.
checkpoint("the head of the weir", 78.0, 4, respawn=78.0, x=15.0)

# ---------------------------------------------------------- the great cistern
# Four metres deep, and deep water is a life. Three ways across.
basin("the deep", 80.0, 112.0, 4.0)

# The pilings, down the middle: six metres between centres and three across,
# so each hop is three metres of water — a jump, and not a long one.
for i, z in enumerate((84.0, 90.0, 96.0, 102.0, 108.0)):
    stone(0.0, z, -4.0)
    if i % 2 == 0:
        coin([0.0, 1.2, z], f"piling coin {i // 2 + 1}")

# The barges, one a side, home at the near shore and sailing to the far one.
# **Named, and not on the tested route**: a platform you wait for is a thing a
# player times, and the tests prove the level finishable rather than lucky.
mover("platform", "the west barge", [-9.0, -0.3, 83.0], [5.0, 0.6, 5.0],
      [0.0, 0.0, 26.0], 3.5, 1.5)
mover("platform", "the east barge", [8.0, -0.3, 83.0], [5.0, 0.6, 5.0],
      [0.0, 0.0, 26.0], 3.5, 1.5, phase=4.0)
coin([-9.0, 1.4, 96.0], "the west barge coin")
coin([8.0, 1.4, 96.0], "the east barge coin")

# The weir: stones three across with a metre between them, out to the key island
# and on to the far shore. The key sits a metre off the island's top, which is
# where the validator can see it is not in the rock.
#
# **A metre, and it is the difference between a crossing and a jump.** The
# stones were two and a half across with a metre and a half of water between
# them, which is a quarter of a second in the air at a walk of six — long enough
# to fall three quarters of a metre, which is below the next stone's top, so a
# runner who simply walked the weir clipped the far face and went in. At a metre
# the fall is a third of that and inside the runner's step, so walking works and
# the weir is what it was meant to be: the long safe way over, against the
# pilings down the middle, which are three metres apart and want a jump each.
WEIR_X = 15.0
for z in (84.0, 88.0, 92.0, 100.0, 104.0, 108.0):
    stone(WEIR_X, z, -4.0, width=3.0)
route([WEIR_X, -1.8, 96.0], [5.0, 4.4, 5.0], "stone")
key("the rust key", [WEIR_X, 1.4, 96.0], "red")
coin([WEIR_X, 1.2, 88.0], "weir coin one")
coin([WEIR_X, 1.2, 104.0], "weir coin two")

# ---------------------------------------------------------------- the far shore
quay(112.0, 130.0)
checkpoint("the far shore", 114.0, 5, respawn=114.0)
enemy("the second warden", [-6.0, 0.0, 118.0], [[6.0, 0.0, 118.0]], speed=0.4)
for x in (-13.0, 13.0):
    pillar(x, 116.0, 2.0, width=3.0)

# The rust gate, across the whole width, and its plate in front of it. A gate
# with no plate never opens: see `plate` in levelkit.
for x in (-12.0, 12.0):
    route([x, 3.0, 124.0], [16.0, 6.0, 2.0], "stone")
gate("the rust gate", [0.0, 2.5, 124.0], "red", size=(8.0, 5.0, 2.0))
plate("the rust gate's plate", "the rust gate", [0.0, 1.6, 121.0],
      size=(6.0, 3.0, 3.0))
lamp("the gate lamp west", [-6.0, 1.0, 122.0])
lamp("the gate lamp east", [6.0, 1.0, 122.0])

# ---------------------------------------------------------------- the spillway
# Deep water again, and the way over it is up: three shelves you jump through
# from below, each a metre and a bit above the last and four metres on, to the
# gallery. A single jump is 1.8 up and seven along, so every one of these is
# one jump — but a walk straight off the shore goes under the first shelf and
# into the water, which is the whole of what a one-way platform teaches.
checkpoint("the spillway", 128.0, 6, respawn=127.0)
basin("the spill", 130.0, 142.0, 4.0)
# Four metres long apiece and four apart, so they butt rather than overlap: the
# quay's lip is the first one's near edge and the gallery's is the last one's
# far edge, and the whole climb is three hops of 1.2 m.
SHELVES = ((132.0, 1.2), (136.0, 2.4), (140.0, 3.6))
for i, (z, y) in enumerate(SHELVES):
    oneway(f"the shelf {i + 1}", [0.0, y, z], size=(6.0, 0.3, 4.0))
    coin([0.0, y + 1.0, z], f"shelf coin {i + 1}")
# A second run of shelves at the side, so the climb is not a doorway either.
for i, (z, y) in enumerate(SHELVES):
    oneway(f"the side shelf {i + 1}", [-12.0, y, z], size=(6.0, 0.3, 4.0))
    coin([-12.0, y + 1.0, z])

# ----------------------------------------------------------------- the gallery
# Four metres up, and the exit at the end of it. A rope over the floor for a
# coin, a keeper walking the way out, and the outflow.
route([0.0, 2.0, 156.0], [W, 4.0, 28.0], "stone")
checkpoint("the gallery", 144.0, 7, respawn=144.0, y=4.0)
climbable("the bell rope", [10.0, 7.0, 150.0], size=(1.0, 6.0, 1.0),
          swing=3.0, period=2.6)
coin([13.0, 10.0, 150.0], "the bell coin")
enemy("the keeper", [-5.0, 4.0, 160.0], [[5.0, 4.0, 160.0]], speed=0.4)
for i, (x, z) in enumerate(((-4.0, 148.0), (4.0, 148.0), (0.0, 156.0))):
    coin([x, 4.8, z], f"gallery coin {i + 1}")
for x in (-14.0, 14.0):
    crate([x, 4.0, 158.0])
    # **Standing on the gallery, not through it.** `pillar` puts its foot at
    # y = 0, which here is four metres inside the gallery's own slab — two
    # brushes in the same volume, which is the z-fight the validator warns
    # about. A column on a terrace starts at the terrace.
    fill([x, 5.25, 165.0], [3.0, 2.5, 3.0], "stone")
    coin([x, 7.3, 165.0])
exit_at("the outflow", [0.0, 4.7, 165.0], "The cisterns drain.")

LIGHTS = [SUN] + [
    point_light(at, c, range=r)
    for at, c, r in (
        ([0.0, 6.0, -6.0], [0.7, 0.9, 1.0], 36.0),
        ([0.0, 6.0, 14.0], [0.6, 0.9, 0.9], 40.0),
        ([0.0, 6.0, 32.0], [1.0, 0.9, 0.7], 36.0),
        ([0.0, 6.0, 52.0], [0.6, 0.9, 0.9], 44.0),
        ([0.0, 6.0, 72.0], [1.0, 0.9, 0.7], 36.0),
        ([0.0, 7.0, 96.0], [0.5, 0.85, 1.0], 50.0),
        ([0.0, 7.0, 118.0], [1.0, 0.9, 0.7], 40.0),
        ([0.0, 8.0, 136.0], [0.6, 0.9, 0.9], 40.0),
        ([0.0, 10.0, 156.0], [0.9, 1.0, 0.95], 44.0),
    )
]

levelkit.write(
    "cisterns.json",
    name="Cisterns",
    lights=LIGHTS,
    fog=(0.04, 0.09, 0.10),
    density=0.006,
    next_level="assets/levels/foundry.json",
    tool="tool/make_cisterns.py",
)
