import 'dart:math' as math;

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('room air is what the tables say', () {
    // Dry air at 20 °C and an atmosphere: 1.204 kg/m³ and 18.1 µPa·s;
    // water's saturation pressure there, 2339 Pa.
    final dry = Atmosphere(humidity: 0.0);
    expect(dry.density, closeTo(1.204, 1.204 * 0.005));
    expect(dry.viscosity, closeTo(1.81e-5, 1.81e-5 * 0.01));
    expect(
      VapourCurve.water.saturationPressure(293.15),
      closeTo(2339.0, 2339.0 * 0.005),
    );
    // Damp air is lighter: water vapour is lighter than the air it
    // displaces.
    expect(Atmosphere(humidity: 1.0).density, lessThan(dry.density));
  });

  test('a millimetre drop falls at the speed Gunn and Kinzer measured', () {
    // 4.03 m/s for a drop a millimetre across (Gunn and Kinzer, 1949).
    // Mutation: leave the air out, and it is still gathering speed at
    // thirty metres a second.
    const d = 0.001;
    // One particle holding a millimetre drop's volume.
    final spacing = math.pow(math.pi / 6.0, 1.0 / 3.0) * d;
    final fluid = ParticleFluid(medium: FluidMedium.water, spacing: spacing)
      ..inject(math.pi / 6.0 * d * d * d, Vector3(0, 100, 0), Vector3.zero());
    final air = Atmosphere();
    final before = fluid.positions.single.y;
    for (var i = 0; i < 240 * 3; i++) {
      fluid.step(1 / 240, gravity: Vector3(0, -9.81, 0), air: air);
    }
    final y0 = fluid.positions.single.y;
    fluid.step(1 / 240, gravity: Vector3(0, -9.81, 0), air: air);
    final speed = (y0 - fluid.positions.single.y) * 240;
    expect(before, greaterThan(y0));
    // Schiller and Naumann's is a rigid sphere's drag, and gives 3.83: a
    // drop's inside circulates and it falls a little faster than a ball,
    // which this does not model. Within six percent of the measurement.
    expect(speed, closeTo(4.03, 4.03 * 0.06));
  });

  test('a wind across a stream carries it downwind', () {
    Vector3 lowest(Atmosphere? air) {
      final jet = Jet(medium: FluidMedium.water, breakupGrowth: 1e9);
      for (var k = 0; k < 200; k++) {
        jet.emit(
          flow: 1e-6,
          dt: 1 / 1000,
          point: Vector3(0, 1, 0),
          velocity: Vector3(0, -0.1, 0),
          width: 0.002,
          across: Vector3(0, 0, 1),
        );
        jet.step(1 / 1000, gravity: Vector3(0, -9.81, 0), air: air);
      }
      return jet.runs.single.last.position;
    }

    // Mutation: drop the drag, and the stream falls straight.
    expect(lowest(null).x, closeTo(0.0, 1e-12));
    final blown = lowest(Atmosphere(wind: Vector3(3, 0, 0)));
    expect(blown.x, greaterThan(1e-4));
  });

  test('a puddle evaporates, leaves what was in it, and is counted', () {
    final world = FluidWorld(
      gravity: Vector3(0, -9.81, 0),
      floor: [PlaneObstacle(normal: Vector3(0, 1, 0), offset: 0)],
      atmosphere: Atmosphere(humidity: 0.3),
    );
    final bench = world.spills.single
      ..receive(
        1e-7,
        Vector3(0, 0.001, 0),
        Vector3.zero(),
        FluidMedium.water,
        const {'salt': 2.0},
      );
    final total = world.volume;
    final puddle = bench.puddles.single;
    for (var i = 0; i < 240 * 60; i++) {
      world.advance(world.step);
    }
    // A minute in drier air takes some of it.
    expect(world.evaporated, greaterThan(0.0));
    expect(puddle.volume, lessThan(1e-7));
    // The salt stayed: the same amount in less water.
    expect(
      puddle.concentrations['salt']! * puddle.volume,
      closeTo(2.0 * 1e-7, 1e-15),
    );
    // Mutation: lose the vapour from the count, and the world is short.
    expect(world.volume, closeTo(total, total * 1e-9));
  });

  test('flat, a puddle evaporates as a disc does, 4·R·D·Δc', () {
    final air = Atmosphere(humidity: 0.5);
    final flat = FluidMedium.water.copyWith(contactAngle: 0.0);
    final puddle = Puddle(
      medium: flat,
      centre: Vector3.zero(),
      normal: Vector3(0, 1, 0),
    )..add(1e-6, Vector3.zero(), const {});
    final r = puddle.radius(9.81);
    final gone = puddle.evaporate(1.0, air, 9.81);
    final disc =
        4.0 *
        r *
        air.vapourDiffusivity *
        air.vapourDeficit(flat) /
        flat.density;
    expect(gone, closeTo(disc, disc * 0.03));
  });

  test('a tube evaporates up the air over its liquid and out of its mouth', () {
    // Stefan's tube: L/(D·A) for the column to the mouth, then 1/(4·D·r)
    // from the mouth out, in series. An hour, in one go.
    const r = 0.008;
    final tube = LiquidBody(
      shape: RevolvedVessel([Vector2(0, 0), Vector2(r, 0), Vector2(r, 0.1)]),
      medium: FluidMedium.water,
      volume: math.pi * r * r * 0.06,
      modes: 2,
    )..place(Matrix3.identity(), Vector3.zero());
    tube.pour(0.0, concentrations: const {});
    final air = Atmosphere(humidity: 0.5);
    final before = tube.volume;
    final gone = tube.evaporate(3600.0, air);
    final d = air.vapourDiffusivity;
    final column = 0.1 - tube.height;
    final rate =
        air.vapourDeficit(FluidMedium.water) /
        (column / (d * math.pi * r * r) + 1.0 / (4.0 * d * r));
    expect(gone, closeTo(rate * 3600.0 / 998.2, rate * 3600.0 / 998.2 * 0.01));
    expect(tube.volume, closeTo(before - gone, 1e-18));
    // About three microlitres an hour: why an open tube on a bench keeps.
    expect(gone, inInclusiveRange(1e-9, 1e-8));
  });
}
