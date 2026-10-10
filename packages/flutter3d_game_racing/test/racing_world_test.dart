/// A car in its world: it falls by the world's gravity and grips by it.
///
///     flutter test test/racing_world_test.dart
library;

import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

final class _Flat with GroundField {
  @override
  bool sample(Vector3 position, double nearHint, GroundSample out) {
    out
      ..s = position.z
      ..lateral = position.x
      ..onRoad = true
      ..barrier = false
      ..halfWidth = 0.0
      ..surface = 'asphalt'
      ..height = 0.0;
    out.normal.setValues(0.0, 1.0, 0.0);
    return true;
  }
}

const double _step = 1 / 60;

SphereVehicle _car(WorldProperties world, {double height = 0.0}) {
  const tuning = VehicleSettings();
  return SphereVehicle(
    world: CollisionWorld(properties: world),
    ground: _Flat(),
    position: Vector3(0.0, tuning.rideHeight + height, 0.0),
  );
}

/// How far a car takes to stop from 25 m/s in [world].
double _stopping(WorldProperties world) {
  final car = _car(world);
  final throttle = VehicleInput()..throttle = 1.0;
  for (var i = 0; i < 60 * 30 && car.speed < 25.0; i++) {
    car.step(_step, throttle);
  }
  final start = car.position.clone();
  final brake = VehicleInput()..brake = 1.0;
  for (var i = 0; i < 60 * 60 && car.speed > 1.0; i++) {
    car.step(_step, brake);
  }
  return car.position.distanceTo(start);
}

void main() {
  test('the race world falls at the racing gravity', () {
    expect(racingWorld.gravityMagnitude, racingGravity);
  });

  test("a car dropped falls by its world's gravity", () {
    // Mutation: read a gravity of the car's own and both fall alike.
    final race = _car(racingWorld, height: 50.0);
    final moon = _car(
      WorldProperties(gravity: Vector3(0.0, -1.62, 0.0)),
      height: 50.0,
    );
    final coast = VehicleInput();
    for (var i = 0; i < 30; i++) {
      race.step(_step, coast);
      moon.step(_step, coast);
    }
    expect(
      race.velocity.y / moon.velocity.y,
      closeTo(racingGravity / 1.62, 0.05),
    );
  });

  test("a tyre's grip is a multiple of its world's gravity", () {
    // A tyre of 1.05 g holds 1.05 × 20 m/s² in the race's world and a
    // quarter of that in a world at a quarter of its gravity, so it stops
    // in about four times the distance.
    final race = _stopping(racingWorld);
    final light = _stopping(
      WorldProperties(gravity: Vector3(0.0, -racingGravity / 4.0, 0.0)),
    );
    expect(light, greaterThan(2.5 * race));
  });

  test('thinner air drags a car less', () {
    WorldProperties air(double pressure) =>
        racingWorld.copyWith(airPressure: pressure);
    double coastFrom40(WorldProperties world) {
      final car = _car(world)..velocity.setValues(0.0, 0.0, 40.0);
      final coast = VehicleInput();
      for (var i = 0; i < 120; i++) {
        car.step(_step, coast);
      }
      return car.speed;
    }

    expect(
      coastFrom40(air(standardAtmosphere / 2.0)),
      greaterThan(coastFrom40(racingWorld)),
    );
  });
}
