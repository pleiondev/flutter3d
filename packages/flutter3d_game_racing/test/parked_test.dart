/// A car nobody is driving stays where it was left.
///
///     flutter test test/parked_test.dart
///
/// **It did not.** Every scene this package was tested against was flat, and on
/// a flat floor a car with no rolling resistance behaves exactly like a car with
/// some: it sits still because nothing pushes it. The circuit is not flat —
/// `ring.json` runs from −3.36 m to +6.75 m and the starting grid sits on about
/// a one-in-fifty rise — and there `_applyGravityAndDrag` put the downhill
/// component of gravity into the velocity every step with nothing opposing it.
/// A driver who touched nothing rolled backwards, gaining speed, from the
/// moment the level loaded.
///
/// The two rules below are what a real car has and this one did not: a little
/// resistance to rolling at all, and enough static grip that a slope this gentle
/// does not start it moving. Neither is allowed to hold a car on a wall, which
/// is what the last test is for.
library;

import 'dart:math' as math;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A floor tilted by [grade], as a fraction: 0.02 is one in fifty.
///
/// Tilted about x, so the slope runs along z — which is the axis a car with a
/// heading of zero points down, and therefore the one where a roll shows up as
/// forward speed rather than as sideways drift.
final class _Slope implements GroundField {
  _Slope(this.grade);

  final double grade;

  @override
  bool sample(Vector3 position, double nearHint, GroundSample out) {
    final normal = Vector3(0.0, 1.0, -grade)..normalize();
    out
      ..height = position.z * grade
      ..normal.setFrom(normal)
      ..surface = null;
    return true;
  }
}

({SphereVehicle car, CollisionWorld world}) onSlope(double grade) {
  const tuning = VehicleTuning();
  final world = CollisionWorld();
  final car = SphereVehicle(
    world: world,
    ground: _Slope(grade),
    position: Vector3(0.0, tuning.rideHeight, 0.0),
    tuning: tuning,
    tyres: Tyres.road,
  );
  return (car: car, world: world);
}

/// Drives [seconds] of simulated time with nothing pressed.
void coast(SphereVehicle car, {double seconds = 10.0}) {
  final steps = (seconds * 60).round();
  for (var i = 0; i < steps; i++) {
    car.step(1 / 60, VehicleInput());
  }
}

double alongSlope(SphereVehicle car) {
  final heading = Vector3(
    math.sin(car.headingYaw),
    0.0,
    math.cos(car.headingYaw),
  );
  return car.velocity.dot(heading);
}

void main() {
  test('a car parked on the grid does not roll away', () {
    // The defect, at the grade the circuit's starting straight actually has.
    // Ten seconds of it: before the fix this reached 3.97 m/s — fourteen
    // kilometres an hour, backwards, from a standing start nobody touched — and
    // was still gaining.
    //
    // Mutation: drop the static hold in `_rollAndHold`. The car rolls, and the
    // number in the failure is how fast it was going when the test gave up.
    final it = onSlope(0.02);
    coast(it.car);

    expect(
      alongSlope(it.car).abs(),
      lessThan(0.1),
      reason:
          'the car rolled to ${alongSlope(it.car).toStringAsFixed(2)} m/s on a '
          'one-in-fifty slope with nothing pressed',
    );
    expect(
      it.car.position.z.abs(),
      lessThan(0.5),
      reason:
          'and travelled ${it.car.position.z.toStringAsFixed(2)} m doing it',
    );
  });

  test('and a gentle slope does not creep either', () {
    // Half the grade, twice the patience. A hold that only just covers the
    // circuit would leave every shallower rise creeping, which is the same
    // defect in a form nobody reports because it takes a minute to notice.
    //
    // Mutation: make the hold's slope ceiling smaller than the circuit's grade.
    final it = onSlope(0.01);
    coast(it.car, seconds: 20.0);
    expect(alongSlope(it.car).abs(), lessThan(0.1));
  });

  test('but a hill is still a hill', () {
    // The other direction, and the reason the hold has a ceiling: a car left on
    // something genuinely steep has to roll down it. A hold with no limit is a
    // handbrake that is always on, and a track with a drop into a gully would
    // have cars sitting on its wall.
    //
    // Mutation: remove the slope ceiling from the hold. This fails; the two
    // tests above pass either way.
    final it = onSlope(0.4);
    coast(it.car, seconds: 4.0);
    expect(
      alongSlope(it.car).abs(),
      greaterThan(2.0),
      reason: 'a car on a one-in-two-and-a-half slope stayed put',
    );
  });

  test('and rolling still costs something', () {
    // Resistance to rolling, which is the half of this that is not the hold: a
    // car let off the throttle slows down rather than coasting for ever. Air
    // drag cannot stand in for it — drag goes as the square of the speed, so
    // below about twenty it is worth almost nothing.
    //
    // Driven up to speed rather than given a velocity, because a car handed one
    // has wheels that are not turning, and the tyre model then answers that
    // enormous slip by stopping it dead. That is correct and it is not what this
    // test is about.
    //
    // Mutation: set `rollingResistance` to zero. The car keeps nearly all of
    // its speed and this fails.
    final it = onSlope(0.0);
    for (var i = 0; i < 120; i++) {
      it.car.step(1 / 60, VehicleInput()..throttle = 1.0);
    }
    final entered = alongSlope(it.car);
    expect(entered, greaterThan(4.0), reason: 'it never got going');

    coast(it.car, seconds: 3.0);
    final left = alongSlope(it.car);

    expect(
      left,
      lessThan(entered - 2.0),
      reason:
          'it entered the coast at ${entered.toStringAsFixed(2)} m/s and still '
          'had ${left.toStringAsFixed(2)} three seconds later',
    );
    expect(left, greaterThan(0.0), reason: 'it stopped dead or reversed');
  });
}
