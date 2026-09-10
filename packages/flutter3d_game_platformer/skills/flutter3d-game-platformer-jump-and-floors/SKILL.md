---
name: flutter3d-game-platformer-jump-and-floors
description: Use when building a platformer on flutter3d — the runner's jump policy, surfaces as a table, the furniture entity kinds, and where a change belongs.
---

# A jump with a memory, and floors that differ by table

```dart
final sim = PlatformerSimulation(…);
sim.step(dt);          // input, jump, movement, riders, hazards, pickups, exits
```

| | |
|---|---|
| `Runner`, `RunnerTuning` | coyote time, jump buffering, a second jump, a dash, dropping through a one-way floor |
| `Surfaces` | ice, moss and mud as a table on the brushes |
| `Purse`, `Collectible` | what is picked up, and the total at the end |
| `Crate`, `Spring`, `Hazard`, `Checkpoint`, `Patrol`, `Leaper` | the furniture, each an entity kind the level format spawns |
| `FollowCamera` | leads, kicks, shakes, widens, and answers reduce-motion |

Everything else comes unchanged from `flutter3d_game`: the fixed step, the
character controller, the level format and validator, the entity registry,
mechanisms, movers, riders, exits, health, the ECS and the snapshot.

## Tune the jump, do not rewrite it

`RunnerTuning` is where a jump's feel lives, and each of coyote time, buffering,
the second jump, the dash and the one-way drop is a number with a test beside
it. Changing the numbers is the intended way to make a different game; changing
the order inside `Runner.step` is how forgiveness stops being reproducible.

**The forgiveness a jump needs is not something a screenshot can show, and it is
the part players feel first.** Test it as steps and positions — no import here
reaches the renderer, so every test file runs with no device.

## Surfaces are data on the brushes

Ice, moss and mud are entries in `Surfaces`, read from the level's own surface
table, and a new surface is a row. `if (material == 'ice')` in a simulation is
what the table exists to prevent, because the second such branch never lands in
the same file as the first.

## Where a change belongs

If a platformer feature seems to need a change in `flutter3d_game`, ask whether
it is machinery (belongs below, with no genre word in it) or vocabulary (belongs
here). The `no package names a genre` structure rule settles the argument.

That boundary is what this package was built to test: a game that is not a
shooter, with no edit in the engine's `lib/src/`. Sketching it found five
hardcoded assumptions in input, all fixed rather than worked around, which is
why the engine below has no idea what a coin is.
