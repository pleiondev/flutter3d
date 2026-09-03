#!/usr/bin/env python3
"""Writes `assets/levels/foundry.json` — the fourth level, and the hot one.

    python3 tool/make_foundry.py

**Everything here is a floor that will not stay a floor.** Cisterns asks where
the water is; this one asks how long the ground under you lasts. Planks that
give way under weight, pads that throw you somewhere you did not walk to, lifts
that only move when something is standing on their plate — three ways of taking
the floor out from under a player, in that order, because the first is the one
a level can teach cheaply.

So the shallow pour comes first: a pool of hot metal two and a half metres down
that costs thirty a second and gives the health back nowhere, with a crumbling
gangway over it and a solid catwalk beside the gangway. Falling in is a mistake
you climb out of. The tap hole at the far end is six metres deep and fatal, and
by then the lesson has been paid for once at the cheap rate.

**The tests walk the catwalk and the anvils, not the planks and not the lift.**
A platform that gives way under you is a thing a player times, and a bot that
crosses one is a bot that got lucky — so both crossings have a way over that
holds still, and that is the way the route test goes. What the planks and the
lift get is a claim about their sizes, which is the part that would quietly stop
being true if somebody moved one.

Forty-four metres by a hundred and ninety-two. Sizes are held to the measured
runner — 6 m/s, a jump of 1.8 m, 3.13 with both, about 7.5 m of gap — see
`playthrough_test.dart` for where those numbers come from.

The vocabulary lives in `levelkit.py`; this file is the arrangement.
"""

from levelkit import *  # noqa: F403
import levelkit

W = 44.0
LENGTH = (-14.0, 178.0)

# Ground the generated filling may not stand on: the walked line, the scrap
# ramp, the pocket under the caps, the west catwalk, the ladle's lane, the mould
# stair, the lift and its gantry, and the gate.
KEEP_CLEAR = [
    (-5.0, 5.0, LENGTH[0], LENGTH[1]),
    (-18.0, -10.0, 17.0, 32.0),
    (9.0, 19.0, 21.0, 31.0),
    (-18.0, -10.0, 39.0, 57.0),
    (10.0, 19.0, 39.0, 57.0),
    (-19.0, -3.0, 62.0, 88.0),
    (-22.0, -7.0, 95.0, 127.0),
    (-9.0, 9.0, 128.0, 137.0),
]

levelkit.start(KEEP_CLEAR)


def deck(z0, z1, material="stone", y=0.0):
    """Dry floor, top at `y`."""
    route([0.0, y - 0.5, (z0 + z1) / 2.0], [W, 1.0, z1 - z0], material)


def melt(name, z0, z1, depth, damage=None):
    """A floor sunk below a pool of hot metal, and the pool over it.

    `damage` is what standing in it costs a second; `None` is a tap hole, which
    is not a number — see `Hazard.instant` on why a pit of the stuff is not
    expressed as a large one.
    """
    route([0.0, -depth - 0.5, (z0 + z1) / 2.0], [W, 1.0, z1 - z0], "stone")
    hazard(name, [0.0, -depth / 2.0, (z0 + z1) / 2.0], [W, depth, z1 - z0],
           damage=damage, instant=damage is None)


# The walls. Sixteen metres, because the gantry over the tap hole stands at nine
# and a fence a player can see over is a fence they can walk off. No shadow:
# see `Brush.castsShadow` and the note on `walls()` in first_steps.
for x in (-W / 2 - 0.5, W / 2 + 0.5):
    route([x, 7.0, (LENGTH[0] + LENGTH[1]) / 2.0],
          [1.0, 16.0, LENGTH[1] - LENGTH[0]], "stone", casts=False)
for z in (LENGTH[0] - 0.5, LENGTH[1] + 0.5):
    route([0.0, 7.0, z], [W + 2.0, 16.0, 1.0], "stone", casts=False)

# ------------------------------------------------------------- the cold floor
deck(LENGTH[0], 14.0)
spawn([0.0, 0.0, -10.0])
for i, (x, z) in enumerate(((0.0, -6.0), (-4.0, -2.0), (4.0, -2.0))):
    coin([x, 0.8, z], f"cold floor coin {i + 1}")
