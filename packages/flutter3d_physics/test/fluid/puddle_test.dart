import 'dart:math' as math;

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

PuddleSurface _bench() =>
    PuddleSurface(PlaneObstacle(normal: Vector3(0, 1, 0), offset: 0));

void main() {
  const g = 9.81;
  const water = FluidMedium.water;

  test('a spread puddle is as deep as the capillary length and θ make it', () {
    // 2ℓc·sin(θ/2): a little under a millimetre for water on glass at 20°.
    // Mutation: leave out the sine, and ten millilitres lie as a disc
    // five centimetres across, five millimetres deep.
    final bench = _bench()
      ..receive(1e-5, Vector3(0, 0.001, 0), Vector3.zero(), water, const {});
    final puddle = bench.puddles.single;
    final r = puddle.restRadius(g);
    final deep = puddle.volume / (math.pi * r * r);
    final capillary = math.sqrt(water.surfaceTension / (water.density * g));
    expect(
      deep,
      closeTo(2 * capillary * math.sin(water.contactAngle / 2), 1e-9),
    );
  });

  test('a small drop is a cap meeting the bench at its contact angle', () {
    final bench = _bench()
      ..receive(1e-9, Vector3(0, 0.0005, 0), Vector3.zero(), water, const {});
    final drop = bench.puddles.single;
    final r = drop.restRadius(g);
    final h = drop.capHeight(r);
    // The cap's angle at its edge, from its base and height.
    expect(2 * math.atan(h / r), closeTo(water.contactAngle, 1e-6));
    expect(math.pi * h * (3 * r * r + h * h) / 6, closeTo(drop.volume, 1e-18));
  });

  test('drops landing apart stay apart, and run together when they meet', () {
    final bench = _bench()
      ..receive(1e-8, Vector3(0, 0, 0), Vector3.zero(), water, const {'a': 1})
      ..receive(1e-8, Vector3(0.1, 0, 0), Vector3.zero(), water, const {});
    expect(bench.puddles, hasLength(2));
    // Poured between them until they reach each other.
    for (var i = 0; i < 40; i++) {
      bench.receive(5e-7, Vector3(0.05, 0, 0), Vector3.zero(), water, const {});
    }
    expect(bench.puddles, hasLength(1));
    expect(bench.volume, closeTo(2e-8 + 40 * 5e-7, 1e-15));
    // What was dissolved in one is in the whole, by its share.
    expect(
      bench.puddles.single.concentrations['a'],
      closeTo(1e-8 / bench.volume, 1e-12),
    );
  });

  test('a glass emptied on the bench lies there, every drop of it', () {
    // Mutation: leave the bench out of the receivers, and what ran out is
    // thousands of particles, which took a quarter of an hour to step.
    final world = FluidWorld(
      gravity: Vector3(0, -g, 0),
      floor: [PlaneObstacle(normal: Vector3(0, 1, 0), offset: 0)],
    );
    final glass = LiquidBody(
      shape: RevolvedVessel([
        Vector2(0, 0.0005),
        Vector2(0.008, 0.0005),
        Vector2(0.008, 0.1),
      ]),
      medium: water,
      volume: math.pi * 0.008 * 0.008 * 0.05,
      modes: 4,
    );
    world.bodies.add(glass);
    final total = world.volume;
    final turn = Matrix3.rotationZ(2.5);
    for (var i = 0; i < 240 * 4; i++) {
      glass.place(turn, Vector3(0, 0.12, 0));
      world.advance(world.step);
    }
    expect(glass.volume, lessThan(total * 0.02));
    expect(world.volume, closeTo(total, total * 1e-9));
    final lying = world.spills.single.volume;
    expect(lying, greaterThan(total * 0.9));
    expect(world.particles.values.fold(0, (s, p) => s + p.count), lessThan(50));
  });
}
