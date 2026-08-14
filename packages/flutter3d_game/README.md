# flutter3d_game

The game layer: a simulation that runs at a fixed rate, input that has
forgotten which device it came from, a level format with a validator, and the
mechanisms a level is built out of.

**It does not depend on `flutter3d`.** Simulation, input and collision have
nothing to say about how a frame is drawn, and keeping the two apart is what
lets the parts that fail quietly be reached from a plain unit test — a
collision that passes through a wall once in a thousand steps, a jump that is a
different height on a faster monitor, a press swallowed at a low frame rate.
None of those are visible in a screenshot. `flutter3d_bridge` is where this
meets the renderer.

Only one file imports Flutter: `src/input/desktop_input.dart`, because a key
event is a Flutter type. Everything else is plain Dart over `vector_math`.

## What is here

| Directory | What it holds |
|---|---|
| `loop/` | `FixedStep` (accumulator, `alpha`, dropped steps), `GameLoop`, `InterpolatedVector3`/`InterpolatedAngle` |
| `input/` | `GameAction`, `InputState` (latched edges, analogue axis, look delta), `DesktopInput` |
| `level/` | `Level` format v1, `EntityKind` and its registry, `LevelValidator`, brush→geometry, `SpawnContext` |
| `world/` | `Mechanism`, `Signal`, `Mover` (door, lift, platform), `Button`, `TriggerVolume`, `Pickup`, `Gift`, `Inventory`, `LightFixture` |
| `combat/` | `WeaponDef` and `Arsenal`, hitscan, projectiles, blast |
| `actors/` | `Health`, `MonsterDef`, `MonsterSystem` |
| `physics/` | Only the layer names. Collision itself is [`flutter3d_physics`](../flutter3d_physics), a plain Dart package |

## The order a step runs in

This is the part that is easy to get wrong and hard to notice, so it is written
down here as well as in the code:

```
mechanisms.step(dt)          // doors and lifts move
collision.reindex()          // ... and the broadphase learns where they are
body.step(dt, …)             // then the player sweeps against them
collision.update()
collision.clearKinematicDeltas()
```

Two bugs that ordering prevents, both of which look like physics faults and are
not:

- **A lift indexed one step late is a lift you can walk through.** Move
  `reindex()` after `body.step` and the player sweeps against where the lift
  *was*.
- **A lift that has not moved yet cannot carry you.** Clear the kinematic deltas
  before the body steps and a passenger stops riding.

## Layers

`CollisionLayers` names the bits — `world`, `player`, `monster`, `pickup`,
`trigger`. The names live here rather than in `flutter3d_physics` because a
collision world that knows what a monster is cannot be used by a game that has
none. The physics package keeps the rule (two colliders meet when each is in
the other's mask) and `Layers.all`.

These five are a default, not a law: a game with vehicles or water adds bits
six upwards, and nothing in either package reads the names.

## What it does not do

Stated rather than discovered:

- **No navigation.** Monsters see the player, turn, and walk straight at them.
  They get stuck on corners.
- **No pause, no game-over, no level transition.** `Level.next` is a field
  nothing reads and `exit` is an entity that spawns nothing.
- **No player abstraction.** Yaw, pitch and eye height belong to the
  application; `CharacterController` is a body without a head.
- **No rigid bodies.** Deliberate — nothing pushes the player and the player has
  no angular momentum.
- **Desktop input only.** `InputState` is device-agnostic and
  `setStickAxis` is the seam a gamepad or touch backend writes to; no such
  backend exists yet.
- **It still ships this game's roster.** Three monsters, four weapons and
  fourteen entity types, three of which — `torch`, `lamp`, `window` — are
  content rather than vocabulary. A second game inherits them today.

## Tests

```
flutter test                       # in this directory
dart test                          # in ../flutter3d_physics — no Flutter needed
```

Every subsystem has tests. The four that had none — `GameLoop`, `DesktopInput`,
`LightFixture` and `SpawnContext.onFixture` — were covered by writing each test
against the claim its doc comment makes and then breaking the code to watch it
fail. One of those first attempts passed against a deliberately broken
implementation, because it was asserting a guarantee `EntityDef` makes rather
than the one `Fixture` makes; it is rewritten and the reason is in the file.
