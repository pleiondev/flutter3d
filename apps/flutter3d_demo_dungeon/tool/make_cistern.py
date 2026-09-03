#!/usr/bin/env python3
"""The fourth level: the cistern.

    python3 tool/make_cistern.py

The deep took the rocket launcher away by making every room too small to fire
it in. This one gives the room back and takes the floor instead: the middle of
the level is a flooded basin a metre and a fifth below everything around it,
and the fight is about **height** — who is standing on a pier and who is wading.

The shape is the vaults' crossroads sunk into water:

                          [ drain ] —— locked (iron) —— [ outflow ] exit
                              |
                       locked (brass)
                              |
    [ sluice ] ——pier—— [ b a s i n ] ——pier—— [ pump room ]
     brass key           water, tanks             iron key
                              |
                         [ landing ]
                            spawn

A pier runs in from each doorway and ends in a flight of steps down into the
water, so every crossing of the basin is a descent and a climb, and a tank
waiting in the water is a tank a player looks down on and then has to walk
past. The shooters are on the piers, which is the other half of the same
lesson: the high ground is where the fire comes from.

Two keys again, one per wing, because the second level's lesson is worth using
twice — but here the basin is between the player and both of them, so neither
wing is reached without wading. And a **secret**, the first in the game: an
opening a metre wide in the west wall, behind a pillar, at the water line where
nobody looks, with the rockets the rest of the level is short of.
"""

import cryptkit as k

TOOL = "apps/flutter3d_demo_dungeon/tool/make_cistern.py"

#: How far below the rest of the level the water stands. Deep enough that a
#: pier is unmistakably above it, shallow enough to wade: four steps of 0.3
#: get a body out of it, and 0.3 is under the step height a body climbs.
DEPTH = 1.2

#: The water's own colour, on the fog too: a level that is green-black in the
#: distance rather than grey-black is a level that reads as wet from the door.
FOG = (0.024, 0.036, 0.034)

LANDING = (0.0, 0.0, 14.0)
BASIN = (0.0, 0.0, -6.0)
ALCOVE = (-15.0, 0.0, 2.0)
SLUICE = (-19.0, 0.0, -6.0)
PUMP = (19.0, 0.0, -6.0)
DRAIN = (0.0, 0.0, -28.0)
OUTFLOW = (0.0, 0.0, -43.0)

#: Light off water: colder than a torch and greener than the stair's blue.
WET = (0.5, 0.85, 0.8)


