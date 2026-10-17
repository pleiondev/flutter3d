import 'dart:math' as math;

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('a pipe rubs as Poiseuille laminar and as Blasius turbulent', () {
    // Laminar, exactly 64/Re.
    expect(Pipe.frictionFactor(1000.0), closeTo(0.064, 1e-12));
    // Smooth and turbulent, Blasius's 0.316·Re^−¼ to a few percent at a
    // hundred thousand, where it holds.
    final blasius = 0.316 * math.pow(1e5, -0.25);
    expect(Pipe.frictionFactor(1e5), closeTo(blasius, blasius * 0.03));
    // A rough bore rubs harder, once the flow is turbulent; laminar, it
    // does not care.
    expect(
      Pipe.frictionFactor(1e5, relativeRoughness: 0.01),
      greaterThan(1.5 * Pipe.frictionFactor(1e5)),
    );
    expect(
      Pipe.frictionFactor(1000.0, relativeRoughness: 0.01),
      Pipe.frictionFactor(1000.0),
    );
    // Through the transition it climbs from one to the other, without a
    // jump at either end.
    expect(Pipe.frictionFactor(2300.0), closeTo(64.0 / 2300.0, 1e-12));
    expect(Pipe.frictionFactor(2300.0 + 1e-6), closeTo(64.0 / 2300.0, 1e-6));
  });

  test('a wide pipe between two vessels runs turbulent and slower than '
      'Poiseuille would let it', () {
    // Two tanks a metre across, one a metre fuller, joined by a pipe two
    // centimetres across: the flow is at a Reynolds number in the tens of
    // thousands, where Darcy's friction is far above Poiseuille's.
    // Mutation: hand the column the bare viscosity, and it runs faster.
    LiquidBody tank(double level) => LiquidBody(
      shape: RevolvedVessel([
        Vector2(0, 0),
        Vector2(0.5, 0),
        Vector2(0.5, 3.0),
      ]),
      medium: FluidMedium.water,
      volume: math.pi * 0.25 * level,
      modes: 2,
    )..place(Matrix3.identity(), Vector3.zero());
    final a = tank(2.0);
    final b = tank(1.0);
    final pipe = Pipe(
      from: a,
      at: Vector3(0.5, 0.05, 0),
      to: b,
      toAt: Vector3(0.5, 0.05, 0),
      radius: 0.01,
      length: 1.0,
    );
    for (var i = 0; i < 2000; i++) {
      pipe.step(1 / 1000, gravity: Vector3(0, -9.81, 0));
    }
    expect(pipe.reynolds, greaterThan(4000.0));
    // A metre of head spent on the end losses (K = 1.5) and the pipe's
    // friction f·L/D: v = √(2gH / (K + f·L/D)), about 2.8 m/s, where the
    // ends alone would let it run at 3.6.
    final speed = pipe.flow / (math.pi * 0.01 * 0.01);
    final f = Pipe.frictionFactor(
      pipe.reynolds,
      relativeRoughness: pipe.roughness / 0.02,
    );
    final head = a.height - b.height;
    final steady = math.sqrt(2 * 9.81 * head / (1.5 + f * 1.0 / 0.02));
    expect(speed, closeTo(steady, steady * 0.03));
  });

  test('a turbulent stream parts at L/D = 8.51·We^0.32', () {
    // Five millimetres at two metres a second: Re 10 000, We 275. Laminar
    // it would hold for a metre; turbulent, for a quarter of one (Grant
    // and Middleman). Mutation: let it part only by its ripples, and it
    // flies a metre whole.
    const d = 0.005;
    const v = 2.0;
    final q = v * math.pi * d * d / 4.0;
    final jet = Jet(medium: FluidMedium.water);
    final water = FluidMedium.water;
    final we = water.density * v * v * d / water.surfaceTension;
    final expected = 8.51 * d * math.pow(we, 0.32);
    expect(Jet.intactLength(water, q, v), closeTo(expected, 1e-9));
    double? first;
    for (var k = 0; k < 400 && first == null; k++) {
      jet.emit(
        flow: q,
        dt: 1 / 1000,
        point: Vector3.zero(),
        velocity: Vector3(v, 0, 0),
        width: d,
        across: Vector3(0, 0, 1),
      );
      final drops = jet.step(1 / 1000, gravity: Vector3.zero());
      if (drops.isNotEmpty) first = drops.first.position.x;
    }
    expect(first, isNotNull);
    expect(first, closeTo(expected, expected * 0.05));
    // A slow, laminar one parts by its ripples alone.
    expect(Jet.intactLength(water, 1e-7, 0.1), double.infinity);
  });
}