lamp("the door lamp west", [-9.0, 1.0, -8.0])
lamp("the door lamp east", [9.0, 1.0, -8.0])
checkpoint("the cold floor", -4.0, 1, respawn=-6.0)
for x in (-17.0, 17.0):
    hut(x, 2.0, 3.4, width=6.0)
    crate([x, 0.0, 8.0])

# ------------------------------------------------------------------ the scrap
# Where the level shows its verbs somewhere they cannot hurt anybody: a ramp you
# walk up, a cap you pound through, a pad that throws you. Nothing here is over
# anything hot, which is the order `first_steps` taught the moves in.
deck(14.0, 40.0)
checkpoint("the scrap", 16.0, 2, respawn=15.0)

# The ramp west, and a ledge on top of it. Three metres over eight is twenty
# degrees, and it is walked rather than jumped.
slope([-14.0, 1.5, 22.0], [6.0, 3.0, 8.0], "stone", "+z")
route([-14.0, 1.5, 28.0], [6.0, 3.0, 4.0], "stone")
coin([-14.0, 4.8, 28.0], "the ramp coin")
coin([-14.0, 4.8, 30.5], "the second ramp coin")

# The caps east: a pocket of coins under three blocks, and a ground pound is the
# only thing that opens it. The walls are three metres and the caps sit on top
# of them, so nothing but a pound gets in.
# The four walls butt rather than overlap — the ends run between the sides
# rather than across them. Two faces in the same plane z-fight, which is the
# level flickering, and the validator says so.
for x in (10.0, 18.0):
    route([x, 1.5, 26.0], [2.0, 3.0, 8.0], "stone")
for z in (22.5, 29.5):
    route([14.0, 1.5, z], [6.0, 3.0, 1.0], "stone")
for i, dx in enumerate((-2.0, 0.0, 2.0)):
    breakable(f"the mould cap {i + 1}", [14.0 + dx, 3.6, 26.0],
              size=(2.0, 1.2, 6.0))
for i, dx in enumerate((-2.0, 0.0, 2.0)):
    coin([14.0 + dx, 0.8, 26.0], f"the cap's coin {i + 1}")

# The pad, over solid ground, with the coins it reaches strung above it. A pad
# shown where a miss costs nothing is a pad a player believes later.
spring("the scrap pad", [0.0, 0.2, 36.0], speed=17.0)
for i, y in enumerate((2.6, 4.0, 5.4)):
    coin([0.0, y, 36.0], f"the pad coin {i + 1}")
enemy("the foreman", [-9.0, 0.0, 33.0], [[9.0, 0.0, 33.0]], speed=0.4)

# ----------------------------------------------------------- the shallow pour
# Sixteen metres of hot metal two and a half down, at thirty a second: a fall
# costs health and a climb, not a life. Three ways over — the catwalk holds
# still, the gangway does not, and the ladle sails.
melt("the shallow pour", 40.0, 56.0, 2.5, damage=30.0)

# The catwalk, west. A plate of brass on legs, three centimetres shy of a step,
# so walking onto it from the bank is walking.
route([-14.0, 0.05, 48.0], [6.0, 0.5, 16.0], "brass")
for z in (43.0, 53.0):
    route([-14.0, -1.35, z], [1.6, 2.3, 1.6], "stone")
    coin([-14.0, 1.1, z])

# The gangway, down the middle: four plates, and the second of them is solid.
# **A rest every other plank is what makes this crossable rather than timed.**
# A plank holds for one and one tenth seconds of weight and comes back three
# seconds after it goes, which is a walk of six metres a second crossing four
# metres of it with room to spare — and a player who stops to think has
# somewhere to stop.
for i, z in enumerate((42.0, 46.0, 50.0, 54.0)):
    if i == 1:
        route([0.0, 0.3, z], [5.0, 0.4, 4.0], "brass")
    else:
        crumbling(f"the gangway plank {i + 1}", [0.0, 0.3, z],
                  size=(5.0, 0.4, 4.0), delay=1.1, gone=3.0)
    coin([0.0, 1.3, z], f"gangway coin {i + 1}")

# The ladle, east: a bucket on a rail, home at the near bank.
mover("platform", "the ladle", [14.0, 0.0, 42.0], [5.0, 0.6, 5.0],
      [0.0, 0.0, 12.0], 3.0, 1.5)
