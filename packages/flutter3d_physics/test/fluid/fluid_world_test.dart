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

  test(
    'a glass carried steadily keeps still, however unevenly it is drawn',
    () {
      // Frames of one, two and three fixed steps and the odd part of one, as
      // a browser draws them, with the glass moving at a steady 0.2 m/s.
      // Placed at each frame's own time it feels no acceleration and its
      // surface stays flat. Mutation: drop `time:` so each place is stamped
      // with the liquid's clock, and the frames that ran one step against
      // those that ran three read as a jolt, and the surface rocks by
      // five centimetres in a tube sixteen millimetres across.
      final world = FluidWorld(gravity: Vector3(0, -9.81, 0));
      final glass = LiquidBody(
        shape: _tube(0.008, 0.1),
        medium: FluidMedium.water,
        volume: math.pi * 0.008 * 0.008 * 0.05,
        modes: 4,
      );
      world.bodies.add(glass);
      const frames = [1.0, 3.0, 1.5, 2.0, 0.6, 3.2, 1.0, 2.4];
      var seconds = 0.0;
      var worst = 0.0;
      for (var i = 0; i < 400; i++) {
        final frame = frames[i % frames.length] / 240.0;
        seconds += frame;
        glass.place(
          Matrix3.identity(),
          Vector3(0.2 * seconds, 0, 0),
          time: world.time + frame,
        );
        world.advance(frame);
        worst = math.max(worst, glass.surface.reach);
      }
      expect(worst, lessThan(1e-5));
    },
  );

  test('a glass left alone sleeps, and anything done to it wakes it', () {
    // Asleep it costs nothing a step. Mutation: let a knock, a pour or a
    // move leave it asleep, and a tapped glass on the bench never rings.
    final glass = LiquidBody(
      shape: _tube(0.008, 0.1),
      medium: FluidMedium.water,
      volume: math.pi * 0.008 * 0.008 * 0.05,
      modes: 4,
    );
    final g = Vector3(0, -9.81, 0);
    void run(int steps, {Vector3? at}) {
      for (var i = 0; i < steps; i++) {
        glass
          ..place(Matrix3.identity(), at ?? Vector3.zero())
          ..step(1 / 240, gravity: g);
      }
    }

    run(10);
    // Knocked: it rings.
    glass.surface.knock(Vector3(0.004, glass.height, 0), 0.001);
    run(1);
    expect(glass.surface.reach, greaterThan(1e-5));
    // Left long enough, the rings die and it sleeps flat.
    run(240 * 20);
    expect(glass.surface.reach, 0.0);
    final volume = glass.volume;
    // Poured into: wakes, and the level rises.
    final height = glass.height;
    glass.pour(1e-7);
    run(1);
    expect(glass.height, greaterThan(height));
    expect(glass.volume, closeTo(volume + 1e-7, 1e-18));
    // Moved: it feels the jolt.
    run(240 * 20);
    run(3, at: Vector3(0.01, 0, 0));
    expect(glass.surface.reach, greaterThan(0.0));
  });
}
