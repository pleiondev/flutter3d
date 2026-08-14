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
| `loop/` | `FixedStep`, `GameLoop`, interpolation. **A step *order* is a genre's** — see `GameSimulation` in [`flutter3d_shooter`](../flutter3d_shooter) |
| `input/` | `GameAction`, `InputState` (latched edges, analogue axis, look delta), `DesktopInput` |
| `level/` | `Level` format v1, `EntityKind` and its registry, `LevelValidator`, brush→geometry, `SpawnContext` |
| `world/` | `Mechanism`, `Signal`, `Mover` (door, lift, platform), `Button`, `TriggerVolume`, `Exit`, `Rider`, `KeyRing`, `LightFixture` |
| `actors/` | `Actor` (a body with health), `Brain`, `ActorSystem`, `Health`, `Damageable` |
| `nav/` | `NavGrid` baked from the brushes, `FlowField`, `Navigation` |
| `ecs/` | `EcsWorld`, `Entity`. Actors and projectiles live here; see below |
| `save/` | `Snapshot`, `GameRandom` |
| `physics/` | Only the layer names. Collision, character movement and rigid bodies are [`flutter3d_physics`](../flutter3d_physics), a plain Dart package |

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

`Simulation` owns this order now, and two claims that used to sit here as
comments have been measured rather than repeated:

- **A platform that moves sideways cannot carry you** if the kinematic deltas
  are cleared before the body steps. Tested. Note *sideways*: the old comment
  said a rising lift could not carry you, and that is false — a lift penetrates
  the capsule standing on it and the controller pushes it out, upwards, whether
  the delta was read or not.
- **`reindex()` before `body.step` is ordering by argument, not by test.** It
  is right — the broadphase should match geometry that already moved — but the
  narrow phase reads live positions and a cell is four metres, so a stale index
  loses a mover only if it left its cell inside one step. No door does. Nothing
  here claims a test covers it.

And a third thing, which was a real bug rather than a claim about one: a
`Mover` refused to move into any body, and a passenger standing on it overlaps
where it is about to be on every step. **No lift in the repository could move
while anybody rode it.** `Rider` is what tells being carried from being in the
way.

## Actors, and why there are no monsters here

`Actor` is an entity and a handle. **Every part of it is optional**, and each
one left out is a component the entity does not carry:

| Left out | What that is |
|---|---|
| no body | a turret, a trigger, a director that decides and stands nowhere |
| no health | a lift, a lamp post — a rocket may ask and get "nothing happened" |
| no brain | a barrel, or anything the game moves itself |
| no facing | anything with no front, which then does not turn |

`spawn` used to require the first three, so a destructible crate came with a
walking capsule and a brain that did nothing. `isAlive` is true for an actor
with no health, because nothing to kill is not the same as dead. `ActorSystem` steps them, throttles their thinking, turns them,
routes them round corners with the navigation grid, tests lines of sight,
applies damage, counts deaths and stops corpses blocking corridors.

**None of it knows what any of them is doing.** That was `Monster` and
`MonsterSystem`, and the engine therefore knew what an alert pause was, that
attacking involves a weapon, and that being hurt involves a chance of
flinching. A platformer has none of those, and the first thing that would have
happened when one was written is that half the file would have been unusable
and the other half copied.

The shooter's chase-and-attack machine — six states, `MonsterDef`, the flinch
roll, `Bestiary`, `MonsterKind` — is in
[`flutter3d_shooter`](../flutter3d_shooter), and so are the weapons, the
inventory, the pickup and the step order that drives them. It used to be
`lib/shooter.dart` here, unexported by the barrel, which was a rule rather than
a boundary: the file still resolved from inside this package, and the four
things it leans on carried no marking at all. `test/no_genre_test.dart` is what
makes the split a fact rather than a rename, and `test/actor_test.dart` drives
an actor with a fourteen-line patrol brain that shares nothing with any of it.

The rule is the one `gift.dart` wrote down long before this: a hierarchy rather
than an enum with a switch, because every job that treats them differently
grows its own switch over the same names in a different file, and the switches
drift.

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

`flutter3d_shooter/lib/sample.dart` holds the roster this repository's own game
uses, and the two hundred-odd tests written against those numbers went with it.

