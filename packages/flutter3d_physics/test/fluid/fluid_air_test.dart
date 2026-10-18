import 'dart:math' as math;

import 'package:flutter3d_matter/flutter3d_matter.dart' show WorldProperties;
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// The air of a world as it is but for [humidity] and [wind].
FluidAir _air({double humidity = 0.5, Vector3? wind}) => FluidAir.of(
  WorldProperties(airHumidity: humidity, wind: wind ?? Vector3.zero()),
);

void main() {
  test('room air is what the tables say', () {
    // Dry air at 20 °C and an atmosphere: 1.204 kg/m³ and 18.1 µPa·s;
    // water's saturation pressure there, 2339 Pa.
    final dry = _air(humidity: 0.0);
    expect(dry.density, closeTo(1.204, 1.204 * 0.005));
    expect(dry.viscosity, closeTo(1.81e-5, 1.81e-5 * 0.01));
    expect(
      VapourCurve.water.saturationPressure(293.15),
      closeTo(2339.0, 2339.0 * 0.005),
    );
    // Damp air is lighter: water vapour is lighter than the air it
    // displaces.
    expect(_air(humidity: 1.0).density, lessThan(dry.density));
    // A world that says its air's density is taken at its word.
    expect(FluidAir.of(WorldProperties(airDensity: 0.5)).density, 0.5);
    // Only water has a vapour curve here: oil is taken not to evaporate.
    expect(dry.vapourDeficit(FluidMedium.oliveOil), 0.0);
    expect(dry.vapourDeficit(FluidMedium.water), greaterThan(0.0));
  });

  test('a millimetre drop falls at about the speed Gunn and Kinzer '
      'measured', () {
    // 4.03 m/s for a drop a millimetre across (Gunn and Kinzer, J. Meteor.
    // 6, 1949). White's drag, the engine's one sphere drag, is a rigid
    // sphere's and settles it at 3.5 in the standard world's damp air: a
    // drop's inside circulates and it falls a little faster than a ball,
    // which this does not model. Mutation: leave the air out, and it is
    // still gathering speed at thirty metres a second.
    const d = 0.001;
    final fluid = ParticleFluid(medium: FluidMedium.water, spacing: 0.002)
      ..inject(math.pi / 6.0 * d * d * d, Vector3(0, 100, 0), Vector3.zero());
    final air = _air();
    for (var i = 0; i < 240 * 3; i++) {
      fluid.step(1 / 240, gravity: Vector3(0, -9.81, 0), air: air);
    }
    final speed = -fluid.drops.single.velocity.y;
    expect(speed, closeTo(4.03, 0.6));
  });

  test('a wind across a stream carries it downwind', () {
    Vector3 lowest(FluidAir? air) {
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

    // Mutation: drop the push across it, and the stream falls straight.
    expect(lowest(null).x, closeTo(0.0, 1e-12));
    expect(lowest(_air()).x, closeTo(0.0, 1e-12));
    expect(lowest(_air(wind: Vector3(3, 0, 0))).x, greaterThan(1e-4));
  });

  test('a puddle evaporates, leaves what was in it, and is counted', () {
    final world = FluidWorld(
      gravity: Vector3(0, -9.81, 0),
      world: WorldProperties(airHumidity: 0.3),
    );
    final bench = PuddleSurface(
      PlaneObstacle(normal: Vector3(0, 1, 0), offset: 0),
    );
    world.puddles.add(bench);
    bench.receive(
      JetLanding(
        volume: 1e-7,
        point: Vector3(0, 0.001, 0),
        concentrations: const {'salt': 2.0},
      ),
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
    final air = _air();
    final flat = FluidMedium.water.copyWith(contactAngle: 0.0);
    final puddle = Puddle(
      medium: flat,
      center: Vector3.zero(),
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
    final air = _air();
    final before = tube.volume;
    final column = 0.1 - tube.height;
    final gone = tube.evaporate(3600.0, air);
    final d = air.vapourDiffusivity;
    final rate =
        air.vapourDeficit(FluidMedium.water) /
        (column / (d * math.pi * r * r) + 1.0 / (4.0 * d * r));
    final expected = rate * 3600.0 / FluidMedium.water.density;
    expect(gone, closeTo(expected, expected * 1e-6));
    expect(tube.volume, closeTo(before - gone, 1e-18));
    // A few microlitres an hour: why an open tube on a bench keeps.
    expect(gone, inInclusiveRange(1e-9, 1e-8));
    // Saturated air takes nothing.
    expect(tube.evaporate(3600.0, _air(humidity: 1.0)), 0.0);
  });
}
