#!/usr/bin/env python3
"""The fifth level: the sanctum, and the end of the game.

    python3 tool/make_sanctum.py

The biggest level and the last one, and it is built on the rule the other four
each taught one piece of: **everything the player has learned, at once, in a
room large enough to use all of it.** The crypt's locked door, the vaults'
two keys, the deep's choice of weapon and the cistern's high ground are all
here, and none of them is explained again.

    [ vestibule ] —— [ n a v e ] —— brass, then iron —— [ choir ] —— [ altar hall ]
       spawn        pillars, six                        ambush        the last fight
                    /         \\                                        exit, on the dais
         [ reliquary ]     [ wardens' crypt ]
          brass key         iron key
              |
          (secret)

The nave is a hall with a colonnade, wide enough that the rocket launcher is
the right answer and long enough that the shooters at the far end get their
shots off first. The chapels are the two keys, one guarded by shooters and one
by tanks, so the order they are taken in changes which weapon is low on
ammunition at the door. The choir is a small room after a big one, which is
the deep's lesson used as an ambush. And the altar hall is the fight the game
was building towards: three tanks on a raised dais with the way out behind
them, shooters on the floor either side, and enough rockets on the way in to
answer it — if the player kept any.

**No `next`.** This is the end of the game, and the application says so.
"""

import cryptkit as k

TOOL = "apps/flutter3d_demo_dungeon/tool/make_sanctum.py"

VESTIBULE = (0.0, 0.0, 14.0)
NAVE = (0.0, 0.0, -8.0)
RELIQUARY = (-21.0, 0.0, -12.0)
HIDDEN = (-19.0, 0.0, -21.0)
WARDENS = (21.0, 0.0, -12.0)
CHOIR = (0.0, 0.0, -33.0)
ALTAR = (0.0, 0.0, -58.0)

#: Candlelight for the hall, whiter than a torch; the game's end is the one
#: place it is allowed to be bright.
CANDLE = (1.0, 0.85, 0.55)
DAWN = (0.55, 0.78, 1.0)