def build():
    k.start()

    # ── The landing. Dry, lit, and the last quiet floor for a while. ────────
    k.room(LANDING, (10.0, 0.0, 8.0), doors=[("north", 0.0, 4.0, 4.0)])
    k.spawn((0.0, 0.0, 16.0))
    k.torch((-4.4, 2.8, 14.0), name="landing_west", yaw=1.5708)
    k.torch((4.4, 2.8, 14.0), name="landing_east", yaw=-1.5708)
    # On the north wall, west of the doorway, the way the crypt's is.
    k.note(
        (-3.5, 1.6, 10.03),
        "The wardens flooded the cistern to keep what is in it from climbing "
        "out. It did not work.",
    )
    k.pickup("shells", (3.0, 0.8, 12.0), amount=8)
    k.corridor((0.0, 0.0, 9.0), (0.0, 0.0, 5.0), width=4.0, height=4.0,
               doors=[("north", 0.0, 4.0, 4.0), ("south", 0.0, 4.0, 4.0)])

    # ── The basin. Sunken, flooded, and crossed by piers. ──────────────────
    #
    # Every doorway into it is at the level of the rooms outside, so each hole
    # has a sill at zero and the wall runs on below it down to the water. The
    # west wall has two openings: the pier's, and the secret's at the water
    # line.
    k.room(BASIN, (24.0, 0.0, 20.0), base=-DEPTH, height=6.2, doors=[
        ("south", 0.0, 4.0, 4.0, 0.0),    # the landing
        ("west", 0.0, 4.0, 4.0, 0.0),     # the sluice
        ("east", 0.0, 4.0, 4.0, 0.0),     # the pump room
        ("north", 0.0, 6.0, 4.0, 0.0),    # the locked gate
        ("west", 8.0, 1.2, 2.4),          # the secret, floor to lintel
    ])
    # **The water is a plane the player walks through.** Solid would make it a
    # floor; this is drawn and stops nothing, and the piers pass through it.
    k.block((0.0, -DEPTH + 0.325, -6.0), (24.0, 0.05, 20.0), "water",
            solid=False, casts=False)

    # A pier from each doorway, standing on the basin floor so there is no
    # surface under it for the navigation grid to prefer, and a flight of
    # steps off the end of each.
    #
    # **Four steps, a metre deep each, on whole metres.** Not a number picked
    # for looks: the navigation grid is a quarter-metre lattice and a cell that
    # straddles two steps has the upper one standing in the lower one's
    # headroom, which the bake reads as no surface at all. A run of a metre
    # falls on the lattice whatever else the level does, and 0.3 of rise is
    # under the step height a body climbs. The eight-step default would put a
    # 0.375 run under a 0.25 cell and dig a trench of dead cells down the
    # middle of every flight — see `stair` in `cryptkit.py`.
    k.block((0.0, -DEPTH / 2.0, 1.5), (4.0, DEPTH, 5.0), "stone")
    k.stair((0.0, 0.0, -0.5), (0.0, -DEPTH, -4.5), steps=4, bottom=-DEPTH)
    k.block((-10.0, -DEPTH / 2.0, -6.0), (4.0, DEPTH, 4.0), "stone")
    k.stair((-8.5, 0.0, -6.0), (-4.5, -DEPTH, -6.0), steps=4, bottom=-DEPTH)
    k.block((10.0, -DEPTH / 2.0, -6.0), (4.0, DEPTH, 4.0), "stone")
    k.stair((8.5, 0.0, -6.0), (4.5, -DEPTH, -6.0), steps=4, bottom=-DEPTH)
    k.block((0.0, -DEPTH / 2.0, -14.0), (6.0, DEPTH, 4.0), "stone")
    k.stair((0.0, 0.0, -12.5), (0.0, -DEPTH, -8.5), steps=4, bottom=-DEPTH)

    # Columns from the water to the vault. The one at the south-west corner is
    # not holding anything up: it stands in front of the secret's opening.
    for x, z in ((-6.0, -2.0), (6.0, -2.0), (-6.0, -10.0), (6.0, -10.0),
                 (-10.0, 2.0)):
        k.pillar((x, -DEPTH + 3.1, z), size=(1.4, 6.2, 1.4))

    k.lamp((0.0, 4.0, -6.0), name="basin_lamp", colour=WET, intensity=6.0,
           rng=18.0)
    k.torch((-11.4, 2.0, -12.0), name="basin_northwest", yaw=1.5708)
    k.torch((11.4, 2.0, -12.0), name="basin_northeast", yaw=-1.5708)
    k.torch((-11.4, 2.0, 0.0), name="basin_southwest", yaw=1.5708,
            intensity=5.0)
    k.torch((11.4, 2.0, 0.0), name="basin_southeast", yaw=-1.5708,
            intensity=5.0)

    # Tanks in the water, shooters on the piers, runners to make wading slow.
    k.monster("tank", (0.0, -DEPTH, -6.0))
    k.monster("tank", (-4.0, -DEPTH, -12.0))
    k.monster("shooter", (-2.0, 0.0, -14.0))
    k.monster("shooter", (10.0, 0.0, -7.0))
    k.monster("runner", (8.0, -DEPTH, -1.0))
    k.monster("runner", (-8.0, -DEPTH, -11.0))
    k.pickup("health", (4.0, -DEPTH + 0.8, 2.0), amount=25)
    k.pickup("shells", (-4.0, -DEPTH + 0.8, -13.0), amount=8)

    # The gate north, seen from the landing's pier before either key is.
    k.door("sluice_gate", (0.0, 2.0, -16.0), key="brass",
           size=(6.0, 4.0, 1.0), travel=(0.0, 4.1, 0.0))
    k.trigger("sluice_gate", (0.0, 1.5, -14.4), size=(6.0, 3.0, 2.0))

    # ── The secret: a cellar off the basin, at the water line. ─────────────
    k.room(ALCOVE, (4.0, 0.0, 4.0), base=-DEPTH, height=3.0,
           doors=[("east", 0.0, 1.2, 2.4)])
    k.torch((-16.4, 1.0, 2.0), name="alcove", yaw=1.5708, colour=WET,
            intensity=3.0, rng=8.0)
    k.secret((-15.0, -DEPTH + 1.25, 2.0))
    k.pickup("rockets", (-15.0, -DEPTH + 0.8, 2.0), amount=4)
    k.pickup("armour", (-16.0, -DEPTH + 0.8, 1.0), amount=25)

    # ── The sluice, west: shooters and the brass key. ──────────────────────
    k.room(SLUICE, (12.0, 0.0, 10.0), doors=[("east", 0.0, 4.0, 4.0)])
    k.torch((-24.4, 2.8, -6.0), name="sluice_west", yaw=1.5708)
    k.torch((-19.0, 2.8, -10.4), name="sluice_north")
    k.pillar((-17.0, 2.0, -9.0))
    k.pillar((-21.0, 2.0, -6.0))
    k.monster("shooter", (-22.0, 0.0, -9.0))
    k.monster("shooter", (-22.0, 0.0, -3.0))
    k.monster("runner", (-16.0, 0.0, -2.0))
    k.pickup("shells", (-15.0, 0.8, -9.0), amount=8)
    k.pickup("health", (-23.0, 0.8, -2.0), amount=25)
    k.key("brass", (-23.0, 0.9, -6.0))

    # ── The pump room, east: tanks, and the iron key on a dais. ────────────
    k.room(PUMP, (12.0, 0.0, 12.0), height=5.0,
           doors=[("west", 0.0, 4.0, 4.0)])
    k.lamp((19.0, 4.2, -6.0), name="pump_lamp", intensity=5.0, rng=14.0)
    k.torch((24.4, 3.0, -9.0), name="pump_northeast", yaw=-1.5708)
    k.torch((24.4, 3.0, -3.0), name="pump_southeast", yaw=-1.5708)
    k.pillar((16.0, 2.5, -3.0), size=(1.2, 5.0, 1.2))
    k.pillar((16.0, 2.5, -9.0), size=(1.2, 5.0, 1.2))
    # One step up, under the step height, so the key is seen over the tanks
    # before it is reached through them.
    k.block((22.0, 0.15, -6.0), (4.0, 0.3, 4.0), "stone")
    k.monster("tank", (22.0, 0.0, -10.0))
    k.monster("tank", (22.0, 0.0, -2.0))
    k.monster("shooter", (16.0, 0.0, -10.0))
    k.pickup("bullets", (15.0, 0.8, -1.0), amount=20)
    k.pickup("rockets", (24.0, 0.8, -11.0), amount=2)
    k.pickup("health", (24.0, 0.8, -1.0), amount=25)
    k.key("iron", (22.0, 1.2, -6.0))

    # ── Through the gate: the drain, and the second lock. ──────────────────
    k.corridor((0.0, 0.0, -17.0), (0.0, 0.0, -22.0), width=6.0, height=4.0,
               doors=[("north", 0.0, 6.0, 4.0), ("south", 0.0, 6.0, 4.0)])
    k.room(DRAIN, (12.0, 0.0, 10.0), doors=[
        ("south", 0.0, 6.0, 4.0),
        ("north", 0.0, 4.0, 4.0),
    ])
    k.torch((-5.4, 2.8, -25.0), name="drain_west", yaw=1.5708, colour=WET,
            intensity=5.0)
    k.torch((5.4, 2.8, -31.0), name="drain_east", yaw=-1.5708, colour=WET,
            intensity=5.0)
    k.pillar((-3.0, 2.0, -28.0))
    k.pillar((3.0, 2.0, -28.0))
    k.monster("tank", (0.0, 0.0, -30.0))
    k.monster("runner", (-4.0, 0.0, -25.0))
    k.monster("runner", (4.0, 0.0, -31.0))
    k.pickup("health", (-4.0, 0.8, -24.0), amount=25)
    k.pickup("shells", (4.0, 0.8, -24.0), amount=8)
    k.pickup("armour", (-4.0, 0.8, -31.0), amount=25)

    k.door("outflow_gate", (0.0, 2.0, -33.0), key="iron",
           size=(4.0, 4.0, 1.0), travel=(0.0, 4.1, 0.0))
    k.trigger("outflow_gate", (0.0, 1.5, -31.4), size=(4.0, 3.0, 2.0))

    # ── The outflow, and the way on. ───────────────────────────────────────
    k.corridor((0.0, 0.0, -34.0), (0.0, 0.0, -38.0), width=4.0, height=4.0,
               doors=[("north", 0.0, 4.0, 4.0), ("south", 0.0, 4.0, 4.0)])
    k.room(OUTFLOW, (10.0, 0.0, 8.0), height=5.0,
           doors=[("south", 0.0, 4.0, 4.0)])
    k.torch((-4.4, 3.0, -43.0), name="outflow_west", yaw=1.5708,
            colour=(0.55, 0.78, 1.0), intensity=5.0)
    k.pickup("armour", (3.0, 0.8, -41.0), amount=25)
    k.exit_at("the_sanctum", (0.0, 0.0, -45.0))

    k.write("cistern.json", name="The Cistern", fog=FOG,
            next_level="assets/levels/sanctum.json",
            materials={"water": k.WATER}, tool=TOOL)


if __name__ == "__main__":
    build()
