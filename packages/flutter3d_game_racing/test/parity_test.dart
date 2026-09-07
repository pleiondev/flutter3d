/// A lap driven on two platforms, and now it is the same lap.
///
///     flutter test test/parity_test.dart
///     flutter test --platform chrome test/parity_test.dart
///
/// **This file used to be the counter-example, and that is what it recorded.**
/// `flutter3d_sim/test/parity_test.dart` drove a character controller for a
/// thousand steps and got all forty checkpoints identical between the VM and
/// Chrome, while separately finding that every transcendental in `dart:math`
/// gives different bits in the two places. Both were true, and the gap between
/// them was the whole problem: two libms disagree on a small fraction of
/// arguments, and whether a run survives is a question about which arguments it
/// happens to reach. A character walking reaches almost none. A car is made of
/// them — the tangent in the bicycle-model steering, an arc tangent twice a
/// step per tyre in the Pacejka curve, an arc tangent for the slip angle — and
/// this drive disagreed at **twenty-three checkpoints of forty**, first at step
/// 75.
///
/// So the test could only ask which of two arithmetics a platform had, and it
/// carried two accepted traces in order to ask it.
///
/// ## What was tried before the answer, and why it was not one
///
/// Routing those call sites through `sin(x) / cos(x)` and `atan2(x, 1)` — both
/// wrongly reported as portable by a twelve-argument version of the primitives
/// table — cut the disagreement from twenty-three checkpoints to one. That is a
/// large effect and it was **not** a fix: the substitutes are not portable
/// either, and a change justified by "it diverges less often" is one whose
/// failures are rarer and no less real. It was reverted.
///
/// ## What it is now
///
/// The vehicle calls `Portable` instead, which answers the same questions out
/// of `+`, `-`, `*`, `/` and `sqrt` — every one of them pinned by the
/// specification rather than supplied by the machine. One recorded trace,
/// matched here and in Chrome. `flutter3d_sim/test/portable_math_test.dart` is
/// the layer below this one, and `tool/structure.dart` holds the call sites to
/// it with the rule *a step asks no machine for an answer*.
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
    test('is the drive that was recorded, wherever it is driven', () {
      // **One accepted trace, where there used to be two.** The pair was the
      // finding: the VM and Chrome drove measurably different cars, so the test
      // could only ask which of the two arithmetics this platform had. The
      // vehicle no longer calls the machine's transcendentals, so there is one
      // answer to accept and a second one is a failure again.
      final trace = _drive(_laps(seed: 20260902, steps: 1000));
      final divergence = trace.divergenceFromHex(_recorded);
      expect(
        divergence,
        isNull,
        reason:
            'this platform drove a different car: $divergence. Everything the '
            'vehicle calls is in `Portable`, whose own test says it gives one '
            'answer everywhere — so check that first: if a row there has '
            'moved, this is downstream of it, and if none has, the difference '
            'is in the vehicle rather than in the arithmetic.',
      );
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

/// Recorded on macOS-arm64 under the VM, 2026-09-05, and matched by Chrome.
///
/// **One table where there were two.** The pair recorded on 2026-09-02
/// disagreed at twenty-three of the forty checkpoints, from step 75 onwards;
/// the head of this file says what that was and what it cost.
///
/// **Matched a third and fourth time on ubuntu-x64, under the VM and under
/// Chrome, in CI run 34121423137 on 2026-09-07** — forty of forty in both. This
/// is the car that used to be the counter-example, so the confirmation is worth
/// more here than anywhere: the arithmetic the tyre curve now runs on carries a
/// run across a processor and an operating system as well as across an engine.
/// No number below changed to earn it.
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
