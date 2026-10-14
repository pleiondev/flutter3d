import 'dart:math' as math;

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A closed box of planes from (0, 0, 0) to [size].
List<JetObstacle> _box(double size) => [
  PlaneObstacle(normal: Vector3(0, 1, 0), offset: 0),
  PlaneObstacle(normal: Vector3(1, 0, 0), offset: 0),
  PlaneObstacle(normal: Vector3(-1, 0, 0), offset: -size),
  PlaneObstacle(normal: Vector3(0, 0, 1), offset: 0),
  PlaneObstacle(normal: Vector3(0, 0, -1), offset: -size),
];

void main() {
  test('lumps let go on top of each other spread rather than fly apart', () {
    // A stream breaking up lets go of its drops at nearly the same point
    // step after step, so each lump is laid out exactly on the last: the
    // chemistry bench's overflowing flask threw thirty thousand particles
    // eleven metres up.
    //
    // Mutations: in `_between`, return pᵢ − pⱼ even where it is nought —
    // coincident pairs read compressed with no gradient, and the drops fly
    // kilometres; or drop the pre-stabilising `_holdDensity` in `_substep`
    // — the overlap is taken out by the solve, becomes velocity, and they
    // leap a metre.
    final fluid = ParticleFluid(medium: FluidMedium.water, spacing: 0.002);
    for (var i = 0; i < 8; i++) {
      fluid.inject(
        64 * fluid.particleVolume,
        Vector3(0.01, 0.02, 0.01),
        Vector3.zero(),
      );
    }
    final box = _box(0.02);
    var highest = 0.0;
    var fastest = 0.0;
    for (var i = 0; i < 120; i++) {
      fluid.step(1 / 240, gravity: Vector3(0, -9.81, 0), obstacles: box);
      for (final p in fluid.positions) {
        highest = math.max(highest, p.y);
      }
    }
    fastest = fluid.velocities.fold(
      0.0,
      (double m, Vector3 v) => math.max(m, v.length),
    );
    // Let go from rest two centimetres up, eight lumps deep in a box two
    // centimetres across: the crowd has to make room for itself, and rises
    // a few centimetres doing it — not metres, which is what it did.
    expect(highest, lessThan(0.02 + 0.05));
    expect(fastest, lessThan(math.sqrt(2 * 9.81 * 0.05)));
  });

  test('a single drop falls as the world falls', () {
    final fluid = ParticleFluid(medium: FluidMedium.water, spacing: 0.002);
    fluid.inject(fluid.particleVolume, Vector3(0, 1, 0), Vector3.zero());
    for (var i = 0; i < 500; i++) {
      fluid.step(1 / 1000, gravity: Vector3(0, -1.62, 0));
    }
    final y = fluid.positions.single.y;
    expect(1 - y, closeTo(0.5 * 1.62 * 0.25, 0.5 * 1.62 * 0.25 * 0.01));
  });

  test('what is less than a particle waits in the bank, and is counted', () {
    final fluid = ParticleFluid(medium: FluidMedium.water, spacing: 0.002);
    fluid.inject(2.5 * fluid.particleVolume, Vector3.zero(), Vector3.zero());
    expect(fluid.count, 2);
    expect(fluid.volume, closeTo(2.5 * fluid.particleVolume, 1e-18));
    fluid.inject(0.5 * fluid.particleVolume, Vector3.zero(), Vector3.zero());
    expect(fluid.count, 3);
  });

  test(
    'a block of liquid settles at its rest density and stays in its box',
    () {
      const s = 0.005;
      final fluid = ParticleFluid(medium: FluidMedium.water, spacing: s);
      for (var i = 0; i < 6; i++) {
        for (var j = 0; j < 6; j++) {
          for (var k = 0; k < 6; k++) {
            fluid.inject(
              fluid.particleVolume,
              Vector3((i + 0.5) * s, (j + 0.5) * s, (k + 0.5) * s),
              Vector3.zero(),
            );
          }
        }
      }
      final start = fluid.volume;
      final walls = _box(6 * s);
      for (var t = 0; t < 600; t++) {
        fluid.step(1 / 600, gravity: Vector3(0, -9.81, 0), obstacles: walls);
      }
      expect(fluid.volume, start);
      // Nothing through the walls, and the bulk of it about as tall as it
      // was: it neither blew apart nor squashed. A surface particle or two
      // may ride a little higher.
      final heights = <double>[];
      for (final p in fluid.positions) {
        expect(p.x, inInclusiveRange(-1e-6, 6 * s + 1e-6));
        expect(p.z, inInclusiveRange(-1e-6, 6 * s + 1e-6));
        expect(p.y, greaterThanOrEqualTo(-1e-6));
        heights.add(p.y);
      }
      // Its mean height is three spacings — the block's — to five per cent:
      // at its rest density, neither squeezed by its weight nor spread out.
      // Mutation: Macklin's artificial pressure at his tenth rather than a
      // fiftieth, and it settles at 3.6, a sixth too thin.
      final mean = heights.reduce((a, b) => a + b) / heights.length;
      expect(mean, closeTo(3.0 * s, 0.15 * s));
      heights.sort();
      expect(heights[(heights.length * 0.95).floor()], lessThan(6.2 * s));
    },
  );

  test('drops that fall into a vessel are its liquid', () {
    final body = LiquidBody(
      shape: RevolvedVessel([
        Vector2(0, 0),
        Vector2(0.02, 0),
        Vector2(0.02, 0.1),
      ]),
      medium: FluidMedium.water,
      volume: 1e-5,
      modes: 2,
    );
    final fluid = ParticleFluid(medium: FluidMedium.water, spacing: 0.002);
    fluid.inject(
      20 * fluid.particleVolume,
      Vector3(0, 0.05, 0),
      Vector3.zero(),
    );
    final total = body.volume + fluid.volume;
    for (var i = 0; i < 400; i++) {
      body.place(Matrix3.identity(), Vector3.zero());
      body.step(1 / 1000, gravity: Vector3(0, -9.81, 0));
      fluid.step(1 / 1000, gravity: Vector3(0, -9.81, 0), receivers: [body]);
    }
    expect(fluid.count, 0);
    expect(body.volume + fluid.volume, closeTo(total, total * 1e-12));
  });

  test('liquid down on the floor is retired, and still counted', () {
    // Spilt liquid lying on the floor is taken out of the solve. Its
    // volume and what was dissolved in it go with it, and the world still
    // counts it. Mutations: leave the retired out of `FluidWorld.volume`
    // and a spill loses liquid; drop the amounts and a puddle has no
    // colour.
    final world = FluidWorld(
      gravity: Vector3(0, -9.81, 0),
      particleSpacing: 0.002,
      floor: [PlaneObstacle(normal: Vector3(0, 1, 0), offset: 0)],
    );
    final fluid = world.particles['water'] = ParticleFluid(
      medium: FluidMedium.water,
      spacing: 0.002,
    );
    fluid.inject(
      27 * fluid.particleVolume,
      Vector3(0, 0.05, 0),
      Vector3.zero(),
      concentrations: {'dye': 3.0},
    );
    final total = world.volume;
    // Down on the floor: on a floor with no friction a lone particle
    // slides on for ever, so lying low, not lying still, is the test.
    bool lying(Vector3 p, Vector3 v) => p.y < 0.006;
    final retired = <RetiredParticles>[];
    var first = double.infinity;
    for (var frame = 0; frame < 120 && fluid.count > 0; frame++) {
      world.advance(1 / 60);
      final gone = fluid.retire(elapsed: 1 / 60, after: 0.25, settled: lying);
      if (!gone.isEmpty) {
        retired.add(gone);
        first = math.min(first, frame / 60);
      }
    }
    expect(fluid.count, 0, reason: 'all of it came down');
    // Five centimetres is a tenth of a second's fall, and a quarter more
    // lying low: nothing goes sooner.
    expect(first, greaterThan(0.3));
    for (final gone in retired) {
      for (final p in gone.positions) {
        expect(p.y, lessThan(0.006));
      }
    }
    final volume = retired.fold(0.0, (s, r) => s + r.volume);
    expect(volume, closeTo(27 * fluid.particleVolume, 1e-18));
    expect(fluid.retired, closeTo(volume, 1e-18));
    expect(world.volume, closeTo(total, total * 1e-12));
    final dye = retired.fold(0.0, (s, r) => s + (r.amounts['dye'] ?? 0.0));
    expect(dye, closeTo(3.0 * volume, 1e-15));
  });

  test('a particle the test lets go of starts its time again', () {
    // Mutation: keep its time when the test fails, and a drop bouncing
    // off the floor is retired in the air.
    final fluid = ParticleFluid(medium: FluidMedium.water, spacing: 0.002)
      ..inject(0.008e-6, Vector3.zero(), Vector3.zero());
    var yes = false;
    for (var i = 0; i < 100; i++) {
      yes = !yes;
      final gone = fluid.retire(
        elapsed: 0.1,
        after: 0.15,
        settled: (_, _) => yes,
      );
      expect(gone.isEmpty, isTrue);
    }
    expect(
      fluid.retire(elapsed: 0.1, after: 0.15, settled: (_, _) => true).isEmpty,
      isTrue,
    );
    expect(
      fluid.retire(elapsed: 0.1, after: 0.15, settled: (_, _) => true).volume,
      closeTo(fluid.particleVolume, 1e-18),
    );
    expect(fluid.count, 0);
  });

  group('a test tube, a millimetre a particle', () {
    // Sixteen millimetres across, half a millimetre of glass, a round
    // bottom: a lathe profile from the middle of the floor up the side.
    List<Vector2> inside() => [
      Vector2(0, 0.0005),
      for (var i = 1; i <= 8; i++)
        Vector2(
          0.0075 * math.sin(i / 8 * math.pi / 2),
          0.0005 + 0.0075 * (1 - math.cos(i / 8 * math.pi / 2)),
        ),
      Vector2(0.0075, 0.09),
    ];

    LiquidBody tube({double volume = 0.0}) => LiquidBody(
      shape: RevolvedVessel(inside()),
      medium: FluidMedium.water,
      volume: volume,
      modes: 2,
      wallThickness: 0.0005,
    )..place(Matrix3.identity(), Vector3.zero());

    test('drops this small keep together', () {
      // Surface tension moves a millimetre particle its own size in a third
      // of a millisecond. Mutation: step it twice a 240th of a second, as
      // a two-millimetre one, and four particles fly metres apart.
      final fluid = ParticleFluid(medium: FluidMedium.water, spacing: 0.001)
        ..inject(4e-9, Vector3(0, 1, 0), Vector3.zero());
      for (var i = 0; i < 12; i++) {
        fluid.step(1 / 240, gravity: Vector3.zero());
      }
      for (final p in fluid.positions) {
        expect((p - Vector3(0, 1, 0)).length, lessThan(0.003));
      }
    });

    test('drops falling in land in it, round bottom and all', () {
      // Mutation: hold particles by the radius at their height, which is
      // nearly nought round the bottom, and they fall through the glass.
      final body = tube();
      final fluid = ParticleFluid(medium: FluidMedium.water, spacing: 0.001);
      final walls = <JetObstacle>[
        InsideWalls(body),
        OutsideWalls(body, thickness: 0.0005),
      ];
      for (var s = 0; s < 240; s++) {
        if (s < 60 && s % 3 == 0) {
          fluid.inject(
            4e-9,
            Vector3(0.002, 0.04, 0.001),
            Vector3(0, -1, 0),
            concentrations: {'dye': 2.0},
          );
        }
        fluid.step(
          1 / 240,
          gravity: Vector3(0, -9.81, 0),
          obstacles: walls,
          receivers: [body],
        );
      }
      expect(fluid.count, 0);
      expect(body.volume, closeTo(80e-9, 1e-15));
      // What was dissolved in the drops came with them. Mutation: hand
      // them over with nothing in them, and a poured dye loses its colour.
      expect(body.layers.single.concentration('dye'), closeTo(2.0, 1e-9));
    });
  });
}
