/// A lap driven on two platforms, and the one checkpoint where it is not the
/// same lap.
///
///     flutter test test/parity_test.dart
///     flutter test --platform chrome test/parity_test.dart
///
/// **This is the counter-example the other parity file needs.**
/// `flutter3d_game/test/parity_test.dart` drove a character controller for a
/// thousand steps and got all forty checkpoints identical between the VM and
/// Chrome — and separately found that every transcendental in `dart:math`
/// gives different bits in the two places. Both are true, and the gap between
/// them is where the design decision lives: two libms disagree on a small
/// fraction of arguments, and whether a run diverges is a question about which
/// arguments that particular run reaches.
///
/// A car reaches them, and not rarely. The same measurement here, on the same
/// day and the same machine, disagrees at **twenty-three checkpoints of
/// forty**, first at step 75. So the character controller's clean sweep is a
/// property of that simulation and not of the engine: walking reaches almost
/// no transcendental, and driving is made of them — `math.tan` in the
/// bicycle-model steering, `math.atan` twice a step per tyre in the Pacejka
/// curve, `math.atan2` for the slip angle, and `math.tan` again in the
/// coefficient the curve is built from.
///
/// ## The substitution that was tried, and why it is not here
///
/// Routing those call sites through `sin(x) / cos(x)` and `atan2(x, 1)` — both
/// of which the twelve-argument version of the primitives table wrongly
/// reported as portable — cut the disagreement from twenty-three checkpoints
/// to one. That is a large effect and it is **not** a fix: the substitutes are
/// not portable either, and a change justified by "it diverges less often" is
/// one whose failures are rarer and no less real. It was reverted rather than
/// kept, and the number is recorded here because it says something worth
/// knowing — the divergence is concentrated in `tan` and `atan`, and the
/// remaining sliver lives in `atan2` and `sin`.
///
/// ## What this settles
///
/// A verifying server cannot compare whole runs and call a mismatch cheating.
/// For a genre made of transcendentals it cannot compare runs across platforms
/// at all. Either the server replays a run on the platform it was played on, or
/// the simulation stops calling functions whose answers are a property of the
/// machine — a polynomial, a table, or a quantised argument, all of which are
/// work and none of which is done. Whichever is chosen, the checkpoints are how
/// a mismatch is localised, and a mismatch is a quarantine somebody looks at
/// rather than a verdict.
///
/// The scenario is a car and not a track. A circuit would make this a test of
/// the track reader too, and would hide the arithmetic behind a document; a
/// flat ground with a scripted driver runs the same tyre curve, the same
/// bicycle-model steering and the same slide term on every step, which is
/// where the functions in question are called.
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('a thousand steps of a car', () {
    test('is one of the two drives that were recorded', () {
      // Two accepted traces and not one, and that is the finding rather than a
      // weakening of the test: the VM and Chrome drove measurably different
      // cars. A third answer means a third arithmetic, and is worth the red.
      final trace = _drive(_laps(seed: 20260902, steps: 1000));
      final onVm = trace.divergenceFromHex(_recordedOnTheVm);
      final inChrome = trace.divergenceFromHex(_recordedInChrome);
      expect(
        onVm == null || inChrome == null,
        isTrue,
        reason:
            'this platform drove a car that is neither of the two recorded '
            'ones. Against the VM: $onVm. Against Chrome: $inChrome. Check '
            'the primitives table in flutter3d_game/test/parity_test.dart '
            'first — if a row there has gained an answer, this is downstream '
            'of it.',
      );
    });

    test('and the two recorded drives disagree from step 75 onwards', () {
      // The measurement, pinned compactly. If a change to the vehicle moves
      // either number, that is a real result about how far the two platforms'
      // arithmetic carries into the physics, and it should be read rather than
      // absorbed.
      final differing = <int>[
        for (var i = 0; i < _recordedOnTheVm.length; i++)
          if (_recordedOnTheVm[i] != _recordedInChrome[i]) (i + 1) * 25,
      ];
      expect(differing.length, 23, reason: 'of forty checkpoints');
      expect(differing.first, 75);
    });

    test('and driving it twice in one process gives the same drive twice', () {
      final inputs = _laps(seed: 11, steps: 400);
      expect(_drive(inputs).digests, _drive(inputs).digests);
    });

    test('and a different driver is a different drive', () {
      // Without this the file could be reporting that a car left at rest stays
      // at rest on both platforms, which is true and worth nothing.
      expect(
        _drive(_laps(seed: 11, steps: 400)).digests,
        isNot(_drive(_laps(seed: 12, steps: 400)).digests),
      );
    });
  });
}