That is also why four suites covering *this* package's machinery — the level
format, the validator, navigation, and buttons and trigger volumes — now run
from the shooter package: their fixtures are written in that game's vocabulary
(`monster`, `key`, `torch`), so they moved rather than being rewritten blind.
The coverage still runs on every CI. What was lost is locality, and
content-free fixtures for those four are work that has not been done.

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

## Getting there

`Navigation` is optional and null keeps the old behaviour exactly — see the
player, walk straight, get stuck on the corner. Given one, a chasing monster
reads its direction out of a flow field instead.

Three decisions worth knowing, because each has an alternative that looks
better and is not:

- **A grid, not a navmesh.** A navmesh's advantage is representing arbitrary
  walkable surfaces. This format has axis-aligned boxes and no slopes, so the
  navmesh pipeline's output would be the rectangles you could have rasterised
  directly.
- **One flow field, not thirty A\* searches.** Nothing targets anything but
  the player, so thirty searches would compute thirty prefixes of one tree. The
  sweep runs only when the player crosses into another cell.
- **Baked from `Level.brushes`, not from the `CollisionWorld`.** The world
  holds the doors, and whichever position one happened to be in at load would
  be frozen into the grid as architecture.

One height per column, and where a column has two surfaces the **lowest**
wins — because a ceiling's upper face is a perfectly good standing surface by
every local test there is, and taking the highest puts the level's whole
population on the roof. Where that is genuinely wrong, a walkway over a floor
with both under a ceiling, the bake says so as a `LevelIssue` warning.

A field refuses cells its body does not fit in, across and up, and `Navigation`
keeps one per class — usually two or three for a whole roster. Clearance is
measured against *reachable* room: the top of a wall is a surface, and counting
it as space would make every corridor come out two cells wider than it is.

**Cell size is the setting that matters, and half a metre is often too coarse.**
A grid is conservative: a cell touching a wall has a clearance of one however
far the wall actually is. At `cellSize: 0.5` a one-metre corridor is two cells,
both of them touching, so no body needing clearance two is routed through it —
and a monster 0.7 wide, which physically fits, is refused the whole passage. The
grid then falls back to walking straight at the player in exactly the places a
route is worth having. The dungeon bakes at `0.25` for that reason, measured on
its own corridors; four times the cells and twice the bake, both at load time.

**One `Navigation` means one goal.** `update` re-targets every field it holds,
which is the point — and the one way to misuse it. Two callers with different
destinations must not share one, or the second one's fields quietly flow to the
first one's goal and the symptom is an agent that looks stuck.

On `crypt.json` at half-metre cells the grid is 55×96 and bakes in well under a
tenth of a second; a sweep is under a millisecond. Every cell it cannot reach
from the player's start is up on top of something. None is on the floor.

## Where the player is looking

`Player` owns yaw, pitch, the eye and the aim vector. All four used to live in
the application, where the spherical-to-cartesian aim was written out **three
times** — for the use ray, for firing, and for the camera's look-at target.
Three copies of four lines of trigonometry, none of them tested. The
interesting part is not that one was wrong; they agreed. It is that nothing
would have noticed if one had stopped agreeing.

Two rules live on the pawn because they are facts about it rather than about
any caller:

- **The pitch limit is a mathematical invariant, not taste.** At exactly a
  right angle the forward vector is parallel to world up, the cross product
  that builds the view basis is zero, and the camera's orientation stops being
  defined.
- **Walking follows the yaw only.** Walking forward while looking at the floor
  must not drive the player into it — that is what a fly camera does. The
  application asserted this in a comment; `moveWish` asserts it in a test.

`eyeFrom` exists separately from `eye` because the camera must read the
*interpolated* position while the simulation reads its own.

## Writing a game down

`GameSimulation.save()` returns a `Snapshot`: everything needed to carry on
simulating, and nothing needed only to draw. A save file, a network packet and
the input to a determinism test are the same thing, so there is one mechanism
rather than three — keeping three of them right costs three times as much.

**It is not a level loader.** A snapshot restores objects that already exist:
the same collision world, the same monsters in the same order, the same
mechanisms under the same names. That boundary is what saves it from having to
invent an identity scheme for every collider. Load the level, then apply the
snapshot.

Versioned like the level format, and refuses a document from a newer build for
the same reason: subtly wrong is worse than refused.