coin([14.0, 1.4, 48.0], "the ladle's coin")

# And two pads on the pool's bed, for whoever ends up down there: a pit you can
# only walk out of the way you fell in is a pit that reads as a punishment.
for x in (-6.0, 6.0):
    spring(f"the relief pad {'west' if x < 0 else 'east'}",
           [x, -2.3, 48.0], speed=17.0)
    coin([x, -1.4, 44.0])

# ----------------------------------------------------------------- the moulds
deck(56.0, 96.0)
checkpoint("the mould floor", 58.0, 3, respawn=57.0)

# The stair of moulds, west, and the key on the top one. Four terraces, each a
# metre and six over the last — under a single jump of 1.8, so the climb asks
# for nothing and the level's difficulty stays where it was put.
for i, (z, top) in enumerate(((66.0, 1.6), (72.0, 3.2), (78.0, 4.8),
                              (84.0, 6.4))):
    route([-11.0, top / 2.0, z], [14.0, top, 6.0], "stone")
    coin([-15.0, top + 0.8, z], f"mould coin {i + 1}")
    coin([-7.0, top + 0.8, z], f"mould coin {i + 5}")
key("the amber key", [-11.0, 7.4, 84.0], "amber")
lamp("the mould lamp", [-11.0, 7.4, 80.0])

# East of it, a pad and a rope, so the half of the hall the stair is not in has
# something in it.
spring("the mould pad", [12.0, 0.2, 70.0], speed=17.0)
for i, y in enumerate((2.6, 4.2, 5.8)):
    coin([12.0, y, 70.0], f"the mould pad coin {i + 1}")
climbable("the charging rope", [16.0, 5.0, 84.0], size=(1.0, 8.0, 1.0),
          swing=3.0, period=2.6)
coin([19.0, 8.6, 84.0], "the rope's coin")
enemy("the moulder", [-2.0, 0.0, 92.0], [[16.0, 0.0, 92.0]], kind="leaper",
      speed=0.45)
for x in (-19.0, 19.0):
    pillar(x, 60.0, 2.4, width=3.0)
    pillar(x, 92.0, 3.6, width=3.0)
    crate([x, 0.0, 76.0])

# ---------------------------------------------------------------- the tap hole
deck(96.0, 104.0)
checkpoint("the tap", 98.0, 4, respawn=97.0)
melt("the tap hole", 104.0, 122.0, 6.0)

# The anvils: columns standing in the stream, tops forty centimetres over the
# far bank. A metre and a half between them, which is a hop you cannot miss —
# what makes this crossing hard is what is underneath it rather than how far
# apart it is, and a level whose last pit is also its widest jump is a level
# that asked for two things at once.
for i, z in enumerate((106.0, 110.0, 114.0, 118.0)):
    route([0.0, -2.8, z], [2.5, 6.4, 2.5], "brass")
    coin([0.0, 1.2, z], f"anvil coin {i + 1}")

# The lift, west, and the gantry it reaches. Nine metres in one ride, on a plate
# that has to be stood on: see `plate` in levelkit on why a mechanism in this
# genre is worked by walking into something.
route([-18.0, 4.5, 100.0], [7.0, 9.0, 7.0], "stone")
mover("lift", "the charging lift", [-12.0, 0.3, 100.0], [4.0, 0.6, 4.0],
      [0.0, 9.0, 0.0], 2.0, 4.0)
plate("the charging lift's plate", "the charging lift", [-12.0, 1.6, 100.0])

# **The gantry stops short of the gate, and that is the point of where it ends.**
# It runs out over the tap hole to the far bank and no further: a walkway that
# carried a player past a locked door would make the key an ornament, and the
# only thing keeping it honest is that there is nothing at nine metres beyond
# z = 124 to walk onto.
route([-12.0, 9.3, 114.0], [6.0, 0.6, 20.0], "wood")
for i in range(4):
    coin([-12.0, 10.4, 107.0 + i * 5.0], f"gantry coin {i + 1}")

deck(122.0, LENGTH[1])
# **Not "the amber gate".** A name is what everything else in the document
# points at — a plate names its door, a hazard names its arm — so two things
# wearing one is a reference nobody can resolve, and the validator refuses the
# level rather than guessing.
checkpoint("the gatehouse", 128.0, 5, respawn=127.0)

