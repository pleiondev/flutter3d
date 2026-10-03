import 'dart:math' as math;

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

RevolvedVessel _cylinder(double radius, double height) => RevolvedVessel([
  Vector2(0, 0),
  Vector2(radius, 0),
  Vector2(radius, height),
]);

/// An open box: [width] along x, [depth] along z, [height] tall.
MeshVessel _box(double width, double depth, double height) {
  final p = <Vector3>[
    for (final y in [0.0, height])
      for (final (x, z) in [
        (0.0, 0.0),
        (width, 0.0),
        (width, depth),
        (0.0, depth),
      ])
        Vector3(x, y, z),
  ];
  const quads = <List<int>>[
    [0, 1, 2, 3], [4, 7, 6, 5], // floor (down), lid (up)
    [0, 4, 5, 1], [1, 5, 6, 2], [2, 6, 7, 3], [3, 7, 4, 0],
  ];
  return MeshVessel(
    positions: p,
    indices: [
      for (final q in quads) ...[q[0], q[1], q[2], q[0], q[2], q[3]],
    ],
    rim: [p[4], p[5], p[6], p[7]],
  );
}

/// A turn of [angle] about the x axis.
Matrix3 _tilt(double angle) => Matrix3.rotationX(angle);

/// Steps [body] for [seconds] at [dt], recording the surface over [probe].
List<double> _record(
  LiquidBody body,
  Vector3 probe,
  double seconds, {
  double dt = 1 / 1000,
  double g = 9.81,
  Matrix3? turn,
}) {
  final out = <double>[];
  final steps = (seconds / dt).round();
  for (var i = 0; i < steps; i++) {
    body.place(turn ?? Matrix3.identity(), Vector3.zero());
    body.step(dt, gravity: Vector3(0, -g, 0));
    out.add(body.surface.displacement(probe));
  }
  return out;
}

/// The mean period of the oscillation in [samples] taken every [dt].
double _period(List<double> samples, double dt) {
  final crossings = <double>[];
  for (var i = 1; i < samples.length; i++) {
    if ((samples[i - 1] < 0) != (samples[i] < 0)) {
      final t = samples[i - 1] / (samples[i - 1] - samples[i]);
      crossings.add((i - 1 + t) * dt);
    }
  }
  return 2 * (crossings.last - crossings[1]) / (crossings.length - 2);
}

double _omega(double k, double h, double g, FluidMedium m) => math.sqrt(
  (g * k + m.surfaceTension / m.density * k * k * k) *
      (1 - 2 / (math.exp(2 * k * h) + 1)),
);

