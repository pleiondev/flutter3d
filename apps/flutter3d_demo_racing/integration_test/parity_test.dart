/// `rp-00`'s determinism probe, on the one platform `flutter test` cannot
/// reach: an actual device.
///
///     flutter test integration_test/parity_test.dart -d <device-id>
///
/// **Mirrors `packages/flutter3d_game_racing/test/parity_test.dart` on
/// purpose, rather than importing it** — see
/// `apps/flutter3d_demo_platformer/integration_test/parity_test.dart` for why.
/// See `doc/tooling-plan.md` rp-00 for what this answers.
library;

import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a thousand steps of a car match the recorded drive', (
    WidgetTester tester,
  ) async {
    final trace = _drive(_laps(seed: 20260902, steps: 1000));
    final divergence = trace.divergenceFromHex(_recorded);
    expect(
      divergence,
      isNull,
      reason:
          'this device drove a different car: $divergence. See '
          'packages/flutter3d_game_racing/test/parity_test.dart, which '
          'recorded the trace this compares against.',
    );
  });
}

List<VehicleInput> _laps({required int seed, required int steps}) {
  final dice = GameRandom(seed);
  final inputs = <VehicleInput>[];
  var steer = 0.0;
  for (var i = 0; i < steps; i++) {
    if (i % 23 == 0) steer = dice.nextDouble() * 2.0 - 1.0;
    inputs.add(
      VehicleInput()
        ..throttle = dice.nextDouble() < 0.75 ? 1.0 : 0.0
        ..brake = dice.nextDouble() < 0.1 ? 1.0 : 0.0
        ..steer = steer
        ..handbrake = dice.nextInt(97) == 0,
    );
  }
  return inputs;
}

final class _Ground implements GroundField {
  @override
  bool sample(Vector3 position, double nearHint, GroundSample out) {
    out
      ..s = position.z
      ..lateral = position.x
      ..onRoad = true
      ..barrier = false
      ..halfWidth = 0.0
      ..surface = null
      ..height = 0.0;
    out.normal.setValues(0.0, 1.0, 0.0);
    return true;
  }
}

DigestTrace _drive(List<VehicleInput> inputs, {int every = 25}) {
  const tuning = VehicleTuning();
  final world = CollisionWorld();
  final car = SphereVehicle(
    world: world,
    ground: _Ground(),
    position: Vector3(0.0, tuning.rideHeight, 0.0),
    tuning: tuning,
    tyres: Tyres.road,
  );
  final trace = DigestTrace(every: every);
  const dt = 1.0 / 60.0;

  for (var step = 1; step <= inputs.length; step++) {
    car.step(dt, inputs[step - 1]);
    world.update();
    trace.observe(step, <String, Object?>{
      'car': car.save(),
      'speed': car.speed,
      'yaw': car.headingYaw,
      'slip': car.slipAngle,
    });
  }
  return trace;
}

/// The same trace `packages/flutter3d_game_racing/test/parity_test.dart`
/// recorded on macOS-arm64 under the VM, 2026-09-05.
const List<String> _recorded = <String>[
  '24ac3284',
  '2174d61e',
  '4e2148ff',
  'da32b826',
  '15d2cb6e',
  '1a50ab8f',
  '7e2e3e7e',
  '9f1ca66d',
  'c53860b8',
  '4407aee5',
  'e1d0489d',
  '69c728fd',
  '76fc7877',
  'be3b49eb',
  '3f0a613a',
  'b49e656d',
  'e3ec2c6a',
  'e5360ba4',
  'f647f887',
  '4e912215',
  'd36c6203',
  'd8489fc1',
  'ac964840',
  '072f4a81',
  '61bed764',
  '6fe91816',
  'b55892eb',
  '2b56c5c1',
  'ff92ab0d',
  'b86fa260',
  'b1200694',
  '9346ce2d',
  'e53f0a89',
  '7caa7ec2',
  '90ac7fda',
  '42939720',
  '1eaa9264',
  'e4bfa32c',
  'bc6bc0e4',
  '4b114d3d',
];
