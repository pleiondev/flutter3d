#!/usr/bin/env python3
"""The first level: the crypt.

    python3 tool/make_crypt.py

**This document used to be written by hand, and it was a showcase rather than a
level.** Thirty-five brushes and twenty-one entities, of which there was exactly
one of every kind the format has — one door, one lift, one button, one trigger,
one platform, one note. That is what you build to prove a format works, and it
is not what you build to start a game with.

What a first level has to do is teach, in the order a player can absorb it:

1. **Walk and look.** A hall with nothing in it but light, so the first thing
   anybody does is turn round and find they can.
2. **Shoot.** One runner in a room you can see all of, at a distance that gives
   you time to raise the gun.
3. **A locked door**, seen *before* the key, so that finding the key later means
   something. Every game teaches this the same way and it only works in that
   order.
4. **Look somewhere that is not the way forward.** The key is down a side
   passage, guarded, and the passage is visible from the hall — a player who
   never turns off the corridor is a player the second level will lose.
5. **Use the key, and leave.**

Nothing here is a mechanism the player has to be told about. The lift, the
button and the moving platform are the *second* level's lesson, and putting one
of each in the first one is how the old document came to have twenty-one
entities and no shape.

Run it again and the file is identical; that is what makes it a generator
rather than a description of what somebody once did.
"""

import cryptkit as k

TOOL = "apps/dungeon/tool/make_crypt.py"

# The plan, in metres. North is −Z: the player spawns facing up this page.
#
#                         [ vault ]  key, guarded
#                              |
#   [ hall ] —— [ guard room ] —— locked door —— [ stair ] —— exit
#    spawn
HALL = (0.0, 0.0, 8.0)
GUARD = (0.0, 0.0, -8.0)
VAULT = (14.0, 0.0, -8.0)
STAIR = (0.0, 0.0, -26.0)


def build():
    k.start()

    # ── The hall. Light, and nothing else. ──────────────────────────────────
    k.room(HALL, (12.0, 0.0, 12.0), doors=[("north", 0.0, 4.0, 4.0)])
    k.spawn((0.0, 0.0, 12.0))
    k.torch((-5.4, 2.8, 10.0), name="hall_west", yaw=1.5708)
    k.torch((5.4, 2.8, 10.0), name="hall_east", yaw=-1.5708)
    # **On the wall, beside the doorway.** It used to hang at (0, 1.6, 2.6) —
    # in the middle of the opening, two metres from anything, in mid-air. That
    # went unnoticed for as long as the game was the only thing looking at this
    # level: a note is read, not drawn, so nothing ever put a page there. The
    # editor draws one now, and a page floating in a doorway is the first thing
    # anybody sees.
    #
    # The hall's north wall runs at z = 1.5 and is a metre thick, so its inner
    # face is z = 2.0; the doorway takes x from −2 to 2, and this sits on the
    # panel west of it, facing into the room.
    k.note(
        (-3.5, 1.6, 2.03),
        "They sealed the lower door and took the key down with them. "
        "It is still down there.",
    )

    # ── The corridor between hall and guard room. ───────────────────────────
    k.corridor((0.0, 0.0, 2.0), (0.0, 0.0, -2.0), width=4.0, height=4.0,
               doors=[("north", 0.0, 4.0, 4.0), ("south", 0.0, 4.0, 4.0)])

    # ── The guard room. One runner, seen from the doorway. ──────────────────
    k.room(GUARD, (16.0, 0.0, 12.0), doors=[
        ("south", 0.0, 4.0, 4.0),   # back to the hall
        ("north", 0.0, 6.0, 5.0),   # the locked door
        ("east", 0.0, 3.0, 3.0),    # the side passage
    ])
    k.torch((-7.4, 2.8, -8.0), name="guard_west", yaw=1.5708)
    k.torch((7.4, 2.8, -12.0), name="guard_east", yaw=-1.5708, intensity=5.0)
    k.pillar((-4.0, 2.0, -10.0))
    k.pillar((4.0, 2.0, -10.0))
    # Far enough that the pistol is the right answer and the fists are not.
    k.monster("runner", (0.0, 1.0, -12.0))
    k.pickup("health", (-6.0, 0.8, -5.0), amount=25)

    # **The door before the key.** It is straight ahead of the way in, so it is
    # the first thing seen on entering and the reason to go looking.
    # **Six metres wide, and the width is not decoration.** At four the route
    # from the vault arrives along the north wall on a diagonal and the player
    # ends up wedged in the corner between the wall and the door's own edge —
    # a flow field aims at the goal, not at the opening. A doorway wide enough
    # to be arrived at sideways is a doorway a player never notices.
    k.door("crypt_door", (0.0, 2.5, -14.0), key="iron",
           size=(6.0, 5.0, 1.0), travel=(0.0, 4.6, 0.0))
    k.trigger("crypt_door", (0.0, 1.5, -12.4), size=(4.0, 3.0, 2.0))

    # ── The vault, through the guard room's east wall. ──────────────────────
    #
    # **No corridor between them, and that is the point of `room`'s geometry.**
    # Two rooms whose walls land on the same plane share it, so an opening cut
    # from each side is one opening. The first draft put a two-metre corridor in
    # the gap and got four walls where it wanted none — the player could see
    # straight through and could not walk through.
    k.room(VAULT, (10.0, 0.0, 10.0), doors=[("west", 0.0, 3.0, 3.0)])
    k.torch((14.0, 2.8, -12.4), name="vault_north")
    # Guarded, and by the one that shoots: the side passage is where a player
    # learns that a corridor is cover.
    k.monster("shooter", (16.0, 1.0, -10.0))
    k.pickup("bullets", (11.0, 0.8, -6.0), amount=20)
    k.key("iron", (14.0, 0.9, -8.0))

    # ── Down, and out. ─────────────────────────────────────────────────────
    k.corridor((0.0, 0.0, -15.0), (0.0, 0.0, -20.0), width=4.0, height=4.0,
               doors=[("north", 0.0, 4.0, 4.0), ("south", 0.0, 4.0, 4.0)])
    k.room(STAIR, (10.0, 0.0, 12.0), height=6.0,
           doors=[("south", 0.0, 4.0, 4.0)])
    k.torch((-4.4, 3.0, -28.0), name="stair_west", yaw=1.5708,
            colour=(0.55, 0.78, 1.0), intensity=5.0)
    k.pickup("armour", (3.0, 0.8, -24.0), amount=25)
    k.exit_at("way_down", (0.0, 2.4, -30.0))

    k.write("crypt.json", name="The Crypt", next_level="assets/levels/vaults.json",
            tool=TOOL)


if __name__ == "__main__":
    build()
