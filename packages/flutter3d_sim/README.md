# flutter3d_sim

The simulation half of [flutter3d](https://flutter3d.pleion.dev): a fixed step,
an entity store, the level format, saves and replays, world logic, actors,
navigation, a camera rig and the maths under all of it.

**Plain Dart.** No Flutter, no renderer, no device. `dart test` runs the whole
suite with no binding, and `dart run` advances a step in a container with no
Flutter SDK in it.

```dart
import 'package:flutter3d_sim/flutter3d_sim.dart';

final world = CollisionWorld()..addBox(Vector3.zero(), Vector3(20, 1, 20));
final body = CharacterController(world: world, position: Vector3(0, 1, 0));
final dice = GameRandom(7);

for (var step = 0; step < 600; step++) {
  body.step(1 / 60, wishDirection: Vector3(0, 0, 1));
  world.update();
}
```

## Why it is a separate package

Not tidiness. A server that verifies a submitted run has to replay it through
**the same simulation the player ran** — the moment a second copy of the game
logic exists on the server, the verification stops proving anything about the
first. That server is an ordinary Dart process, and requiring a Flutter SDK
there to advance a headless step is a blocker rather than an inconvenience.

It came out of `flutter3d_game`, which reached Flutter in eight files out of
eighty-nine: five touch and keyboard widgets, one `MediaQuery` read and one
`debugPrint`. Those stayed behind with the devices they belong to.
`flutter3d_game` re-exports this package, so a program that imported it keeps
working unchanged.

The boundary is checked rather than described: `the simulation names no
Flutter` in `tool/structure.dart` reads this package's `lib/`, `test/` and
`bin/` and fails on the first import that would put a Flutter SDK back on the
critical path.

## Determinism, and what it is worth across machines

Every step takes its randomness from a `GameRandom` whose state is a number you
can write down, and reads no clock. `InputTape` is a run as the intents that
produced it, at a few bytes a step, and it is the format a run is submitted to a
server in.

`StateDigest` and `DigestTrace` are how two runs are compared without sending
each other their worlds: a 32-bit digest over the bits of a snapshot, taken every
so many steps, with the first disagreeing checkpoint named. **Read
`test/parity_test.dart` before designing anything on top of this** — it measures
what carries across platforms and what does not, and the answer is narrower than
"the simulation is deterministic".

## Documentation

<https://flutter3d.pleion.dev>
