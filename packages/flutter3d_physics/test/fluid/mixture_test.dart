import 'dart:math' as math;

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

LiquidBody _tube(
  FluidMedium m,
  double volume, {
  Map<String, double> c = const {},
}) => LiquidBody(
  shape: RevolvedVessel([Vector2(0, 0), Vector2(0.01, 0), Vector2(0.01, 0.2)]),
  medium: m,
  volume: volume,
  concentrations: c,
  modes: 2,
);

void main() {
  test('two solutions poured together keep every solute', () {
    final a = _tube(FluidMedium.water, 2e-6, c: {'dye': 3.0});
    a.pour(1e-6, concentrations: {'dye': 0.0, 'salt': 6.0});
    final layer = a.layers.single;
    // 2·3 + 1·0 of dye and 1·6 of salt, over 3.
    expect(layer.concentration('dye'), closeTo(2.0, 1e-9));
    expect(layer.concentration('salt'), closeTo(2.0, 1e-9));
    expect(a.volume, closeTo(3e-6, 1e-18));
  });

  test('oil floats on water, each its own layer, densest at the bottom', () {
    final body = _tube(FluidMedium.oil, 1e-6);
    body.pour(2e-6, medium: FluidMedium.water);
    expect(body.layers.map((l) => l.medium.name), ['water', 'oil']);
    expect(body.medium.name, 'oil');
    final tops = body.layerTops();
    final area = math.pi * 0.01 * 0.01;
    expect(tops[0], closeTo(2e-6 / area, 1e-6));
    expect(tops[1], closeTo(3e-6 / area, 1e-6));
    // The pressure at the floor is each layer's weight: ρ g h, added.
    body
      ..place(Matrix3.identity(), Vector3.zero())
      ..step(1e-3, gravity: Vector3(0, -9.81, 0));
    final expected = 9.81 * (998.2 * 2e-6 / area + 911 * 1e-6 / area);
    expect(body.pressureAt(Vector3.zero()), closeTo(expected, expected * 1e-3));
  });

  test('a tipped glass pours its top layer first', () {
    final body = _tube(FluidMedium.water, 5e-5);
    body.pour(2e-6, medium: FluidMedium.oil);
    var oil = 0.0, water = 0.0;
    for (var i = 0; i < 3000; i++) {
      body.place(Matrix3.rotationX(1.2), Vector3.zero());
      final spill = body.step(1e-3, gravity: Vector3(0, -9.81, 0));
      if (spill.medium.name == 'oil') oil += spill.flow * 1e-3;
      if (spill.medium.name == 'water') water += spill.flow * 1e-3;
      // Mutation: spill from the bottom, and water leaves while oil is left.
      if (water > 0) {
        expect(body.layers.any((l) => l.medium.name == 'oil'), isFalse);
      }
    }
    expect(oil, closeTo(2e-6, 2e-6 * 1e-6));
    expect(water, greaterThan(0));
  });

  test('a pipe at the floor draws the bottom layer', () {
    final a = _tube(FluidMedium.water, 1e-5);
    a.pour(5e-6, medium: FluidMedium.oil);
    final b = _tube(FluidMedium.water, 1e-6);
    final pipe = Pipe(
      from: a,
      at: Vector3(0, 0.0005, 0),
      to: b,
      toAt: Vector3(0, 0.0005, 0),
      radius: 0.002,
      length: 0.05,
    );
    for (var i = 0; i < 2000; i++) {
      for (final v in [a, b]) {
        v.place(Matrix3.identity(), Vector3.zero());
      }
      pipe.step(1e-3, gravity: Vector3(0, -9.81, 0));
      a.step(1e-3, gravity: Vector3(0, -9.81, 0));
      b.step(1e-3, gravity: Vector3(0, -9.81, 0));
    }
    // Water went through; the oil stayed on top of the first glass.
    expect(b.layers.map((l) => l.medium.name), ['water']);
    expect(a.layers.last.medium.name, 'oil');
    expect(a.layers.last.volume, closeTo(5e-6, 1e-12));
  });

  test('the meniscus is the top liquid\'s', () {
    // Mutation: keep the water's meniscus once oil is poured over it, and
    // the wall rise stays water's, a third higher.
    final body = _tube(FluidMedium.water, 8e-6);
    body
      ..place(Matrix3.identity(), Vector3.zero())
      ..step(1e-4, gravity: Vector3(0, -9.81, 0));
    final water = body.meniscusAt(Vector3(0.01, 0, 0));
    body
      ..pour(4e-6, medium: FluidMedium.oil)
      ..place(Matrix3.identity(), Vector3.zero())
      ..step(1e-4, gravity: Vector3(0, -9.81, 0));
    final oil = body.meniscusAt(Vector3(0.01, 0, 0));
    final expected = TubeMeniscus(
      medium: FluidMedium.oil,
      radius: 0.01,
      g: 9.81,
    );
    // Within a percent: menisci are kept by the radius in steps of a
    // hundredth of it, so this one was solved a hair off a centimetre.
    final rise = expected.wallRise - expected.meanHeight;
    expect(oil, closeTo(rise, 0.01 * rise));
    expect(oil, lessThan(water));
  });
}
