import 'dart:math' as math;

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

LiquidBody _tube(double radius, double level, FluidMedium m) => LiquidBody(
  shape: RevolvedVessel([
    Vector2(0, 0),
    Vector2(radius, 0),
    Vector2(radius, 0.5),
  ]),
  medium: m,
  volume: math.pi * radius * radius * level,
  modes: 2,
);

/// Joins [a] and [b] at their floors and steps them for [seconds].
List<double> _run(
  LiquidBody a,
  LiquidBody b,
  double seconds, {
  double radius = 0.01,
  double length = 0.1,
  double dt = 1 / 2000,
}) {
  final pipe = Pipe(
    from: a,
    at: Vector3(0, 0.0005, 0),
    to: b,
    toAt: Vector3(0, 0.0005, 0),
    radius: radius,
    length: length,
    minorLoss: 0,
  );
  final gravity = Vector3(0, -9.81, 0);
  final levels = <double>[];
  for (var t = 0.0; t < seconds; t += dt) {
    for (final body in [a, b]) {
      body.place(Matrix3.identity(), Vector3.zero());
    }
    pipe.step(dt, gravity: gravity);
    a.step(dt, gravity: gravity);
    b.step(dt, gravity: gravity);
    levels.add(a.height - b.height);
  }
  return levels;
}

void main() {
  test("a U-tube swings at 2π√(l / 2g)", () {
    // Wide enough that surface tension is nothing beside gravity.
    final a = _tube(0.03, 0.12, FluidMedium.water);
    final b = _tube(0.03, 0.08, FluidMedium.water);
    final total = a.volume + b.volume;
    final d = _run(a, b, 3, radius: 0.03, length: 0.1);
    final crossings = <double>[];
    for (var i = 1; i < d.length; i++) {
      if ((d[i - 1] < 0) != (d[i] < 0)) crossings.add(i / 2000);
    }
    final period = 2 * (crossings[2] - crossings[0]) / 2;
    // The column: the pipe and the liquid standing in each tube.
    const l = 0.1 + 0.1 + 0.1;
    expect(
      period,
      closeTo(2 * math.pi * math.sqrt(l / (2 * 9.81)), 0.03 * 0.78),
    );
    expect(a.volume + b.volume, closeTo(total, total * 1e-12));
  });

  test('a thick liquid creeps to its level without swinging past it', () {
    final a = _tube(0.02, 0.12, FluidMedium.glycerol);
    final b = _tube(0.02, 0.08, FluidMedium.glycerol);
    final d = _run(a, b, 4, radius: 0.002, length: 0.1);
    // Mutation: drop Poiseuille's friction, and it overshoots.
    expect(d.every((x) => x >= -1e-6), isTrue);
    expect(d.last, lessThan(d.first));
  });

  test(
    'a narrow tube joined to a wide one stands higher by the capillary rise',
    () {
      final water = FluidMedium.water;
      final narrow = _tube(0.0015, 0.05, water);
      final wide = _tube(0.02, 0.05, water);
      final d = _run(narrow, wide, 6, radius: 0.0015, length: 0.05);
      final expected =
          TubeMeniscus(medium: water, radius: 0.0015, g: 9.81).rise -
          TubeMeniscus(medium: water, radius: 0.02, g: 9.81).rise;
      // The surfaces' flat levels differ by that, less the meniscus each takes
      // out of its own level.
      final settled =
          d.last +
          TubeMeniscus(medium: water, radius: 0.0015, g: 9.81).meanHeight -
          TubeMeniscus(medium: water, radius: 0.02, g: 9.81).meanHeight;
      expect(settled, closeTo(expected, expected * 0.05));
    },
  );
}
