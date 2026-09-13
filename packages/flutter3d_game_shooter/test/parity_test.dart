/// A crawl played twice, and now it is the same crawl wherever it is played.
///
///     flutter test test/parity_test.dart
///     flutter test --platform chrome test/parity_test.dart
///     flutter test --platform chrome --wasm test/parity_test.dart
///
/// **The fourth genre's own answer to the question the other three already
/// asked.** `flutter3d_sim/test/parity_test.dart` matched a bare
/// `CharacterController`; `flutter3d_game_racing` and `flutter3d_game_strategy`
/// each found their own genre reaching further than the controller does. This
/// is `GameSimulation` — crouch, look, jump, and the step order this package
/// argued out for the other genres to copy — none of which the bare
/// controller exercises.
///
/// The room is the same one `flutter3d_sim`'s and
/// `flutter3d_game_platformer`'s parity files play in, on purpose: a
/// divergence that shows up only here is this package's own, and one that
/// shows up in all three is the controller's.
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

void main() {
  group('a thousand steps of a player', () {
    test('is the crawl that was recorded, wherever it is played', () {
      final trace = _play(_tape(seed: 20260912, steps: 1000));
      final divergence = trace.divergenceFromHex(_recorded);
      expect(
        divergence,
        isNull,
        reason:
            'this platform ran a different player: $divergence. Bisect '
            'between that checkpoint and the one before it; if '
            '`flutter3d_sim/test/parity_test.dart` is green the cause is in '
            'this package rather than in the controller underneath it.',
      );
    });

    test('and playing it twice in one process gives the same crawl twice', () {
      final tape = _tape(seed: 5, steps: 300);
      expect(_play(tape).digests, _play(tape).digests);
    });

    test('and a different tape is a different crawl', () {
      expect(
        _play(_tape(seed: 5, steps: 300)).digests,
        isNot(_play(_tape(seed: 6, steps: 300)).digests),
      );
    });
  });
}

/// The room `flutter3d_sim`'s and `flutter3d_game_platformer`'s parity files
/// play in, kept identical rather than reinvented — see the note at the top of
/// this file for why.
CollisionWorld _room() {
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
/// the reason the other parity files give.
///
/// Movement held on a rhythm, a look delta every step (a mouse never rests),
/// and a jump and a crouch each held on their own rhythm — so the controller's
/// jump, the crouch capsule swap and the look-driven move axis all run inside
/// the thousand steps.
List<({bool forward, bool jump, bool crouch, double lookX, double lookY})>
_tape({required int seed, required int steps}) {
  final dice = GameRandom(seed);
  final tape =
      <({bool forward, bool jump, bool crouch, double lookX, double lookY})>[];
  var forward = false;
  var jump = false;
  var crouch = false;
  for (var i = 0; i < steps; i++) {
    if (i % 17 == 0) forward = dice.nextDouble() < 0.8;
    if (i % 13 == 0) jump = dice.nextDouble() < 0.3;
    if (i % 29 == 0) crouch = dice.nextDouble() < 0.3;
    tape.add((
      forward: forward,
      jump: jump,
      crouch: crouch,
      lookX: (dice.nextDouble() * 2.0 - 1.0) * 0.05,
      lookY: (dice.nextDouble() * 2.0 - 1.0) * 0.02,
    ));
  }
  return tape;
}

/// Plays [tape] through `GameSimulation` and digests the world every
/// twenty-five steps.
DigestTrace _play(
  List<({bool forward, bool jump, bool crouch, double lookX, double lookY})>
  tape, {
  int every = 25,
}) {
  final world = _room();
  final input = InputState();
  final player = Player(
    body: CharacterController(world: world, position: Vector3(0.0, 1.0, 6.0)),
  );
  final sim = GameSimulation(
    player: player,
    collision: world,
    input: input,
    random: GameRandom(20260912),
  );
  final trace = DigestTrace(every: every);

  var forward = false;
  var jump = false;
  var crouch = false;
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
      wish.jump
          ? input.press(GameAction.jump)
          : input.release(GameAction.jump);
      jump = wish.jump;
    }
    if (wish.crouch != crouch) {
      wish.crouch
          ? input.press(ShooterActions.crouch)
          : input.release(ShooterActions.crouch);
      crouch = wish.crouch;
    }
    input.addLook(wish.lookX, wish.lookY);

    sim.step(_dt);
    input.endStep();

    trace.observe(step, sim.save().toJson());
  }
  return trace;
}

/// Recorded on macOS-arm64 under the VM, 2026-09-12.
const List<String> _recorded = <String>[
  '16e3d7e9',
  '6d76e27b',
  '228ceea1',
  '5c3e0a83',
  'e96f0f28',
  'e4ed09fc',
  '56cfc973',
  'de356577',
  '696f7bce',
  '7c3b90c0',
  'db637ac8',
  'f924106e',
  '0d4f5cc1',
  '2c8d858a',
  'b4e21424',
  '17bb021d',
  '95cabe54',
  '3d6da1fd',
  'b84f77e2',
  'a1fcf215',
  'a996d8c8',
  'ce9b018d',
  'ee524b7e',
  'b67c000d',
  '81226920',
  'bdc870a3',
  '04137c6a',
  '297280d1',
  '118aa31c',
  'c3561b6d',
  '7407924d',
  'fb010bba',
  '4162c08e',
  '68a0eb89',
  '5ebe10a6',
  'b871fdeb',
  'f68ed393',
  '87a93c6e',
  'da39d439',
  '059ecd2d',
];
