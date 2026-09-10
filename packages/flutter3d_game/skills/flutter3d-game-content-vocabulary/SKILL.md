---
name: flutter3d-game-content-vocabulary
description: Use when adding content to a flutter3d game — entity kinds, level rules, actors, navigation — or when a feature seems to need a change in the engine below.
---

# The package offers kinds; the game composes a vocabulary

`lib/src/` contains no monsters, no weapons, no furniture, and no opinion about
whether a game has any. A game says what its documents may contain:

```dart
final kinds = EntityRegistry(<EntityKind>[
  const PlayerSpawnKind(),
  const DoorKind(),
  MonsterKind(myMonsters),   // only if this game has monsters
  MyOwnKind(),
]);
```

The same registry validates a level and spawns it, so the two cannot disagree
about what is legal. `LevelValidator` and `Level.spawnInto` both require one.

Rules about a level **as a whole** are also the game's: requiring one
`player_spawn`, warning about a missing `exit`. Pass them as `LevelRule`s. What
the validator checks by itself is true of any level — names unique, references
resolving, brushes not degenerate, something to stand on, something to see by.

Write a new kind as a class rather than a value in an enum with a switch. Every
job that treats kinds differently grows its own switch over the same names in a
different file, and the switches drift.

## Actors carry only what they have

`Actor` is an entity and a handle, and every part is optional: no body (a
turret, a director), no health (a lift, a lamp post), no brain (a barrel), no
facing (anything with no front). `isAlive` is true for an actor with no health,
because nothing to kill is not the same as dead.

`ActorSystem` steps, throttles thinking, turns, routes, tests lines of sight,
applies damage and stops corpses blocking corridors — and knows what none of
them is for. A chase machine, an alert pause, a flinch roll and a weapon belong
to a genre package. Naming a monster, a lap or a jump here fails
`dart run tool/structure.dart`.

Damage goes through `Damageable`, and a monster implements it by handing the
call back to the system that spawned it: subtracting from its own health leaves
a corpse that still blocks the corridor and a death nothing counted.
`Collider.userData` answers one question — who is this — and callers ask it
`is Damageable`, `is Rider`, `is Collector`.

## Navigation

`Navigation` is optional; null means see the player, walk straight, get stuck on
the corner. Given one, a chasing actor reads a flow field.

**Cell size is the setting that matters, and half a metre is often too coarse.**
A grid is conservative: a cell touching a wall has clearance one however far the
wall is. At `cellSize: 0.5` a one-metre corridor is two touching cells, so a
body needing clearance two is refused a passage it physically fits through, and
falls back to walking straight at the player exactly where a route was worth
having. The dungeon bakes at `0.25`.

**One `Navigation` means one goal.** `update` re-targets every field it holds.
Two callers with different destinations sharing one leaves the second flowing to
the first one's goal, and the symptom is an agent that looks stuck.

The grid is baked from `Level.brushes` rather than from the `CollisionWorld`,
which holds the doors — whichever position one was in at load would freeze into
the grid as architecture. Where a column has two walkable surfaces the **lowest**
wins, because a ceiling's upper face passes every local test for a floor and
taking the highest puts the level's population on the roof; where that is wrong,
the bake says so as a `LevelIssue`.

## Where the player is looking

`Player` owns yaw, pitch, the eye and the aim. The pitch limit is a
mathematical invariant: at a right angle the forward vector is parallel to world
up, the cross product that builds the view basis is zero, and orientation stops
being defined. **Walking follows the yaw only**, so walking forward while looking
at the floor does not drive the player into it. `eyeFrom` exists separately from
`eye` because the camera reads the interpolated position while the simulation
reads its own.

## What this package will not do

Navigation gets an actor there and not around anybody; nothing reserves the
space it walks into. `RunOutcome` says whether a run is being played, lost or
won, and an `Exit` says where to go next, but nothing restarts a level or loads
the next one — a genre names its own states and maps them onto that.

`CameraRig` is the part every chasing camera has: easing towards a place
somebody else worked out, carrying knocks and shakes, staying out of walls. It
has no idea where it wants to be and computes no projection, so third-person and
over-the-shoulder are a caller reading `eye` and `aim` differently and handing
the rig a target.

Nothing schedules anything: a delayed event is a countdown somebody writes.
