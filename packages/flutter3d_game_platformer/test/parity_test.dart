/// A run played twice, and now it is the same run wherever it is played.
///
///     flutter test test/parity_test.dart
///     flutter test --platform chrome test/parity_test.dart
///     flutter test --platform chrome --wasm test/parity_test.dart
///
/// **The sibling this package did not have.** `flutter3d_sim/test/parity_test.dart`
/// already drove a bare `CharacterController` for a thousand steps and matched
/// the VM against Chrome; `flutter3d_game_racing` and `flutter3d_game_strategy`
/// each measured their own genre on top of that and found the racer's tyre
/// curve reaching `dart:math` where the character controller never had. This is
/// the same question asked of `PlatformerSimulation` — coyote time, the jump
/// buffer, the double jump, crouch and the surfaces table — none of which the
/// bare controller exercises.
///
/// The scenario is the sim package's own room: floor, walls, a lattice of
/// pillars and a flight of steps, so this measures the runner rather than a
/// second geometry. A document read from disk would put a level loader between
/// the measurement and the thing measured, and `dart:io` does not exist in a
/// browser test besides.
library;

import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

void main() {
  group('a thousand steps of a runner', () {
    test('is the run that was recorded, wherever it is played', () {
      final trace = _play(_tape(seed: 20260912, steps: 1000));
      final divergence = trace.divergenceFromHex(_recorded);
      expect(
        divergence,
        isNull,
        reason:
            'this platform ran a different runner: $divergence. Bisect '
            'between that checkpoint and the one before it; if '
            '`flutter3d_sim/test/parity_test.dart` is green the cause is in '
            'this package rather than in the controller underneath it.',
      );
    });

    test('and playing it twice in one process gives the same run twice', () {
      final tape = _tape(seed: 5, steps: 300);
      expect(_play(tape).digests, _play(tape).digests);
    });

    test('and a different tape is a different run', () {
      expect(
        _play(_tape(seed: 5, steps: 300)).digests,
        isNot(_play(_tape(seed: 6, steps: 300)).digests),
      );
    });
  });
}

/// The room `flutter3d_sim/test/parity_test.dart` plays a bare controller
/// through, kept identical on purpose: a divergence that shows up here and not
/// there is this package's own, and one that shows up in both is the
/// controller's, and the two files should not have to agree that by
/// coincidence.
CollisionWorld _room() {
  final world = CollisionWorld(properties: platformerWorld)
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
  for (var i = 0; i < 6; i++) {
    final top = 0.3 * (i + 1);
    world.addBox(
      Vector3(8.0, top / 2.0, -6.0 - i.toDouble()),
      Vector3(6.0, top, 1.0),
    );
  }
  return world;
}

/// What the player did, generated rather than written down — [GameRandom] for
/// the reason the other parity files give: it is the one generator this
/// repository has proved gives the same sequence everywhere.
///
/// Held for a stretch rather than rerolled every step, the way a keyboard
/// produces edges and not noise: a direction and a jump held or not, changed
/// on a rhythm and read as `press`/`release` rather than every-step state.
List<({bool forward, bool jump})> _tape({
  required int seed,
  required int steps,
}) {
  final dice = GameRandom(seed);
  final tape = <({bool forward, bool jump})>[];
  var forward = false;
  var jump = false;
  for (var i = 0; i < steps; i++) {
    if (i % 17 == 0) forward = dice.nextDouble() < 0.8;
    if (i % 11 == 0) jump = dice.nextDouble() < 0.4;
    tape.add((forward: forward, jump: jump));
  }
  return tape;
}

/// Plays [tape] through `PlatformerSimulation` and digests the world every
/// twenty-five steps.
DigestTrace _play(List<({bool forward, bool jump})> tape, {int every = 25}) {
  final world = _room();
  final input = InputState();
  final runner = Runner(
    body: CharacterController(world: world, position: Vector3(0.0, 1.0, 6.0)),
  );
  final sim = PlatformerSimulation(
    runner: runner,
    collision: world,
    input: input,
    startAt: Vector3(0.0, 1.0, 6.0),
    random: GameRandom(20260912),
  );
  final trace = DigestTrace(every: every);

  var forward = false;
  var jump = false;
  for (var step = 1; step <= tape.length; step++) {
    input.beginStep();
    final wish = tape[step - 1];
    if (wish.forward != forward) {
      wish.forward
          ? input.press(GameAction.moveForward)
          : input.release(GameAction.moveForward);
      forward = wish.forward;
    }
    if (wish.jump != jump) {
      wish.jump ? input.press(GameAction.jump) : input.release(GameAction.jump);
      jump = wish.jump;
    }
    sim.step(_dt);
    input.endStep();

    trace.observe(step, sim.save().toJson());
  }
  return trace;
}

/// Recorded on macOS-arm64 under the VM, 2026-10-08, once the runner's push
/// was held to its grip.
const List<String> _recorded = <String>[
  'd98eaea0',
  'e2afdea4',
  '6ba526e7',
  'ed9e0749',
  '4dafeff7',
  '139ec879',
  '00bd49c3',
  '9967cd3d',
  '34ad8ff2',
  '685d342b',
  '671c756c',
  'c0a45cf0',
  '4059470a',
  '2c94c96f',
  '9c43fa21',
  '324922c3',
  '9d03fe50',
  'c3513573',
  'b9954323',
  'a6a6ab93',
  '1609d141',
  'aef296ac',
  'b2c1d897',
  '81eebae9',
  '362ec47d',
  '388506e7',
  '3396afcd',
  'f154235e',
  '141bbc06',
  '4336f3b1',
  'd824f802',
  '737a1003',
  '35d7ede4',
  'e4210f1a',
  '62c68ec2',
  'e9113bb6',
  '331c7b1f',
  '73a66f0e',
  '8448e0b0',
  '7fc4718f',
];
