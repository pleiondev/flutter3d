---
name: flutter3d-sim-fixed-step
description: Use when writing simulation code on flutter3d_sim — the fixed step, the ECS, levels, saves, InputTape and GameRandom — or when a run has to reproduce elsewhere.
---

# Plain Dart, and a step that reproduces

No Flutter, no renderer, no device: `dart test` runs the suite with no binding
and `dart run` advances a step in a container with no Flutter SDK. A server
verifying a submitted run replays it through **the same simulation the player
ran**, and a second copy of the game logic on the server proves nothing about
the first.

`flutter3d_game` re-exports this package whole. An import of `package:flutter/…`
here fails the `the simulation names no Flutter` rule in
`dart run tool/structure.dart`.

## The step

```dart
final loop = GameLoop(
  input: inputState,
  onStep: (dt) => world.step(dt),      // dt is always stepSeconds
  clock: FixedStep(stepSeconds: 1 / 60, maxStepsPerFrame: 5),
);
```

`dt` never varies, which is what makes two runs comparable. `maxStepsPerFrame`
keeps a stalled frame from spiralling: a frame that took thirty seconds asks for
eighteen hundred steps, which take longer than thirty seconds to run and so ask
for more next frame.

Anything a fixed step makes jerky is the renderer's problem, and
`InterpolatedVector3` / `InterpolatedAngle` are the answer — the visual reads
between the last two simulated states rather than the step becoming variable.

## No clocks, no loose dice

```dart
final dice = GameRandom(7);
snapshot['rng'] = dice.state;      // one number; write it back to continue
```

`DateTime.now()`, an unseeded `Random()` and a `Stopwatch` inside a step are all
caught by the `a step reaches for no clock and no loose dice` rule. Something
that genuinely needs wall time belongs above the simulation and arrives as an
input.

## Runs as tapes

`InputTape` is a run recorded as the intents that produced it, a few bytes a
step, and the format a run is submitted to a server in.
`InputTapeRecorder.record(input)` fills one, `InputTapePlayback` feeds it back.
A bug then arrives as a file rather than as a description, and a test can play a
whole level.

`StateDigest` and `DigestTrace` compare two runs without either sending its
world: a 32-bit digest over the bits of a snapshot, every so many steps, naming
the first checkpoint that disagrees.

**Read `test/parity_test.dart` before designing anything on top of this.** It
measures what carries across platforms, and the answer is narrower than "the
simulation is deterministic" — a browser's doubles and an integer digest do not
promise the same things.

## The entity store

```dart
world.register<Position>('position', encode: …, decode: …);  // once, at set-up

final entity = world.spawn();
world.set(entity, Position(…));
for (final e in world.query2<Position, Velocity>()) { … }

final saved = world.save();      // Map<String, Object?>; world.restore(saved)
```

A save is a plain map, written through the encoders registered for each type. A
type that must never be saved is declared with `exclude<T>('why')`, so the
failure carries a sentence instead of a silently missing field. `alive(entity)`
is the check before touching a handle kept across steps.

## Levels

A level is validated before it runs, and `LevelValidator` reports the coordinate
of a problem rather than "the file is broken". `LevelIssue` values are warnings
a caller can show; the level still loads where it can. Geometry, spawns,
visibility and the surface table live here with no mesh and no device near them
— turning a level into something drawable is `flutter3d_bridge`.