`GameRandom` exists because `math.Random` has no readable state, which makes it
the one thing in a simulation that cannot be written down. Pass one instance to
`MonsterSystem`, `Hitscan` and `GameSimulation` and two loads of the same save
agree for ever; leave it out and they agree until the first flinch roll.

The determinism test that goes with it found a real defect on its first run:
monster thinking was staggered across steps by `Object.hashCode`, which is an
address, so two runs of the same game with the same seed diverged. It is an
ordinal now.

## The ECS, and how far it has got

`EcsWorld` is tested, and **two systems have moved onto it: actors and
projectiles.** Mechanisms and the player still hold their own state and write
their own saves. Saying where the line is beats leaving it to be discovered.

It was accepted for one reason, recorded in `docs/SPEC.md`: replication. A
snapshot with delta compression needs state enumerable in one place, and the
`GameSimulation.save()` above enumerates it by hand — a line per subsystem,
which will silently miss the next one. `EcsWorld.save()` cannot miss one: a
component type that is neither registered nor deliberately excluded throws,
naming itself.

It is not accepted for cache locality, and does not deliver any: components
live in maps keyed by entity index. The condition that would change that is
written in the file — a query walking thousands of entities per step, showing
up in a profile — so it is a measurement later rather than a preference.

**Building it before the migration rather than during** was deliberate, and it
paid immediately: the projectile move changed no test and broke nothing, so
whatever had gone wrong would have been the system rather than the core.

What the move bought, in one sentence: neither system writes its own save any
more, and the next component anybody adds to an actor cannot be left out of a
save file by omission — `EcsWorld.save()` refuses to write a component type
nobody registered.

Two things the actor move forced, both of which improved the design:

- **`registerInPlace`.** A `CharacterController` owns a collider in a live
  collision world and a `Brain` is code as much as data; neither can be rebuilt
  from a file, and neither needs to be, because a snapshot restores a world
  that already exists. So those components take their numbers back rather than
  being reconstructed. The alternative — declaring them unsaved and writing
  their state by hand somewhere else — is the hand-written save this removes,
  wearing a different hat.
- **`ordinal` is gone.** Actors were numbered by hand so thinking could be
  staggered deterministically; an entity already has a stable index.

What did **not** move is `Actor` itself, and the reason is worth knowing before
anyone tries again. `Collider.userData` answers *who is this*, and callers ask
it `is Damageable`, `is Rider`, `is Collector`. An entity id in that field turns
every one of those back into "look up a component, in which world" — in the
blast resolver, the hitscan, the mechanisms and the pickups. So `Actor` is a
handle: an entity, its world, and those three answers. Every field on it is a
component read.

The cap survived the move. Sixty-four in the air at once is far past what the
game produces, and something that grows without limit under load grows during
the frame that was already struggling.

## Things with mass

`GameSimulation` takes an optional `Dynamics` — crates, barrels, anything the
world pushes around. Stage one of the specification's two: mass, gravity,
impulses, resting and sleeping, and **no rotation**, which is what makes a box
stay axis-aligned and its contacts exact.

**A character controller does not push anything on its own**, and that is not an
oversight: it is kinematic, it sweeps and slides and is never moved by anything,
which is what makes a first-person game feel solid. So the transfer is explicit
— `Dynamics.push`, called after the player has moved — and it hands over a
*speed* rather than a force. A crate gets just enough velocity to move away at
the speed it is being approached at, and no more; a force proportional to mass
would let a player launch a light crate across the room by brushing it.

A body is a `Physical` component, so the snapshot carries it with everything
else and the next kind of moving thing cannot be left out by omission.

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

- **Navigation gets you there, not around you.** No flanking, no cover, no
  squads, no doors opened by monsters, and nothing reserves the space it is
  walking into, so a crowd in a corridor is still a crowd in a corridor.
- **A game flow with nowhere to go.** `GameState` is `playing`, `dead` or
  `complete`, a dead player's input moves nothing, and an `Exit` reports where
  to go next. What no one has written is the part that *acts* on that: nothing
  restarts a level and nothing loads the next one.
- **No camera, and that is not an omission.** `Player` owns the body, the
  inventory, where the eye is and which way it points; what a projection matrix
  should do about that belongs to the renderer. Third-person, over-the-shoulder
  and fixed cameras are all a caller reading `eye` and `aim` differently.
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