/// What the driver did, generated rather than written down.
///
/// [GameRandom] for the same reason the other parity file gives: it is the one
/// generator this repository has proved gives the same sequence everywhere, so
/// rolling the inputs costs nothing in what the measurement is worth. The
/// driver is deliberately clumsy — full throttle and full lock in alternating
/// bursts, with the brakes and the handbrake thrown in — because a car driven
/// smoothly never reaches the part of the tyre curve past the peak, which is
/// the part built out of the functions being asked about.
List<VehicleInput> _laps({required int seed, required int steps}) {
  final dice = GameRandom(seed);
  final inputs = <VehicleInput>[];
  var steer = 0.0;
  for (var i = 0; i < steps; i++) {
    // Held for a stretch and then changed, rather than rerolled every step: a
    // steering input that is noise averages to straight ahead and never loads
    // a tyre.
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

/// An endless flat floor, so that the measurement is about the car.
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

/// Drives [inputs] and digests the car every twenty-five steps.
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
      // Read back through the interface as well as through the save, because
      // the two are not the same set: `slipAngle` is what the tyre curve is
      // driven by and `save` has no reason to carry it.
      'speed': car.speed,
      'yaw': car.headingYaw,
      'slip': car.slipAngle,
    });
  }
  return trace;
}

/// Recorded on macOS-arm64, 2026-09-02, with the vehicle exactly as it ships.
///
/// The two disagree at twenty-three of the forty checkpoints, from step 75
/// onwards. See the head of this file.
const List<String> _recordedOnTheVm = <String>[
  '24ac3284',
  '2174d61e',
  '4e2148ff',
  'da32b826',
  '15d2cb6e',
  '07bd742d',
  '7e2e3e7e',
  'f9992e27',
  'c53860b8',
  '55884eff',
  '08c3845f',
  '69c728fd',
  'e9787997',
  'be3b49eb',
  '3f0a613a',
  '92deac35',
  'e65b2164',
  '51e8f616',
  '7075711f',
  'e7eee819',
  '40a823f3',
  '4b32e2f3',
  'ae5e0f18',
  '6ed41883',
  'ccf45de4',
  '89afc922',
  'f0e4e4eb',
  '8f14c4e1',
  'a1f69a55',
  '434a0238',
  'd5cc19f4',
  '98f08b5d',
  'c086af09',
  '051c8720',
  '287fd48c',
  'c4145b4a',
  '26aee62c',
  '5a081168',
  '553c8424',
  '4e3a7f45',
];

/// The same drive in Chrome on the same machine, the same day.
const List<String> _recordedInChrome = <String>[
  '24ac3284',
  '2174d61e',
  'b2f4027f',
  '64f1f9d2',
  '15d2cb6e',
  '07bd742d',
  '7e2e3e7e',
  '9f1ca66d',
  'c53860b8',
  '5de3b717',
  '76cc22fb',
  '2b018235',
  'c1107bf7',
  '302dde5b',
  '18705bea',
  '4d5290fd',
  'e65b2164',
  '51e8f616',
  'a049efff',
  'fb868765',
  '40a823f3',
  '4b32e2f3',
  'fbf4da4c',
  'd7f1ab87',
  '67fc2f44',
  '743a15ce',
  '524f5d0b',
  'eff60119',
  'e5fdc0e9',
  '34f601a0',
  'd5cc19f4',
  '98f08b5d',
  'c086af09',
  '051c8720',
  '287fd48c',
  'c4145b4a',
  '26aee62c',
  '78737bf4',
  'ed5738b8',
  'dc4a50f1',
];
