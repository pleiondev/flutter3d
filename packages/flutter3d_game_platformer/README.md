# flutter3d_game_platformer

A jump with a memory, a purse, a crate to push, and the floors all of it happens
on.

## Why it exists at all

This package is the instrument that tested the engine. SPEC stage 5 asks for "a
game that is not a shooter, without a single edit in `lib/src/`", and the value
was never the game: **it was what the attempt found.** Three hardcoded object
types had already been dug out of the engine by imagining this one, and
sketching it for real found five more, all in input. They were fixed rather than
worked around, which is why the engine below has no idea what a coin is.

What it needed from the engine and got unchanged: the fixed step, the character
controller, the level format and its validator, the entity registry, mechanisms,
movers, riders, exits, health, the ECS and the snapshot. What it had to bring
itself is the list below.

## What is in it

| | |
|---|---|
| `PlatformerSimulation` | The step order: input, jump, movement, riders, hazards, collectibles, exits. |
| `Runner`, `RunnerTuning` | The jump policy — coyote time, jump buffering, a second jump, a dash, a drop through a one-way floor. |
| `Surfaces` | What a floor is made of. Ice, moss and mud are a table on the brushes, not three special cases. |
| `Purse`, `Collectible` | What is picked up and what the total is at the end. |
| `Crate`, `Spring`, `Hazard`, `Checkpoint`, `Patrol`, `Leaper` | The furniture and the things that walk about in it, each one an entity kind the level format spawns. |
| `FollowCamera` | A camera that leads, kicks, shakes and widens — and answers reduce-motion. |

## Nothing here draws

No import reaches the renderer, so every one of the thirteen test files runs in
a test with no device. The forgiveness a jump needs is not something a
screenshot can show, and it is the part players feel first.

---

Part of [flutter3d](https://github.com/pleiondev/flutter3d), an **independent
implementation** of a 3D engine for Flutter — not a fork or a binding of
another engine, and not affiliated with the Flutter team.
Documentation: <https://flutter3d.pleion.dev>.
