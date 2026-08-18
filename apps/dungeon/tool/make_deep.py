#!/usr/bin/env python3
"""The third level: the deep.

    python3 tool/make_deep.py

The last one, and the only one that asks a question the first two did not:
**which weapon**, and it asks it by taking away the freedom to answer wrong.

The crypt is a corridor and the vaults are a choice of order. Here the rooms are
small, the tanks are slow and hard, and the ammunition on the floor is less than
the fight in front of it. A rocket in a room this size hurts the person who
fired it — the blast reaches everything in the radius including the player — so
the launcher stops being the obvious answer and the shotgun starts being one.

That is the whole design, and it is why this level has no keys, no lift and no
crossroads. Everything it has to say is said by the shape of the rooms and by
what is not lying about in them.

**No `next`.** This is the end of the game, and the application says so.
"""

import cryptkit as k

TOOL = "apps/dungeon/tool/make_deep.py"

ARRIVAL = (0.0, 0.0, 4.0)
FIRST = (0.0, 0.0, -8.0)
NARROW = (0.0, 0.0, -20.0)
LAST = (0.0, 0.0, -34.0)


def build():
    k.start()

    # ── Arrival. Small, and the only quiet room in the level. ───────────────
    k.room(ARRIVAL, (8.0, 0.0, 8.0), height=3.5,
           doors=[("north", 0.0, 3.0, 3.0)])
    k.spawn((0.0, 0.0, 6.0))
    k.torch((-3.4, 2.4, 5.0), name="arrival_west", yaw=1.5708,
            colour=(0.55, 0.78, 1.0), intensity=4.5)
    k.note(
        (0.0, 1.6, 0.6),
        "Nothing below here was buried. It came down on its own.",
    )
    k.pickup("shells", (2.5, 0.8, 6.0), amount=8)

    # ── The first room. One tank, and nowhere to back away to. ─────────────
    k.corridor((0.0, 0.0, -0.5), (0.0, 0.0, -3.0), width=3.0, height=3.0,
               doors=[("north", 0.0, 3.0, 3.0), ("south", 0.0, 3.0, 3.0)])
    k.room(FIRST, (10.0, 0.0, 8.0), height=3.5,
           doors=[("south", 0.0, 3.0, 3.0), ("north", 0.0, 3.0, 3.0)])
    k.torch((4.4, 2.4, -8.0), name="first_east", yaw=-1.5708, intensity=4.0)
    k.pillar((0.0, 1.75, -10.0), size=(1.6, 3.5, 1.6))
    # Behind the pillar, so the room is entered before it is seen.
    k.monster("tank", (0.0, 1.0, -11.0))
    k.pickup("health", (-4.0, 0.8, -6.0), amount=25)

    # ── The narrows. Two rooms wide enough to fight in and no more. ─────────
    k.corridor((0.0, 0.0, -12.5), (0.0, 0.0, -15.0), width=3.0, height=3.0,
               doors=[("north", 0.0, 3.0, 3.0), ("south", 0.0, 3.0, 3.0)])
    k.room(NARROW, (12.0, 0.0, 10.0), height=3.5, doors=[
        ("south", 0.0, 3.0, 3.0),
        ("north", 0.0, 3.0, 3.0),
    ])
    k.torch((-5.4, 2.4, -17.0), name="narrow_west", yaw=1.5708, intensity=4.0)
    k.torch((5.4, 2.4, -23.0), name="narrow_east", yaw=-1.5708, intensity=4.0)
    k.pillar((-3.0, 1.75, -20.0), size=(1.4, 3.5, 1.4))
    k.pillar((3.0, 1.75, -20.0), size=(1.4, 3.5, 1.4))
    k.monster("tank", (-4.0, 1.0, -23.0))
    k.monster("shooter", (4.0, 1.0, -17.0))
    k.monster("runner", (4.0, 1.0, -23.0))
    # The only bullets in the level, and not enough of them. The shells behind
    # you are the answer, which is the point.
    k.pickup("bullets", (0.0, 0.8, -17.0), amount=20)

    # ── The last room. Everything at once, and the way out behind it. ──────
    k.corridor((0.0, 0.0, -25.5), (0.0, 0.0, -28.0), width=3.0, height=3.0,
               doors=[("north", 0.0, 3.0, 3.0), ("south", 0.0, 3.0, 3.0)])
    k.room(LAST, (16.0, 0.0, 12.0), height=5.0,
           doors=[("south", 0.0, 3.0, 3.0)])
    k.lamp((0.0, 4.2, -34.0), name="last_lamp", colour=(0.55, 0.78, 1.0),
           intensity=6.0, rng=18.0)
    k.pillar((-5.0, 2.5, -31.0), size=(1.4, 5.0, 1.4))
    k.pillar((5.0, 2.5, -31.0), size=(1.4, 5.0, 1.4))
    k.monster("tank", (-6.0, 1.0, -37.0))
    k.monster("tank", (6.0, 1.0, -37.0))
    k.monster("shooter", (0.0, 1.0, -38.0))
    # Rockets, here and nowhere else. A room five metres high and sixteen wide
    # is the first place in the game where firing one is not also hitting
    # yourself — the level teaches the weapon by being the first room that
    # affords it.
    k.pickup("rockets", (0.0, 0.8, -30.0), amount=4)
    k.pickup("armour", (-7.0, 0.8, -30.0), amount=25)
    k.exit_at("the_surface", (0.0, 2.4, -39.0))

    # No `next_level`: this is the end of the game.
    k.write("deep.json", name="The Deep", tool=TOOL)


if __name__ == "__main__":
    build()