void main() {
  test("a round vessel's modes are Bessel's", () {
    // ∂J_m/∂r = 0 at the wall: J1' at 1.8412 (the slosh), J2' at 3.0542,
    // J0' = −J1 at 3.8317 (the first ring). Mutation: leave the wall cells
    // their missing neighbours as zeros — a wall that pins the surface — and
    // the first k is J1's zero, 3.8317, instead of 1.8412.
    const r = 0.05;
    final s = FreeSurface(medium: FluidMedium.water, cells: 40)
      ..layOut(_cylinder(r, 0.2), Vector3(0, 1, 0), 0.1);
    final k = s.wavenumbers.map((x) => x * r).toList();
    expect(k[0], closeTo(1.8412, 1.8412 * 0.04));
    expect(k[1], closeTo(1.8412, 1.8412 * 0.04));
    expect(k[2], closeTo(3.0542, 3.0542 * 0.04));
    expect(k.any((x) => (x - 3.8317).abs() < 3.8317 * 0.04), isTrue);
  });

  test("a box's first mode spans its length: k = π / L", () {
    final s = FreeSurface(medium: FluidMedium.water, cells: 40)
      ..layOut(_box(0.2, 0.08, 0.1), Vector3(0, 1, 0), 0.05);
    expect(s.wavenumbers[0], closeTo(math.pi / 0.2, math.pi / 0.2 * 0.02));
  });

  test('a sudden tilt sloshes at the first mode, in the world\'s gravity', () {
    const r = 0.04, h = 0.06;
    for (final g in [9.81, 1.62]) {
      final body = LiquidBody(
        shape: _cylinder(r, 0.2),
        medium: FluidMedium.water,
        volume: math.pi * r * r * h,
      );
      final samples = _record(
        body,
        Vector3(0, h, 0.8 * r),
        3,
        g: g,
        turn: _tilt(0.15),
      );
      final k = 1.8412 / r;
      final expected = 2 * math.pi / _omega(k, h, g, FluidMedium.water);
      // Mutation: drop the tanh, or take g as 9.81 whatever the world says,
      // and the Moon's slosh comes out at Earth's period.
      expect(_period(samples, 1 / 1000), closeTo(expected, expected * 0.04));
    }
  });

  test('viscosity damps the slosh as Stephens and Dodge measured', () {
    const r = 0.04, h = 0.06;
    double decay(FluidMedium m) {
      final body = LiquidBody(
        shape: _cylinder(r, 0.2),
        medium: m,
        volume: math.pi * r * r * h,
        modes: 2,
      );
      final s = _record(body, Vector3(0, h, 0.8 * r), 4, turn: _tilt(0.1));
      // Peaks of |η| over the first and last second.
      double peak(int from, int to) =>
          s.sublist(from, to).map((x) => x.abs()).reduce(math.max);
      return math.log(peak(0, 1000) / peak(3000, 4000)) / 3.0;
    }

    final water = decay(FluidMedium.water);
    final k = 1.8412 / r;
    final w = _omega(k, h, 9.81, FluidMedium.water);
    final nu = FluidMedium.water.kinematicViscosity;
    final ratio = 1.84 * h / r;
    final zeta =
        0.83 *
        math.sqrt(nu / math.sqrt(9.81 * r * r * r)) *
        (1 +
            0.318 /
                ((math.exp(ratio) - math.exp(-ratio)) / 2) *
                (1 + (1 - h / r) / ((math.exp(ratio) + math.exp(-ratio)) / 2)));
    final expected = zeta * w + 2 * nu * k * k;
    expect(water, closeTo(expected, expected * 0.25));
    // Glycerol, fourteen hundred times as viscous, is still in a moment.
    expect(decay(FluidMedium.glycerol), greaterThan(10 * water));
  });

  test('a carried glass tips its liquid as gravity and braking say', () {
    // Accelerating at a along x, the surface settles at atan(a / g).
    const r = 0.04;
    final body = LiquidBody(
      shape: _cylinder(r, 0.2),
      medium: FluidMedium.glycerol,
      volume: math.pi * r * r * 0.08,
      modes: 4,
    );
    const dt = 1 / 500, a = 3.0;
    for (var i = 0; i < 500; i++) {
      final t = i * dt;
      body.place(Matrix3.identity(), Vector3(0.5 * a * t * t, 0, 0));
      body.step(dt, gravity: Vector3(0, -9.81, 0));
    }
    final angle = math.acos(body.up.y);
    expect(angle, closeTo(math.atan(a / 9.81), 1e-3));
    // Liquid left behind piles up at the back, so the surface's normal leans
    // forward. Mutation: add the vessel's acceleration instead of taking it
    // away, and it leans back.
    expect(body.up.x, greaterThan(0));
  });

  test('waves move no liquid: the volume stays, the surface averages flat', () {
    const r = 0.04;
    final body = LiquidBody(
      shape: _cylinder(r, 0.3),
      medium: FluidMedium.water,
      volume: math.pi * r * r * 0.1,
    );
    final start = body.volume;
    final random = math.Random(3);
    for (var i = 0; i < 4000; i++) {
      final tilt = 0.3 * math.sin(i / 300.0);
      body.place(_tilt(tilt), Vector3.zero());
      if (i % 500 == 0) {
        body.surface.knock(
          Vector3(random.nextDouble() * r - r / 2, 0.1, 0),
          0.004,
        );
      }
      body.step(1 / 1000, gravity: Vector3(0, -9.81, 0));
    }
    expect(body.volume, start);
    // Waves hold no liquid above the plane, to a part in ten thousand of a
    // millimetre over the surface. Mutation: keep the flat mode, and a knock
    // adds liquid.
    expect(
      body.surface.displacedVolume.abs(),
      lessThan(1e-7 * body.surface.area),
    );
  });

  test('tipped past its lip a full vessel spills, outwards, then stops', () {
    const r = 0.02;
    final body = LiquidBody(
      shape: _cylinder(r, 0.1),
      medium: FluidMedium.water,
      volume: math.pi * r * r * 0.095,
      modes: 4,
    );
    final start = body.volume;
    var spilled = 0.0;
    Spill? first;
    var last = 0.0;
    for (var i = 0; i < 6000; i++) {
      body.place(_tilt(0.5), Vector3.zero());
      final spill = body.step(1 / 1000, gravity: Vector3(0, -9.81, 0));
      spilled += spill.flow / 1000;
      if (spill.flow > 0) first ??= spill;
      last = spill.flow;
    }
    // And it has stopped.
    expect(last, 0.0);
    expect(spilled, greaterThan(0));
    expect(body.volume + spilled, closeTo(start, start * 1e-9));
    // It left on the low side. The tilt set the liquid rocking, which threw
    // a little more over the lip than the still surface would have let go,
    // so it ends at or a little under what the tipped vessel holds.
    expect(first!.point.z, greaterThan(0));
    final holds = body.shape.holds(body.up);
    expect(body.volume, lessThanOrEqualTo(holds * 1.001));
    expect(body.volume, greaterThan(holds * 0.9));
  });

  test('no wave stands steeper than Stokes\' limit: past it, it breaks', () {
    // A wave higher than a seventh of its length spills its crest. The
    // modes are linear and knew no such bound: turned sixty-seven degrees
    // in a frame, the chemistry bench's flask laid its old level out as a
    // thirty-four millimetre wave and threw most of what it held over the
    // lip.
    //
    // Mutation: drop `_breakSteep` from `FreeSurface.step`.
    const r = 0.02;
    final body = LiquidBody(
      shape: _cylinder(r, 0.1),
      medium: FluidMedium.water,
      volume: math.pi * r * r * 0.05,
      modes: 4,
    )..place(_tilt(0.0), Vector3.zero());
    body.step(1 / 1000, gravity: Vector3(0, -9.81, 0));
    // Turned a radian in one step: the old level, laid out on the new
    // plane, is a wave far past anything that stands.
    body
      ..place(_tilt(1.0), Vector3.zero())
      ..step(1 / 1000, gravity: Vector3(0, -9.81, 0));
    final bound = body.surface.wavenumbers.fold(
      0.0,
      (double sum, double k) => sum + 2 * math.pi / (14 * k),
    );
    expect(body.surface.reach, lessThanOrEqualTo(bound * 1.0001));
    // And small waves are left alone: a knock of a tenth of a millimetre
    // rings as it always did.
    final calm = LiquidBody(
      shape: _cylinder(r, 0.1),
      medium: FluidMedium.water,
      volume: math.pi * r * r * 0.05,
      modes: 4,
    )..place(_tilt(0.0), Vector3.zero());
    calm.step(1 / 1000, gravity: Vector3(0, -9.81, 0));
    calm.surface.knock(Vector3(0.5 * r, calm.height, 0), 1e-4);
    final before = calm.surface.reach;
    calm.step(1e-9, gravity: Vector3(0, -9.81, 0));
    expect(calm.surface.reach, closeTo(before, before * 1e-3));
  });

  test('upright and overfull, it runs over the edge, out, not in', () {
    // Over every part of a level lip at once, the outward pull of each
    // stretch cancels the one across from it: the spill left from the middle
    // of the mouth with no speed at all, and fell back into the glass it came
    // from — round and round, every step. Overfilling the chemistry bench's
    // tube did that. It leaves over the stretch that passes most instead,
    // and outwards.
    //
    // Mutation: go back to the weighed mean in `_spill`.
    const r = 0.02;
    final body = LiquidBody(
      shape: _cylinder(r, 0.1),
      medium: FluidMedium.water,
      volume: math.pi * r * r * 0.1,
      modes: 4,
    );
    body.pour(math.pi * r * r * 0.005);
    Spill? first;
    for (var i = 0; i < 200 && first == null; i++) {
      body.place(_tilt(0.0), Vector3.zero());
      final spill = body.step(1 / 1000, gravity: Vector3(0, -9.81, 0));
      if (spill.flow > 0) first = spill;
    }
    expect(first, isNotNull, reason: 'an overfull glass spills');
    final out = Vector3(first!.point.x, 0.0, first.point.z);
    // At the lip, not the middle of the mouth.
    expect(out.length, closeTo(r, r * 0.05));
    // Moving outwards, away from the axis.
    expect(first.velocity.length, greaterThan(0.0));
    expect(first.velocity.dot(out.normalized()), greaterThan(0.0));
    // A sheet no wider than the mouth.
    expect(first.width, lessThanOrEqualTo(2 * r * 1.001));
  });

  test('what lands hard sets the surface moving, and dips it', () {
    // A drop landing at a metre a second strikes: an impulsive pressure,
    // whose potential sets every mode moving at k·tanh(kh) times its share.
    // The same drop laid down still only heaps. Mutation: drop the strike,
    // and a stream poured into a glass leaves its surface as flat as a lid.
    LiquidBody glass() => LiquidBody(
      shape: _cylinder(0.008, 0.09),
      medium: FluidMedium.water,
      volume: math.pi * 0.008 * 0.008 * 0.03,
      modes: 8,
    )..place(Matrix3.identity(), Vector3.zero());
    double ring(double speed) {
      final body = glass()..step(1 / 240, gravity: Vector3(0, -9.81, 0));
      for (var i = 0; i < 40; i++) {
        body
          ..receive(
            5e-9,
            Vector3(0.003, 0.03, 0),
            Vector3(0, -speed, 0),
            FluidMedium.water,
            const {},
          )
          ..place(Matrix3.identity(), Vector3.zero())
          ..step(1 / 240, gravity: Vector3(0, -9.81, 0));
      }
      return body.surface.reach;
    }

    final still = ring(0.0);
    final struck = ring(1.0);
    expect(struck, greaterThan(3.0 * still));
    // And under where it lands the surface is lower than elsewhere.
    final body = glass()..step(1 / 240, gravity: Vector3(0, -9.81, 0));
    for (var i = 0; i < 12; i++) {
      body
        ..receive(
          5e-9,
          Vector3(0.004, 0.03, 0),
          Vector3(0, -1.0, 0),
          FluidMedium.water,
          const {},
        )
        ..place(Matrix3.identity(), Vector3.zero())
        ..step(1 / 240, gravity: Vector3(0, -9.81, 0));
    }
    expect(
      body.surface.displacement(Vector3(0.004, body.height, 0)),
      lessThan(body.surface.displacement(Vector3(-0.004, body.height, 0))),
    );
  });
}
