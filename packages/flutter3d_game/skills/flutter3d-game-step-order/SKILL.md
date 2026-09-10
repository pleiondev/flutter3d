---
name: flutter3d-game-step-order
description: Use when writing or debugging a flutter3d_game simulation step — the order mechanisms, collision and bodies run in, how events are drained, snapshots, and input.
---

# The order a step runs in

```dart
mechanisms.step(dt);              // doors and lifts move
collision.reindex();              // the broadphase learns where they are
body.step(dt, wishDirection: …);  // then the player sweeps against them
collision.update();
collision.clearKinematicDeltas();
```

`Simulation` owns that order. Clearing kinematic deltas before the body steps
stops a **sideways** platform carrying anybody; a rising lift penetrates the
capsule on it and the controller pushes it out upwards either way. `reindex()`
before `body.step` is ordering by argument rather than by test: the narrow phase
reads live positions and a cell is four metres, so a stale index only loses a
mover that left its cell inside one step, and no door does.

A `Mover` refuses to move into any body, and a passenger standing on one
overlaps where it is about to be on every step — which is why `Rider` exists,
and why no lift could move while anybody rode it until it did.

A **step order is a genre's**. `GameSimulation` in `flutter3d_game_shooter` is
one shooter's; a platformer's is its own.

## Events are lists, drained after the step

`ActorSystem.died` and `hurtThisStep`, `ProjectileSystem.detonations`,
`MechanismWorld.events` after `publish()`. A `Stream` would deliver *after* the
step that produced the event, which is the property this package protects; a
list cleared at the top of each step is synchronous, typed, and allocates
nothing.

Call `publish()` at the **end** of the step. A button pressed with the use key
runs after mechanisms have stepped, so a door it starts is not moving yet when
`step` returns, and publishing from inside reports every such door a step late.

Each mechanism reports itself through `Mechanism.collect`, so a game's own
mechanism can report events this package has never heard of.

## Input has forgotten which device it came from

`InputState` holds latched edges, analogue axes and a look delta. `DesktopInput`
is the keyboard, `pad_input` the gamepad, `TouchControls` writes into the same
state. Write against `GameAction` and it works on all three.

Latched edges matter at a low frame rate: a press and release inside one frame
is still a press, and reading raw key state loses it.

## A snapshot is a save, a packet and a determinism test

`GameSimulation.save()` returns everything needed to carry on simulating and
nothing needed only to draw. **It is not a level loader**: a snapshot restores
objects that already exist — the same collision world, the same actors in the
same order, the same mechanisms under the same names — which is what saves it
from inventing an identity scheme for every collider. Load the level, then apply
the snapshot. It refuses a document from a newer build.

Pass one `GameRandom` to everything that draws — `ActorSystem`, the genre's
systems, `GameSimulation` — or two loads of the same save agree until the first
roll. Anything standing in for identity inside a step has to be an ordinal or an
entity index: staggering actor thinking by `Object.hashCode`, which is an
address, diverged two runs of the same seed.

## The ECS, and how far it has got

Actors and projectiles live in `EcsWorld`; mechanisms and the player still write
their own saves. It was accepted for replication rather than cache locality:
`EcsWorld.save()` cannot silently miss a subsystem, because a component type
that is neither registered nor deliberately excluded throws and names itself.

`registerInPlace` is for components that cannot be rebuilt from a file and need
not be — a `CharacterController` owning a collider in a live world, a `Brain`
that is code as much as data.

`Actor` is deliberately not an entity id: `Collider.userData` is asked
`is Damageable`, `is Rider`, `is Collector`, and an id there turns each of those
into a component lookup in some world.

## Layers

`CollisionLayers` names the bits — `world`, `player`, `monster`, `pickup`,
`trigger` — here rather than in `flutter3d_physics`, because a collision world
that knows what a monster is cannot be used by a game that has none. Five is a
default: a game with vehicles or water adds bits six upwards, and nothing in
either package reads the names.
