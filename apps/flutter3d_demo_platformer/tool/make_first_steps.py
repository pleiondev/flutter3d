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
    # **They cast no shadow, and that is the point of the flag.** Sixteen metres
    # of wall beside a twenty-two metre level lays a hard band of shade across a
    # third of it at this sun — measured at eight per cent of a frame — and it
    # reads as a shadow following the player, because they walk along it. These
    # exist so the level cannot be walked out of; they were never meant to be
    # lighting it.
    route([-WIDE / 2 - 0.5, height / 2 - 1.0, (z0 + z1) / 2.0],
          [1.0, height, z1 - z0], material, casts=False)
    route([WIDE / 2 + 0.5, height / 2 - 1.0, (z0 + z1) / 2.0],
          [1.0, height, z1 - z0], material, casts=False)


LENGTH = (-10.0, 108.0)
walls(*LENGTH)
route([0.0, 7.0, LENGTH[0] - 0.5], [WIDE + 2, 16.0, 1.0], "stone", casts=False)
route([0.0, 7.0, LENGTH[1] + 0.5], [WIDE + 2, 16.0, 1.0], "stone", casts=False)

entities.append({"type": "player_spawn", "at": [0.0, 0.0, -8.0]})

# ------------------------------------------------------------------ walking --
# Nothing to do but go forward, and three coins to make going forward the
# obvious thing. A level that opens with a decision opens with a player
# standing still.
room(-10.0, 8.0)
for i, z in enumerate((-4.0, 0.0, 4.0)):
    coin([0.0, 0.8, z], f"first coin {i + 1}")
# Off the straight line, because a level whose every coin is on the centreline
# teaches that the centreline is the level. These are the first reason to look
# left and right.
for i, (x, z) in enumerate(((-5.0, -6.0), (5.0, -6.0), (-7.0, 1.0), (7.0, 1.0),
                            (-4.0, 6.0), (4.0, 6.0))):
    coin([x, 0.8, z], f"first stray coin {i + 1}")

# ------------------------------------------------------------------- a rise --
# **The first slope, and it is terrain rather than a verb.** A ramp asks
# nothing of a player — you walk up it — so it belongs here, in the room whose
# whole job is walking, and not later where a mistake costs a life. It is
# eight metres long and two tall: fourteen degrees, which the size says on its
# own, because the cut runs corner to corner and the format carries no angle.
#
# Off the centre line and with a coin on top, so the reason to go up it is a
# reason and not an instruction. The ledge it climbs to is a plain block, which
# is what makes the ramp visible as the thing that is not one.
# **Its thin end has to be somewhere a player is walking towards.** The first
# placement put it at z = -9.5, a metre and a half behind the spawn and hard
# against the back wall, so the only way up was to walk backwards first — and
# from the side, at the spawn's own z, the slope's edge stood 0.43 m tall
# against a step of 0.40. Three centimetres: it looked walkable and was not,
# which is the worst number a piece of level geometry can have.
#
# So it starts at floor level six metres ahead of the spawn and runs the way
# the player is already going. Walking forward along the left wall now simply
# becomes walking uphill, with no moment of deciding to.
slope([-9.5, 1.0, -1.0], [3.0, 2.0, 6.0], "stone", "+z")
route([-9.5, 1.0, 3.0], [3.0, 2.0, 2.0], "stone")
coin([-9.5, 2.8, 3.0], "the coin at the top of the slope")

# **The first crate, where it can do no harm.** A player who has never pushed
# one finds out that it moves by walking into it on flat ground, with a coin
# behind it as the reason to bother. Every crate puzzle later in the game is
# this fact plus geometry.
crate([-2.0, 0.7, 2.0], "the first crate")
crate([2.0, 0.7, 2.0], "the second crate")

lamp("the first lamp", [-6.0, 1.0, -2.0])
lamp("the second lamp", [6.0, 1.0, -2.0])

# ------------------------------------------------------------------ jumping --
# A gap of three metres: a single jump crosses seven, so this is a gap you
# cannot fail at, which is the point of the first one.
checkpoint("the first post", 8.0, 1, respawn=6.0)
catch(8.0, 14.0)
room(14.0, 24.0)
coin([0.0, 2.2, 11.0], "the jump coin")
coin([-3.5, 2.2, 11.0], "the jump coin to the left")
coin([3.5, 2.2, 11.0], "the jump coin to the right")

# **The first crate that is worth moving rather than merely movable.** A coin
# hung at 3.4 m is out of reach of both jumps from the floor and easy from the
# top of a crate. Nothing is lost by ignoring it, which is what makes it a
# puzzle rather than a gate.
crate([-6.0, 0.7, 17.0], "the crate to stand on")
coin([-6.0, 3.4, 19.0], "the coin you need the crate for")
for i, x in enumerate((-8.0, -4.0, 4.0, 8.0)):
    coin([x, 0.8, 15.5], f"landing coin {i + 1}")

# ------------------------------------------------------------------- twice ---
# **Shown before it is asked for, which is the rule this room used to break.**
# It went straight to a 2.6 m shelf across the whole width — over a single
# jump's 1.8 and under a double's 3.13 — with nothing before it and no way
# round. A player who had not discovered that a second jump exists in mid-air
# walked into it and stopped: measured, walking and jumping reached z = 23.5
# and stalled there for the rest of the run. The header of this file promises
# that every verb is shown somewhere it cannot hurt you before it is needed
# somewhere it can, and here the showing *was* the wall.
checkpoint("the second post", 22.0, 2, respawn=21.0)

