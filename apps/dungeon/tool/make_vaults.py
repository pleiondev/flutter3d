#!/usr/bin/env python3
"""The second level: the vaults.

    python3 tool/make_vaults.py

The crypt taught one lesson at a time in one line. This one is where the game
stops being a corridor, and it does that by making the player **choose the order
of two things** rather than by making anything harder.

The shape is a crossroads. Two wings, two keys, one door that wants both:

    [ west wing ]        [ landing ]        [ east wing ]
      brass key    ——   crossroads   ——      iron key
                             |
                        double door
                             |
                        [ shaft ]  lift, button, exit

Neither wing is the way forward and both have to be visited, so a player who
walks in a straight line runs out of level and has to look. That is the whole
step up from the crypt, and it costs no new mechanic to teach.

**The mechanisms the crypt deliberately did not have are here**, one per wing,
so each is met alone: a button and a lift in the shaft, a moving platform over
the gap in the west wing. Meeting one of each in the first level — which is what
the hand-written crypt did — teaches none of them.

The fight steps up by kind rather than by count. The east wing has the shooters
and long sight lines; the west has runners and corners.
"""

import cryptkit as k

TOOL = "apps/dungeon/tool/make_vaults.py"

LANDING = (0.0, 0.0, 6.0)
CROSS = (0.0, 0.0, -8.0)
WEST = (-20.0, 0.0, -8.0)
EAST = (20.0, 0.0, -8.0)
SHAFT = (0.0, 0.0, -26.0)


def build():
    k.start()

    # ── The landing you arrive on. ─────────────────────────────────────────
    k.room(LANDING, (10.0, 0.0, 10.0), doors=[("north", 0.0, 4.0, 4.0)])
    k.spawn((0.0, 0.0, 9.0))
    k.torch((-4.4, 2.8, 8.0), name="landing_west", yaw=1.5708)
    k.torch((4.4, 2.8, 8.0), name="landing_east", yaw=-1.5708)
    k.note(
        (0.0, 1.6, 1.6),
        "Two locks, and they gave a key to each of the wings. "
        "Neither warden trusted the other.",
    )
    k.corridor((0.0, 0.0, 1.0), (0.0, 0.0, -2.0), width=4.0, height=4.0,
               doors=[("north", 0.0, 4.0, 4.0), ("south", 0.0, 4.0, 4.0)])

    # ── The crossroads. Everything is visible from here and nothing is
    #    reachable in a straight line. ────────────────────────────────────────
    k.room(CROSS, (14.0, 0.0, 12.0), height=5.0, doors=[
        ("south", 0.0, 4.0, 4.0),
        ("west", 0.0, 4.0, 4.0),
        ("east", 0.0, 4.0, 4.0),
        ("north", 0.0, 6.0, 5.0),
    ])
    k.lamp((0.0, 4.2, -8.0), name="cross_lamp", intensity=6.0, rng=16.0)
    k.pillar((-5.0, 2.5, -4.0), size=(1.2, 5.0, 1.2))
    k.pillar((5.0, 2.5, -4.0), size=(1.2, 5.0, 1.2))
    k.pickup("health", (0.0, 0.8, -4.0), amount=25)

    # The door that wants both. It is the first thing seen on arriving, which
    # is the crypt's lesson used rather than taught again.
    k.door("vault_door", (0.0, 2.5, -14.0), key="brass",
           size=(6.0, 5.0, 1.0), travel=(0.0, 4.6, 0.0))
    k.door("vault_inner", (0.0, 2.5, -17.0), key="iron",
           size=(6.0, 5.0, 1.0), travel=(0.0, 4.6, 0.0))

    # ── West wing: corners, runners, and a platform over a drop. ────────────
    k.corridor((-7.0, 0.0, -8.0), (-13.0, 0.0, -8.0), width=4.0, height=4.0,
               doors=[("east", 0.0, 4.0, 4.0), ("west", 0.0, 4.0, 4.0)])
    k.room(WEST, (14.0, 0.0, 14.0), doors=[("east", 0.0, 4.0, 4.0)])
    k.torch((-25.4, 2.8, -8.0), name="west_far", yaw=1.5708)
    k.torch((-20.0, 2.8, -14.4), name="west_north")
    k.pillar((-16.0, 2.0, -12.0))
    k.pillar((-24.0, 2.0, -4.0))
    k.monster("runner", (-22.0, 1.0, -12.0))
    k.monster("runner", (-17.0, 1.0, -4.0))
    # The platform, alone in its wing so it is met on its own.
    k.platform("west_ferry", (-20.0, 0.3, -8.0), travel=(0.0, 0.0, -4.0))
    k.pickup("shells", (-24.0, 0.8, -11.0), amount=8)
    k.key("brass", (-20.0, 0.9, -13.0))

    # ── East wing: length, shooters, and the ammunition to answer them. ─────
    k.corridor((7.0, 0.0, -8.0), (13.0, 0.0, -8.0), width=4.0, height=4.0,
               doors=[("west", 0.0, 4.0, 4.0), ("east", 0.0, 4.0, 4.0)])
    k.room(EAST, (14.0, 0.0, 20.0), doors=[("west", 0.0, 4.0, 4.0)])
    k.torch((25.4, 2.8, -2.0), name="east_near", yaw=-1.5708)
    k.torch((25.4, 2.8, -14.0), name="east_far", yaw=-1.5708)
    k.pillar((17.0, 2.0, -6.0))
    k.pillar((23.0, 2.0, -10.0))
    k.monster("shooter", (20.0, 1.0, -15.0))
    k.monster("shooter", (24.0, 1.0, -2.0))
    k.monster("runner", (16.0, 1.0, -12.0))
    k.pickup("bullets", (17.0, 0.8, -2.0), amount=20)
    k.pickup("armour", (24.0, 0.8, -16.0), amount=25)
    k.key("iron", (20.0, 0.9, -16.0))

    # ── The shaft: a button, a lift, and the way down. ──────────────────────
    k.corridor((0.0, 0.0, -15.0), (0.0, 0.0, -20.0), width=6.0, height=5.0,
               doors=[("north", 0.0, 6.0, 5.0), ("south", 0.0, 6.0, 5.0)])
    k.room(SHAFT, (12.0, 0.0, 12.0), height=8.0,
           doors=[("south", 0.0, 6.0, 5.0)])
    k.torch((-5.4, 3.0, -26.0), name="shaft_west", yaw=1.5708,
            colour=(0.55, 0.78, 1.0), intensity=5.0)
    k.lift("shaft_lift", (0.0, 0.25, -28.0), size=(3.0, 0.5, 3.0),
           travel=(0.0, 4.0, 0.0), speed=1.4, wait=5.0)
    k.button("shaft_lift", (0.0, 1.5, -31.4), size=(0.7, 0.7, 0.25))
    k.pickup("health", (-4.0, 0.8, -23.0), amount=25)
    k.exit_at("deeper", (0.0, 5.0, -28.0))

    k.write("vaults.json", name="The Vaults",
            next_level="assets/levels/deep.json", tool=TOOL)


if __name__ == "__main__":
    build()
