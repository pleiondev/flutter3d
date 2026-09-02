/// Walks a body through a level and prints where it got to — with no Flutter.
///
///     dart run flutter3d_sim:headless_run
///     dart run flutter3d_sim:headless_run path/to/level.json
///
/// **This is the acceptance test of the package existing**, and it is a binary
/// rather than a test on purpose: `flutter test` would prove that the code
/// compiles under a Flutter toolchain, which was never in doubt. What had to be
/// shown is that a plain `dart run`, in a container with no Flutter SDK,
/// advances the same step a player's device advances — because that is the
/// process a verifying server is.
///
/// What it prints is a [DigestTrace]: a checkpoint every twenty-five steps, in
/// the form the server compares. Run it twice and the two are identical; run it
/// on another machine and whether they are is the question
/// `test/parity_test.dart` measures rather than assumes.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

const int _steps = 600;
const double _dt = 1.0 / 60.0;

void main(List<String> arguments) {
  final world = arguments.isEmpty
      ? _aRoom()
      : _fromDocument(File(arguments.first));

  final body = CharacterController(
    world: world,
    position: Vector3(0.0, 1.0, 6.0),
  );
  final dice = GameRandom(20260902);
  final trace = DigestTrace();
  final wish = Vector3.zero();

  for (var step = 1; step <= _steps; step++) {
    // A driver rather than a player: the point is that a step runs, not that
    // it is played well. Held for a stretch so the body actually travels —
    // a direction rerolled every step averages to standing still.
    if (step % 20 == 1) {
      wish.setValues(dice.nextDouble() * 2.0 - 1.0, 0.0, dice.nextDouble());
      final length = wish.length;
      if (length > 1e-6) wish.scale(1.0 / length);
    }
    if (dice.nextInt(53) == 0) body.requestJump();

    body.step(_dt, wishDirection: wish);
    world.update();
    trace.observe(step, <String, Object?>{
      'body': body.save(),
      'dice': dice.state,
    });
  }

  stdout
    ..writeln('$_steps steps, ${world.colliderCount} colliders, no Flutter')
    ..writeln('checkpoints: ${trace.hexDigests.join(' ')}');
}

/// A level document, if one was named.
///
/// Reading a file is the one thing this binary does that the simulation itself
/// never does: a level arrives as already-parsed data everywhere else, and
/// `dart:io` is deliberately confined to `bin/` so that the library stays
/// usable in a browser as well as on a server.
CollisionWorld _fromDocument(File file) {
  if (!file.existsSync()) {
    stderr.writeln('no level at ${file.path}');
    exit(2);
  }
  final json = jsonDecode(file.readAsStringSync());
  if (json is! Map<String, Object?>) {
    stderr.writeln('${file.path} is not a level document');
    exit(2);
  }
  final world = CollisionWorld();
  Level.fromJson(json).addTo(world);
  return world;
}

/// A room, for when no document was named.
CollisionWorld _aRoom() {
  final world = CollisionWorld()
    ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0))
    ..addBox(Vector3(0.0, 2.0, -20.0), Vector3(40.0, 6.0, 1.0))
    ..addBox(Vector3(0.0, 2.0, 20.0), Vector3(40.0, 6.0, 1.0))
    ..addBox(Vector3(-20.0, 2.0, 0.0), Vector3(1.0, 6.0, 40.0))
    ..addBox(Vector3(20.0, 2.0, 0.0), Vector3(1.0, 6.0, 40.0));
  for (var x = -3; x <= 3; x++) {
    for (var z = -3; z <= 3; z++) {
      if ((x + z) % 2 == 0) continue;
      world.addBox(Vector3(x * 4.0, 2.0, z * 4.0), Vector3(1.4, 6.0, 1.4));
    }
  }
  return world;
}
