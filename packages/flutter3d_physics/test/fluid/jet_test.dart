import 'dart:math' as math;

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// Runs a steady stream of [flow] from [lip] at [velocity] for [seconds].
Jet _steady({
  required double flow,
  required Vector3 lip,
  required Vector3 velocity,
  required double seconds,
  required Vector3 gravity,
  double width = 0.0,
  double dt = 1 / 1000,
  List<JetObstacle> obstacles = const [],
  List<JetReceiver> receivers = const [],
  void Function(List<JetDrop>)? onDrops,
}) {
  final jet = Jet(medium: FluidMedium.water);
  final round = 2 * math.sqrt(flow / (math.pi * velocity.length));
  for (var t = 0.0; t < seconds; t += dt) {
    jet.emit(
      flow: flow,
      dt: dt,
      point: lip,
      velocity: velocity,
      width: width > 0 ? width : round,
      across: Vector3(0, 0, 1),
    );
    final drops = jet.step(
      dt,
      gravity: gravity,
      obstacles: obstacles,
      receivers: receivers,
    );
    onDrops?.call(drops);
  }
  return jet;
}

void main() {
  test('a stream carries its flow past every height: Q = v·A', () {
    const q = 2e-6;
    final g = Vector3(0, -9.81, 0);
    final jet = _steady(
      flow: q,
      lip: Vector3(0, 1, 0),
      velocity: Vector3(0.3, 0, 0),
      seconds: 0.3,
      gravity: g,
    );
    for (final s in jet.runs.first.skip(5)) {
      // The speed falling gives it, from how far below the lip it is.
      final v = math.sqrt(0.09 + 2 * 9.81 * (1 - s.position.y));
      final passed = math.pi * s.wide * s.thick * v;
      expect(passed, closeTo(q, q * 0.02));
    }
  });

  test('a parcel falls as the world falls, whatever its gravity', () {
    final moon = Vector3(0.2, -1.62, 0);
    const dt = 1e-4;
    // Kept whole: a stream this thin would part into drops on the way.
    final jet = Jet(medium: FluidMedium.water, breakupGrowth: 1e9);
    for (var k = 0; k < 2; k++) {
      jet.emit(
        flow: 1e-6,
        dt: dt,
        point: Vector3.zero(),
        velocity: Vector3(1, 0.5, 0),
        width: 1e-3,
        across: Vector3(0, 0, 1),
      );
      jet.step(dt, gravity: moon);
    }
    for (var i = 0; i < 4998; i++) {
      jet.step(dt, gravity: moon);
    }
    // The first parcel has fallen half a second.
    const t = 0.5;
    final expected = Vector3(1, 0.5, 0) * t + moon * (0.5 * t * t);
    final oldest = jet.runs.first.last.position;
    expect((oldest - expected).length, lessThan(1e-3));
  });

  test('every drop of it is somewhere', () {
    final body = LiquidBody(
      shape: RevolvedVessel([
        Vector2(0, 0),
        Vector2(0.02, 0),
        Vector2(0.02, 0.1),
      ]),
      medium: FluidMedium.water,
      volume: 1e-5,
      modes: 4,
    );
    final before = body.volume;
    final jet = _steady(
      flow: 3e-6,
      lip: Vector3(0, 0.1, 0),
      velocity: Vector3(0, -0.2, 0),
      seconds: 0.4,
      gravity: Vector3(0, -9.81, 0),
      receivers: [body],
    );
    expect(jet.landed, greaterThan(0));
    // Mutation: drop a landed parcel without handing it over, and the
    // vessel is short by what landed.
    expect(
      jet.inFlight + jet.landed + jet.dropped,
      closeTo(jet.emitted, jet.emitted * 1e-12),
    );
    expect(body.volume - before, closeTo(jet.landed, jet.landed * 1e-9));
  });

  test('a stream that meets the inside of a glass runs down it', () {
    const r = 0.02;
    final body = LiquidBody(
      shape: RevolvedVessel([Vector2(0, 0), Vector2(r, 0), Vector2(r, 0.2)]),
      medium: FluidMedium.water,
      volume: 1e-6,
      modes: 4,
    );
    var outside = 0;
    final jet = Jet(medium: FluidMedium.water);
    for (var i = 0; i < 400; i++) {
      // Thick enough to reach the wall whole: a millimetre stream at this
      // speed parts into drops in five centimetres.
      jet.emit(
        flow: 1e-5,
        dt: 1 / 1000,
        point: Vector3(-0.015, 0.19, 0),
        velocity: Vector3(0.6, 0, 0),
        width: 1e-3,
        across: Vector3(0, 0, 1),
      );
      jet.step(
        1 / 1000,
        gravity: Vector3(0, -9.81, 0),
        obstacles: [InsideWalls(body)],
        receivers: [body],
      );
      for (final run in jet.runs) {
        for (final s in run) {
          final p = s.position;
          if (math.sqrt(p.x * p.x + p.z * p.z) > r + 1e-9) outside++;
        }
      }
    }
    // Mutation: let it bounce or pass the wall, and it leaves the glass.
    expect(outside, 0);
    expect(jet.landed, greaterThan(0));
  });

  test('a stream in still air breaks at L/D = 12(√We + 3We/Re)', () {
    // Weightless, so its speed and width stay what they left with.
    const d = 1e-3, v = 1.0;
    final water = FluidMedium.water;
    final q = math.pi * d * d / 4 * v;
    double? first;
    _steady(
      flow: q,
      lip: Vector3.zero(),
      velocity: Vector3(v, 0, 0),
      seconds: 1.0,
      gravity: Vector3.zero(),
      dt: 1 / 4000,
      onDrops: (drops) {
        if (drops.isNotEmpty) first ??= drops.first.position.x;
      },
    );
    final we = water.density * v * v * d / water.surfaceTension;
    final re = water.density * v * d / water.viscosity;
    final length = 12 * (math.sqrt(we) + 3 * we / re) * d;
    expect(first, closeTo(length, length * 0.02));
  });

  test('poured slowly it runs down the outside; quickly, it leaves clean', () {
    const r = 0.02, wall = 0.002;
    final source = LiquidBody(
      shape: RevolvedVessel([Vector2(0, 0), Vector2(r, 0), Vector2(r, 0.1)]),
      medium: FluidMedium.water,
      volume: 1e-6,
      modes: 2,
    );
    double furthest(double speed) {
      final jet = Jet(medium: FluidMedium.water, breakupGrowth: 1e9);
      var most = 0.0;
      for (var i = 0; i < 200; i++) {
        jet.emit(
          flow: 2e-7,
          dt: 1 / 1000,
          point: Vector3(r + wall + 0.0004, 0.1, 0),
          velocity: Vector3(speed, 0, 0),
          width: 1e-3,
          across: Vector3(0, 0, 1),
        );
        jet.step(
          1 / 1000,
          gravity: Vector3(0, -9.81, 0),
          obstacles: [OutsideWalls(source, thickness: wall)],
        );
      }
      for (final run in jet.runs) {
        for (final s in run) {
          most = math.max(most, s.position.x);
        }
      }
      return most;
    }

    final jet = Jet(medium: FluidMedium.water);
    // A slow trickle is held to the glass below the lip: it stays within a
    // couple of millimetres of the outside. Mutation: let go of a parcel the
    // step it leaves the wall, and it falls away.
    expect(furthest(0.03), lessThan(r + wall + 0.003));
    expect(jet.clingSpeed(1e-3), greaterThan(0.03));
    // A quick pour leaves it.
    expect(furthest(1.0), greaterThan(r + wall + 0.05));
  });
}
