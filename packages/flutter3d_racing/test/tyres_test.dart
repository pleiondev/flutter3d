/// The three sets of tyres, and what choosing one costs.
///
///     flutter test test/tyres_test.dart
///
/// **Not a ladder.** Every number here has to be a trade or the choice is not
/// one: slicks that were quicker everywhere would be the only sensible answer,
/// and a game with one sensible answer is a game with no decision in it. What
/// each of these tests measures is a place where one set beats another and the
/// place where the same set pays for it.
library;

import 'dart:math' as math;

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_racing/flutter3d_racing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

final class _Ground implements GroundField {
  _Ground({this.surface});

  final String? surface;

  @override
  bool sample(Vector3 position, double nearHint, GroundSample out) {
    out
      ..s = position.z
      ..lateral = position.x
      ..onRoad = true
      ..barrier = false
      ..halfWidth = 0.0
      ..surface = surface
      ..height = 0.0;
    out.normal.setValues(0.0, 1.0, 0.0);
    return true;
  }
}

const double _step = 1 / 60;

SphereVehicle _car(Tyres tyres, {String surface = 'asphalt'}) {
  const tuning = VehicleTuning();
  return SphereVehicle(
    world: CollisionWorld(),
    ground: _Ground(surface: surface),
    position: Vector3(0.0, tuning.rideHeight, 0.0),
    tuning: tuning,
    tyres: tyres,
  );
}

void _run(SphereVehicle car, VehicleInput input, double seconds) {
  for (var step = 0; step < (seconds / _step).round(); step++) {
    car.step(_step, input);
  }
}

/// How far a car takes to stop from [from] metres a second.
///
/// Braking rather than cornering because it is one number with a unit, and
/// because it spends the same grip: what stops a car is what turns it.
double _brakingDistance(Tyres tyres, {String surface = 'asphalt', double from = 30.0}) {
  final car = _car(tyres, surface: surface);
  final throttle = VehicleInput()..throttle = 1.0;
  for (var step = 0; step < 60 * 30 && car.speed < from; step++) {
    car.step(_step, throttle);
  }
  final start = car.position.clone();
  final brake = VehicleInput()..brake = 1.0;
  for (var step = 0; step < 60 * 30 && car.speed > 1.0; step++) {
    car.step(_step, brake);
  }
  return car.position.distanceTo(start);
}

/// The hardest the car can be made to turn, in metres per second squared.
///
/// **Where the limit shows and braking does not.** A brake pedal asks for
/// 26 m/s² and the tyres are asked for whatever is left over, so above about a
/// gravity of grip the stopping distance is set by the brakes rather than by
/// the rubber — which is why a set of tyres worth a quarter more grip stops
/// barely two metres shorter and corners a fifth harder. Nothing puts a ceiling
/// on cornering but the tyres.
double _peakCornering(Tyres tyres, {String surface = 'asphalt', double from = 25.0}) {
  final car = _car(tyres, surface: surface);
  final throttle = VehicleInput()..throttle = 1.0;
  for (var step = 0; step < 60 * 30 && car.speed < from; step++) {
    car.step(_step, throttle);
  }

  final turn = VehicleInput()
    ..throttle = 0.35
    ..steer = 1.0;
  var worst = 0.0;
  for (var step = 0; step < 180; step++) {
    final was = Vector3.copy(car.velocity);
    car.step(_step, turn);
    final acceleration = (car.velocity - was)..scale(1.0 / _step);
    // Across the car rather than across the world: what a tyre is holding is
    // the sideways force, and the car is turning while it holds it.
    final forward =
        Vector3(math.sin(car.headingYaw), 0.0, math.cos(car.headingYaw));
    final sideways = Vector3(forward.z, 0.0, -forward.x);
    worst = math.max(worst, acceleration.dot(sideways).abs());
  }
  return worst;
}

