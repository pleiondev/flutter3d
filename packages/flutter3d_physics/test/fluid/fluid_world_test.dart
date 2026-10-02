import 'dart:math' as math;

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

RevolvedVessel _tube(double r, double h) =>
    RevolvedVessel([Vector2(0, 0), Vector2(r, 0), Vector2(r, h)]);

void main() {
  test('a world runs whole steps and carries the rest over', () {
    final world = FluidWorld(gravity: Vector3(0, -9.81, 0), step: 0.01);
    expect(world.advance(0.025), 2);
    expect(world.advance(0.006), 1);
    expect(world.advance(0.003), 0);
  });

  test('poured from one glass into another, no liquid is lost or made', () {
    final gravity = Vector3(0, -9.81, 0);
    final world = FluidWorld(gravity: gravity);
    final source = LiquidBody(
      shape: _tube(0.008, 0.1),
      medium: FluidMedium.water,
      volume: math.pi * 0.008 * 0.008 * 0.07,
      modes: 4,
    );
    final target = LiquidBody(
      shape: _tube(0.012, 0.1),
      medium: FluidMedium.water,
      volume: 0.0,
      modes: 4,
    );
    world.bodies.addAll([source, target]);
    final total = source.volume;
    // The source tipped over the target's mouth, its lip over the back of
    // it: what spills is thrown forward, across the mouth.
    final turn = Matrix3.rotationX(1.3);
    for (var i = 0; i < 480; i++) {
      source.place(turn, Vector3(0, 0.1, -0.1045));
      target.place(Matrix3.identity(), Vector3.zero());
      world.advance(world.step);
    }

    // Mutation: let the source's own inside catch its spill back, and
    // nothing ever leaves it.
    expect(target.volume, greaterThan(0));
    expect(world.volume, closeTo(total, total * 1e-9));
  });
}