def build():
    k.start()

    # ── The vestibule. ─────────────────────────────────────────────────────
    k.room(VESTIBULE, (10.0, 0.0, 8.0), doors=[("north", 0.0, 4.0, 4.0)])
    k.spawn((0.0, 0.0, 16.0))
    k.torch((-4.4, 2.8, 14.0), name="vestibule_west", yaw=1.5708)
    k.torch((4.4, 2.8, 14.0), name="vestibule_east", yaw=-1.5708)
    k.note(
        (-3.5, 1.6, 10.03),
        "Two wardens kept the sanctum, and they kept its keys apart, "
        "as they always did. What they kept it from is still in it.",
    )
    k.pickup("health", (3.0, 0.8, 12.0), amount=25)
    k.corridor((0.0, 0.0, 9.0), (0.0, 0.0, 5.0), width=4.0, height=4.0,
               doors=[("north", 0.0, 4.0, 4.0), ("south", 0.0, 4.0, 4.0)])

    # ── The nave. A colonnade, two chapels off it, the great door ahead. ───
    k.room(NAVE, (28.0, 0.0, 24.0), height=7.0, doors=[
        ("south", 0.0, 4.0, 4.0),
        ("west", -4.0, 4.0, 4.0),     # the reliquary
        ("east", -4.0, 4.0, 4.0),     # the wardens' crypt
        ("north", 0.0, 8.0, 5.0),     # the great door
    ])
    for x in (-6.0, 6.0):
        for z in (-16.0, -10.0, -4.0):
            k.pillar((x, 3.5, z), size=(1.6, 7.0, 1.6))
    k.lamp((0.0, 6.2, -14.0), name="nave_north", colour=CANDLE,
           intensity=7.0, rng=20.0)
    k.lamp((0.0, 6.2, -2.0), name="nave_south", colour=CANDLE,
           intensity=7.0, rng=20.0)
    k.torch((-13.4, 3.0, -4.0), name="nave_southwest", yaw=1.5708)
    k.torch((13.4, 3.0, -4.0), name="nave_southeast", yaw=-1.5708)
    k.torch((-13.4, 3.0, -16.0), name="nave_northwest", yaw=1.5708)
    k.torch((13.4, 3.0, -16.0), name="nave_northeast", yaw=-1.5708)
    # The shooters are at the far end, behind the door they cover; the tank
    # is in the middle, where the columns are cover from it and not from them.
    k.monster("tank", (0.0, 0.0, -12.0))
    k.monster("shooter", (-10.0, 0.0, -18.0))
    k.monster("shooter", (10.0, 0.0, -18.0))
    k.monster("runner", (-10.0, 0.0, -2.0))
    k.monster("runner", (10.0, 0.0, -2.0))
    k.monster("runner", (0.0, 0.0, -17.0))
    k.pickup("health", (-12.0, 0.8, 2.0), amount=25)
    k.pickup("shells", (12.0, 0.8, 2.0), amount=8)
    k.pickup("bullets", (-3.0, 0.8, -7.0), amount=20)
    k.pickup("armour", (3.0, 0.8, -7.0), amount=25)

    # The great door, seen from the vestibule's doorway the length of the
    # nave away. Two locks in one passage, the way the vaults did it.
    k.door("sanctum_door", (0.0, 2.5, -20.0), key="brass",
           size=(8.0, 5.0, 1.0), travel=(0.0, 4.6, 0.0))
    k.trigger("sanctum_door", (0.0, 1.5, -18.4), size=(8.0, 3.0, 2.0))
    k.door("sanctum_inner", (0.0, 2.5, -24.0), key="iron",
           size=(8.0, 5.0, 1.0), travel=(0.0, 4.6, 0.0))
    k.trigger("sanctum_inner", (0.0, 1.5, -22.4), size=(8.0, 3.0, 2.0))

    # ── The reliquary, west: shooters, the brass key, and the secret. ──────
    k.room(RELIQUARY, (12.0, 0.0, 10.0), doors=[
        ("east", 0.0, 4.0, 4.0),
        ("north", 3.0, 1.2, 2.4),     # the secret, behind the column
    ])
    k.torch((-26.4, 2.8, -9.0), name="reliquary_west", yaw=1.5708)
    k.torch((-21.0, 2.8, -7.6), name="reliquary_south", yaw=3.1416)
    # A column a metre and a half off the north wall: the opening is behind
    # it from the door, and there is room to walk round.
    k.pillar((-18.0, 2.0, -15.0))
    k.monster("tank", (-22.0, 0.0, -12.0))
    k.monster("shooter", (-25.0, 0.0, -9.0))
    k.monster("shooter", (-25.0, 0.0, -15.0))
    k.pickup("armour", (-16.0, 0.8, -8.0), amount=25)
    k.pickup("shells", (-26.0, 0.8, -16.0), amount=8)
    k.key("brass", (-26.0, 0.9, -12.0))

    k.room(HIDDEN, (6.0, 0.0, 6.0), height=3.0,
           doors=[("south", 1.0, 1.2, 2.4)])
    k.torch((-21.4, 2.0, -21.0), name="hidden", yaw=1.5708, colour=CANDLE,
            intensity=3.5, rng=8.0)
    k.secret((-19.0, 1.25, -21.0))
    k.pickup("rockets", (-19.0, 0.8, -22.0), amount=8)
    k.pickup("armour", (-17.0, 0.8, -22.0), amount=25)
    k.pickup("health", (-21.0, 0.8, -22.0), amount=25)

    # ── The wardens' crypt, east: tanks, and the iron key on a dais. ───────
    k.room(WARDENS, (12.0, 0.0, 10.0), doors=[("west", 0.0, 4.0, 4.0)])
    k.torch((26.4, 2.8, -9.0), name="wardens_northeast", yaw=-1.5708)
    k.torch((26.4, 2.8, -15.0), name="wardens_southeast", yaw=-1.5708)
    k.pillar((18.0, 2.0, -9.0))
    k.pillar((18.0, 2.0, -15.0))
    k.block((25.0, 0.15, -12.0), (3.0, 0.3, 3.0), "stone")
    k.monster("tank", (22.0, 0.0, -9.0))
    k.monster("tank", (22.0, 0.0, -15.0))
    k.monster("shooter", (18.0, 0.0, -12.0))
    k.pickup("shells", (16.0, 0.8, -8.0), amount=8)
    k.pickup("health", (26.0, 0.8, -8.0), amount=25)
    k.pickup("bullets", (26.0, 0.8, -16.0), amount=20)
    k.key("iron", (25.0, 1.2, -12.0))

    # ── Through both locks: the choir, small after the nave. ───────────────
    k.corridor((0.0, 0.0, -21.0), (0.0, 0.0, -27.0), width=8.0, height=5.0,
               doors=[("north", 0.0, 8.0, 5.0), ("south", 0.0, 8.0, 5.0)])
    k.room(CHOIR, (16.0, 0.0, 10.0), height=5.0, doors=[
        ("south", 0.0, 8.0, 5.0),
        ("north", 0.0, 6.0, 5.0),
    ])
    k.lamp((0.0, 4.2, -33.0), name="choir_lamp", colour=CANDLE,
           intensity=5.0, rng=14.0)
    k.pillar((-4.0, 2.5, -33.0), size=(1.2, 5.0, 1.2))
    k.pillar((4.0, 2.5, -33.0), size=(1.2, 5.0, 1.2))
    k.monster("shooter", (-6.0, 0.0, -36.0))
    k.monster("shooter", (6.0, 0.0, -36.0))
    k.monster("runner", (-6.0, 0.0, -30.0))
    k.monster("runner", (6.0, 0.0, -30.0))
    k.pickup("rockets", (0.0, 0.8, -33.0), amount=4)
    k.pickup("health", (-7.0, 0.8, -33.0), amount=25)
    k.pickup("armour", (7.0, 0.8, -33.0), amount=25)

    # ── The altar hall. ────────────────────────────────────────────────────
    k.corridor((0.0, 0.0, -39.0), (0.0, 0.0, -43.0), width=6.0, height=5.0,
               doors=[("north", 0.0, 6.0, 5.0), ("south", 0.0, 6.0, 5.0)])
    k.room(ALTAR, (32.0, 0.0, 28.0), height=9.0,
           doors=[("south", 0.0, 6.0, 5.0)])
    for x in (-9.0, 9.0):
        for z in (-48.0, -54.0, -60.0, -66.0):
            k.pillar((x, 4.5, z), size=(1.8, 9.0, 1.8))
    k.lamp((0.0, 8.2, -50.0), name="altar_south", colour=CANDLE,
           intensity=9.0, rng=24.0)
    k.lamp((0.0, 8.2, -64.0), name="altar_north", colour=CANDLE,
           intensity=9.0, rng=24.0)
    k.torch((-15.4, 3.5, -48.0), name="altar_southwest", yaw=1.5708)
    k.torch((15.4, 3.5, -48.0), name="altar_southeast", yaw=-1.5708)
    k.torch((-15.4, 3.5, -68.0), name="altar_northwest", yaw=1.5708)
    k.torch((15.4, 3.5, -68.0), name="altar_northeast", yaw=-1.5708)
    # The light the way out stands in, on the far wall behind the dais.
    k.torch((0.0, 3.0, -71.4), name="dawn", colour=DAWN, intensity=6.0,
            rng=16.0)

    # The dais: three steps, each under the step height, stacked rather than
    # nested so no two brushes share a volume.
    k.block((0.0, 0.15, -64.0), (16.0, 0.3, 12.0), "stone")
    k.block((0.0, 0.45, -64.0), (14.0, 0.3, 10.0), "stone")
    k.block((0.0, 0.75, -64.0), (12.0, 0.3, 8.0), "stone")

    # The last fight. Tanks on the dais between the player and the way out;
    # shooters on the floor either side, where a rocket at the dais does not
    # reach them; runners at the door, so nobody stands in it and reloads.
    k.monster("tank", (-4.0, 0.9, -65.0))
    k.monster("tank", (4.0, 0.9, -65.0))
    k.monster("tank", (0.0, 0.9, -62.0))
    k.monster("shooter", (-12.0, 0.0, -66.0))
    k.monster("shooter", (12.0, 0.0, -66.0))
    k.monster("shooter", (0.0, 0.0, -71.0))
    k.monster("runner", (-13.0, 0.0, -47.0))
    k.monster("runner", (13.0, 0.0, -47.0))
    k.pickup("rockets", (-6.0, 0.8, -46.0), amount=4)
    k.pickup("rockets", (6.0, 0.8, -46.0), amount=4)
    k.pickup("health", (-14.0, 0.8, -56.0), amount=25)
    k.pickup("health", (14.0, 0.8, -56.0), amount=25)
    k.pickup("armour", (0.0, 0.8, -50.0), amount=25)
    k.pickup("shells", (-14.0, 0.8, -62.0), amount=8)
    k.pickup("bullets", (14.0, 0.8, -62.0), amount=20)
    # On the top of the dais, which is where the tanks are standing.
    k.exit_at("the_light", (0.0, 0.9, -66.0))

    # No `next_level`: this is the end of the game.
    k.write("sanctum.json", name="The Sanctum", tool=TOOL)


if __name__ == "__main__":
    build()
