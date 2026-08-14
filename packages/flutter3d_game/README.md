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

## Content lives in the game, not here

`lib/src/` contains no monsters, no weapons, no pickups and no furniture — and,
more to the point, **no opinion about whether a game has any**. The package
offers kinds; a game composes the vocabulary it speaks:

```dart
final kinds = EntityRegistry(<EntityKind>[
  const PlayerSpawnKind(),
  const DoorKind(),
  MonsterKind(myMonsters),   // only if this game has monsters
  MyOwnKind(),               // and whatever it invents
]);
```

The same registry validates a level and spawns it, so the two cannot disagree
about what a document may contain. `LevelValidator` and `Level.spawnInto`
require it — there is no default a package can honestly give.

Rules about a level *as a whole* work the same way. The validator once required
exactly one `player_spawn` and warned about a missing `exit`; those are a
shooter's rules, not the format's, so they are `LevelRule`s a game passes in.
What the validator still checks by itself is true of any level whatever the
game is: names unique, references resolving, brushes not degenerate, something
to stand on, something to see by.

`lib/sample.dart` holds the roster this repository's own game uses. It is
**not** exported from `flutter3d_game.dart`: a game gets none of it unless it
asks by name. It stays in the package for the tests, two hundred of which are
written against those numbers.

## Who a collider is

`Collider.userData` answers one question — *who is this?* — and one only. It
used to answer two: a monster on one collider and the player's *inventory* on
another, which is what the body carries rather than who it is. That is why
dealing damage took two branches, one testing `userData` and one testing the
collider's layer, and why neither could have been written by a game with a
third thing worth shooting.

`Damageable` replaces both with one question. A monster implements it by handing
the call back to the system that spawned it — subtracting from its own health
would leave a corpse that still blocks the corridor and a death nothing counted.

## Events

Each system fills a list during the step and a caller drains it after —
`MonsterSystem.died` and `hurtThisStep`, `ProjectileSystem.detonations`, and
`MechanismWorld.events` once `publish()` has been called.

Lists rather than streams, and the reason is the fixed step: a `Stream`
delivers *after* the step that produced the event, which is the one property
this package exists to protect. A list cleared at the top of each step is
synchronous, typed, and allocates nothing.

**Each mechanism reports itself** — `Mechanism.collect` — rather than the world
type-testing its members. That is the same rule `Gift` and `EntityKind` already
follow, and it is what lets a game's own mechanism report events the package
has never heard of.

`publish()` is called at the *end* of the simulation step, not from `step()`. A
button pressed with the use key runs after mechanisms have stepped, so a door
it starts is not yet moving when `step` returns; publishing there would report
every such door a step late.

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
- **No game-over and no level transition.** `Level.next` is a field nothing
  reads and `exit` is an entity that spawns nothing. There *is* a pause:
  `GameLoop.paused`, which stops the clock rather than accumulating time it
  then throws away.
- **Half a player abstraction.** `Player` owns the body, the inventory and the
  answer to "who is this collider". Yaw, pitch, eye height and the aim vector
  still belong to the application, which is the next thing to fix.
- **No rigid bodies.** Deliberate — nothing pushes the player and the player has
  no angular momentum.
- **Desktop input only.** `InputState` is device-agnostic and
  `setStickAxis` is the seam a gamepad or touch backend writes to; no such
  backend exists yet.
- **No animation, no persistence, no timers.** Nothing here schedules
  anything; a game that wants a delayed event counts down itself.

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