# The gate, across the whole width, and its plate in front of it. Eight metres
# of wall against a double jump of 3.13: the way through is the door.
for x in (-13.0, 13.0):
    route([x, 4.0, 134.0], [18.0, 8.0, 2.0], "stone")
gate("the amber gate", [0.0, 2.5, 134.0], "amber", size=(8.0, 5.0, 2.0),
     lintel=8.0)
plate("the amber gate's plate", "the amber gate", [0.0, 1.6, 131.0],
      size=(6.0, 3.0, 3.0))
lamp("the gate lamp west", [-6.0, 1.0, 131.0])
lamp("the gate lamp east", [6.0, 1.0, 131.0])

# ----------------------------------------------------------- the cooling yard
# What is on the other side of the door: two hoists with their plates, a yard of
# crates, and the way out.
checkpoint("the cooling yard", 142.0, 6, respawn=141.0)
for i, (x, z) in enumerate(((-4.0, 142.0), (4.0, 142.0), (0.0, 148.0))):
    coin([x, 0.8, z], f"yard coin {i + 1}")
for x in (-16.0, 16.0):
    side = "west" if x < 0 else "east"
    mover("lift", f"the {side} hoist", [x, 0.3, 146.0], [4.0, 0.6, 4.0],
          [0.0, 7.0, 0.0], 2.0, 4.0)
    plate(f"the {side} hoist's plate", f"the {side} hoist", [x, 1.6, 146.0])
    fill([x, 3.75, 154.0], [8.0, 7.5, 8.0], "stone")
    coin([x, 8.6, 154.0])
    fill([x, 7.8, 162.0], [8.0, 0.6, 8.0], "wood")
    coin([x, 9.0, 162.0])
    crate([x - 5.0 if x < 0 else x + 5.0, 0.0, 150.0])
# Two stacks of cooling ingots, either side of the way out and off it: the
# walked line is the one strip of this hall that stays empty, which is what
# `KEEP_CLEAR` is for and what stops a generated pile from becoming a wall.
#
# **Stacked rather than nested**, which is what separates this from `ziggurat`:
# a ziggurat is a solid block with a smaller solid block inside the top of it,
# and the two share a volume the validator rightly calls a z-fight. Slabs one on
# top of the last share only a face. The coins go half a metre in from each
# tier's edge, which is outside the footprint of the tier above — a coin on the
# middle of a terrace is a coin inside the next one.
def stack(x, z, tiers, step, base, material="brass"):
    for i in range(tiers):
        side = base - i * 2.0
        top = step * (i + 1)
        fill([x, top - step / 2.0, z], [side, step, side], material)
        coin([x + side / 2.0 - 0.5, top + 0.8, z])


for x in (-11.0, 11.0):
    stack(x, 166.0, 3, 1.8, 8.0)
enemy("the yard keeper", [-6.0, 0.0, 172.0], [[6.0, 0.0, 172.0]], speed=0.4)
for i, x in enumerate((-6.0, 6.0)):
    coin([x, 0.8, 170.0], f"the last coin {i + 1}")
exit_at("the shipping door", [0.0, 0.7, 174.0], "The foundry cools.")

LIGHTS = [SUN] + [
    point_light(at, c, range=r)
    for at, c, r in (
        ([0.0, 6.0, -6.0], [0.7, 0.8, 1.0], 36.0),
        ([0.0, 6.0, 26.0], [1.0, 0.86, 0.6], 40.0),
        ([0.0, 4.0, 48.0], [1.0, 0.55, 0.25], 44.0),
        ([0.0, 8.0, 76.0], [1.0, 0.8, 0.5], 46.0),
        ([0.0, 5.0, 113.0], [1.0, 0.45, 0.2], 48.0),
        ([0.0, 7.0, 132.0], [1.0, 0.88, 0.66], 40.0),
        ([0.0, 8.0, 156.0], [0.85, 0.92, 1.0], 46.0),
        ([0.0, 8.0, 174.0], [0.9, 1.0, 0.95], 40.0),
    )
]

levelkit.write(
    "foundry.json",
    name="Foundry",
    lights=LIGHTS,
    fog=(0.10, 0.05, 0.04),
    density=0.006,
    next_level="assets/levels/spire.json",
    tool="tool/make_foundry.py",
)
