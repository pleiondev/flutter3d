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
  });
}