# The showing: coins at 2.6 m over open floor, which is the height of the shelf
# that is coming. Missing them costs nothing, and reaching them is the lesson.
coin([0.0, 2.6, 19.0], "the coin you cannot reach once")
coin([-4.5, 2.6, 21.0], "the coin you cannot reach twice")
coin([4.5, 2.6, 21.0], "the coin you cannot reach three times")

# The asking, and beside it a step. **The step is the door, the coin on top is
# the lesson**: a player who has worked out the double jump goes straight over
# and is paid for it, and one who has not climbs in two goes and keeps playing.
# The crate in the room behind also reaches — pushed to the face, it is 1.4 m
# to stand on — but a crate can be shoved into the pit, and a door that the
# player can destroy is not a door.
route([0.0, 1.3, 26.0], [WIDE, 2.6, 4.0], "stone")
route([9.0, 0.65, 23.0], [4.0, 1.3, 2.0], "moss")
coin([0.0, 3.6, 26.0], "the high coin")
coin([9.0, 2.0, 23.0], "the coin on the step")

catch(28.0, 36.0)
room(36.0, 46.0)
coin([0.0, 3.0, 32.0], "the second jump coin")
coin([-3.5, 3.0, 31.0], "the coin left of the gap")
coin([3.5, 3.0, 33.0], "the coin right of the gap")

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
coin([0.0, 1.4, 52.0], "the shaft coin one")
coin([0.0, 3.0, 52.0], "the shaft coin two")
coin([0.0, 4.4, 52.0], "the shaft coin three")
coin([0.0, 5.8, 52.0], "the shaft coin four")
# A ladder of coins rather than two: a climb you are paid for at every metre is
# a climb you keep trying. Two coins six metres apart is a climb you abandon.

# The room the chimney stands in, which was a corridor with a slot in it. A
# crate to push, and coins along the walls, so the room is somewhere you are
# rather than somewhere you pass.
# **In the room before the shaft, not in it.** The shaft room's floor is almost
# entirely underneath the two chimney blocks — they run from z = 47 to 57 across
# all but the two-metre slot — so a crate "at the foot of the shaft" was a crate
# inside a wall, and so were half these coins. There is one metre of open floor
# in front of the blocks, and that is where the things you can reach go.
crate([-6.0, 0.7, 42.0], "the crate before the shaft")
for i, x in enumerate((-9.0, -4.0, 4.0, 9.0)):
    coin([x, 0.8, 46.4], f"shaft floor coin {i + 1}")

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
# A line of them, so the dash is worth trying before it is needed: each one is
# a little further than a walk gets you comfortably.
for i, z in enumerate((69.5, 70.5, 71.5)):
    coin([0.0, 7.0, z], f"the dash trail {i + 1}")
route([0.0, 5.5, 84.0], [WIDE, 1.0, 10.0], "stone")
coin([0.0, 8.0, 74.0], "the gap coin")
coin([-4.0, 8.0, 74.0], "the gap coin to the left")
coin([4.0, 8.0, 74.0], "the gap coin to the right")

# A crate on the far side, and a coin only reachable from on top of it. The
# last thing the level teaches about crates: they come with you.
crate([7.0, 6.2, 82.0], "the crate on the far side")
coin([7.0, 8.9, 84.0], "the coin above the far crate")

# And a shallow floor under the gap, with a stair up to the far side: a miss
# costs a few seconds, not a walk back to the start.
route([0.0, 4.0, 74.5], [WIDE, 1.0, 9.0], "stone")
route([0.0, 4.875, 77.0], [WIDE, 0.75, 2.0], "stone")
route([0.0, 5.625, 78.5], [WIDE, 0.75, 1.0], "stone")

# ---------------------------------------------------------------- crouching --
# A metre of headroom, over a floor that carries on: the slab is thick enough
# that jumping at it is obviously not the answer.
checkpoint("the fifth post", 88.0, 5, respawn=88.0)
# **A metre of headroom, and it used to be half of one.** The floor's top is at
# y = 6 and the slab's underside was at 6.5 — against a crouched body 0.9 m
# tall, which is a room that cannot be crawled through at all. The autopilot
# still finished the level, by climbing the 5.5 m face of the slab, so nothing
# said so. Now the underside is at 7: a crouch fits with room to spare and a
# standing runner, 1.8 m, does not.
route([0.0, 9.5, 94.0], [WIDE, 5.0, 8.0], "stone")
route([0.0, 5.5, 96.0], [WIDE, 1.0, 14.0], "stone")
for i, z in enumerate((91.5, 94.0, 96.5)):
    coin([0.0, 6.5, z], f"the crawl coin {i + 1}")
coin([-5.0, 6.5, 94.0], "the crawl coin to the left")
coin([5.0, 6.5, 94.0], "the crawl coin to the right")

# ----------------------------------------------------------------- the guard -
# One thing that walks, on a route across the way out, with the exit behind it.
enemy("the guard", [-6.0, 6.0, 101.0], [[6.0, 6.0, 101.0]], speed=0.3)
coin([0.0, 6.8, 101.0], "the guard's coin")
coin([-8.0, 6.8, 100.0], "the coin the guard walks past")
coin([8.0, 6.8, 102.0], "the other coin the guard walks past")
crate([-8.0, 6.2, 103.0], "the last crate")
crate([8.0, 6.2, 103.0], "the other last crate")

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
