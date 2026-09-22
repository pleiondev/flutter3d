/// `rp-00`'s determinism probe, on the one platform `flutter test` cannot
/// reach: an actual device.
///
///     flutter test integration_test/parity_test.dart -d <device-id>
///
/// **Mirrors `packages/flutter3d_game_platformer/test/parity_test.dart` on
/// purpose, rather than importing it.** That file's scenario is private, and
/// this one needs to run inside `IntegrationTestWidgetsFlutterBinding` on a
/// real phone rather than under `TestWidgetsFlutterBinding` on a host — two
/// different entry points for the same computation. If a checkpoint ever needs
/// to change, change it in both places; a mismatch between them would be
/// silent otherwise. See `doc/tooling-plan.md` rp-00 for what this is
/// answering and why it is not part of `test/` already.
library;

import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a thousand steps of a runner match the recorded trace', (
    WidgetTester tester,
  ) async {
    final trace = _play(_tape(seed: 20260912, steps: 1000));
    final divergence = trace.divergenceFromHex(_recorded);
    expect(
      divergence,
      isNull,
      reason:
          'this device ran a different runner: $divergence. See '
          'packages/flutter3d_game_platformer/test/parity_test.dart, which '
          'recorded the trace this compares against.',
    );
  });
}

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

/// The same trace `packages/flutter3d_game_platformer/test/parity_test.dart`
/// recorded on macOS-arm64 under the VM, 2026-09-12.
const List<String> _recorded = <String>[
  'bb9e0171',
  '0fd867d5',
  '4e9391fe',
  'ddc05a18',
  '8d22cefe',
  '309a14fa',
  '5e7213e6',
  'bb742308',
  'c91b21cb',
  '1bc03276',
  '4c849101',
  'b3ebc3e5',
  '8133b25b',
  'a4c24fbe',
  'ded93d8c',
  '2055247e',
  'bc7ddbb9',
  '75d5f4ee',
  'b461a66a',
  '48abbbc6',
  'fbb66590',
  '01238495',
  '89c70c86',
  '150907c4',
  'c7b545d0',
  '7ba2901e',
  'f53618e4',
  '8bfc7b33',
  '8f07424b',
  '90db1f20',
  '0fb208d3',
  'ffc963fe',
  '5c253ed5',
  '94bf51ef',
  '72b7e877',
  'e7090d03',
  '9fee6404',
  'dd4a407b',
  'd5d535bd',
  '7df6e6d2',
];