void main() {
  group('on the road', () {
    test('slicks stop shorter than road tyres, and rally tyres do not', () {
      // Measured, from thirty metres a second to walking pace: 22.2 m on
      // slicks, 24.1 m on road tyres, 27.2 m on rally tyres. Two metres and
      // three — a corner's worth over a lap, not a different game.
      final slicks = _brakingDistance(Tyres.slicks);
      final road = _brakingDistance(Tyres.road);
      final rally = _brakingDistance(Tyres.rally);

      expect(slicks, lessThan(road),
          reason: 'slicks are ${slicks}m against road tyres\' ${road}m');
      expect(rally, greaterThan(road),
          reason: 'rally tyres are ${rally}m against road tyres\' ${road}m');
    });

    test('and corner harder, which is where the grip actually shows', () {
      // Measured at twenty-five metres a second: 23.3 m/s² on slicks, 19.0 on
      // road tyres, 16.0 on rally tyres — a fifth either way, against two
      // metres of braking. **This is the test that holds `limit` up**: replacing
      // it with a constant leaves every braking figure inside its tolerance,
      // because the brakes run out before the tyres do.
      final slicks = _peakCornering(Tyres.slicks);
      final road = _peakCornering(Tyres.road);
      final rally = _peakCornering(Tyres.rally);

      expect(slicks, greaterThan(road * 1.1),
          reason: 'slicks pull $slicks against road tyres\' $road');
      expect(rally, lessThan(road * 0.95),
          reason: 'rally tyres pull $rally against road tyres\' $road');
    });
  });

  group('off it', () {
    test('and on grass they corner the other way round too', () {
      final slicks = _peakCornering(Tyres.slicks, surface: 'grass', from: 15.0);
      final rally = _peakCornering(Tyres.rally, surface: 'grass', from: 15.0);

      expect(rally, greaterThan(slicks * 1.5),
          reason: 'a car on slicks turns on grass: $slicks against $rally');
    });

    test('and on grass the order turns round completely', () {
      // The trade, in one assertion. A driver on slicks who puts two wheels on
      // the grass has thrown away more than the tarmac ever gave them.
      // From twenty metres a second: 92.2 m on slicks, 30.6 m on road tyres,
      // 14.5 m on rally tyres. The slicks do not stop so much as run out of
      // speed eventually.
      final slicks = _brakingDistance(Tyres.slicks, surface: 'grass', from: 20.0);
      final road = _brakingDistance(Tyres.road, surface: 'grass', from: 20.0);
      final rally = _brakingDistance(Tyres.rally, surface: 'grass', from: 20.0);

      expect(rally, lessThan(road),
          reason: 'rally tyres are ${rally}m against road tyres\' ${road}m');
      expect(slicks, greaterThan(road),
          reason: 'slicks are ${slicks}m against road tyres\' ${road}m');
      expect(slicks, greaterThan(rally * 1.5),
          reason: 'the price of slicks off the road is not worth paying '
              'attention to: ${slicks}m against ${rally}m');
    });
  });

  test('and the shape differs as well as the number', () {
    // A fast tyre and a forgiving one are not the same axis. Past the peak,
    // slicks keep less of their grip than rally tyres do — which is why one
    // lets go suddenly and the other slides.
    expect(Tyres.slicks.model.lateralAt(1.2).abs(),
        lessThan(Tyres.rally.model.lateralAt(1.2).abs()),
        reason: 'both tyres behave the same once the car is sideways');
    expect(Tyres.slicks.model.peakSlipAngle,
        lessThan(Tyres.rally.model.peakSlipAngle),
        reason: 'the limit arrives at the same place on both');
  });

  group('changing them', () {
    test('is refused while the car is moving', () {
      // **The whole price.** Nothing would go wrong mechanically — a set of
      // tyres is a table of numbers — and that is exactly the problem: a driver
      // who could change at speed would hold slicks down the straight and
      // knobbly tyres through the gravel, and a choice with no cost is not one.
      final car = _car(Tyres.road);
      _run(car, VehicleInput()..throttle = 1.0, 2.0);
      expect(car.speed, greaterThan(5.0), reason: 'the car never moved');

      expect(car.fitTyres(Tyres.slicks), isFalse);
      expect(car.tyres, Tyres.road);
    });

    test('and allowed at a standstill', () {
      final car = _car(Tyres.road);

      expect(car.fitTyres(Tyres.slicks), isTrue);
      expect(car.tyres, Tyres.slicks);
    });

    test('and takes effect immediately, without rebuilding the car', () {
      // The reason `tyres` is not final. A car is a lot of state — where it is
      // on the lap, how fast its wheels are turning — and throwing it away to
      // change a table of numbers would put the driver back on the grid.
      final car = _car(Tyres.road);
      final where = car.position.clone();

      car.fitTyres(Tyres.rally);

      expect(car.grips.gripFor('grass'), Tyres.rally.grips.gripFor('grass'));
      expect(car.tires.peakSlipAngle, Tyres.rally.model.peakSlipAngle);
      expect(car.position, where);
    });

    test('and cycling goes round rather than off the end', () {
      var tyres = Tyres.all.first;
      final seen = <Tyres>{};
      for (var i = 0; i < Tyres.all.length; i++) {
        seen.add(tyres);
        tyres = Tyres.after(tyres);
      }

      expect(seen.length, Tyres.all.length, reason: 'a set nobody can reach');
      expect(tyres, Tyres.all.first, reason: 'it does not come back round');
    });

    test('and a name this build no longer ships reads as the first set', () {
      // What a saved document does when a compound is renamed or dropped: the
      // tyres every car starts on, rather than a crash on the launch after an
      // update.
      expect(Tyres.named('unobtainium'), Tyres.road);
      expect(Tyres.named(null), Tyres.road);
      expect(Tyres.named('rally'), Tyres.rally);
    });
  });
}
