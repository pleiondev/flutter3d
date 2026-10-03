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
  test('a single drop falls as the world falls', () {
    final fluid = ParticleFluid(medium: FluidMedium.water, spacing: 0.002);
    fluid.inject(fluid.particleVolume, Vector3(0, 1, 0), Vector3.zero());
    for (var i = 0; i < 500; i++) {
      fluid.step(1 / 1000, gravity: Vector3(0, -1.62, 0));
    }
    final y = fluid.positions.single.y;
    expect(1 - y, closeTo(0.5 * 1.62 * 0.25, 0.5 * 1.62 * 0.25 * 0.01));
  });

  test('a drop thrown along the bench stops where it lands', () {
    // Mutation: drop the no-slip at walls, and a drop that came down
    // moving five centimetres a second sideways is half a metre off after
    // ten seconds, sliding still.
    final fluid = ParticleFluid(medium: FluidMedium.water, spacing: 0.001);
    final bench = [PlaneObstacle(normal: Vector3(0, 1, 0), offset: 0)];
    fluid.inject(
      3 * fluid.particleVolume,
      Vector3(0, 0.01, 0),
      Vector3(0.05, 0, 0),
    );
    for (var i = 0; i < 2400; i++) {
      fluid.step(1 / 240, gravity: Vector3(0, -9.81, 0), obstacles: bench);
    }
    for (final p in fluid.positions) {
      // A fall of a centimetre takes 45 ms, and five centimetres a second
      // carries it two and a quarter millimetres in that.
      expect(p.x, lessThan(0.005));
      expect(p.y, lessThan(0.002));
    }
  });

  test('what is less than a particle waits in the bank, and is counted', () {
    final fluid = ParticleFluid(medium: FluidMedium.water, spacing: 0.002);
    fluid.inject(
      2.5 * fluid.particleVolume,
      Vector3.zero(),
      Vector3.zero(),
      asParticles: true,
    );
    expect(fluid.count, 2);
    expect(fluid.volume, closeTo(2.5 * fluid.particleVolume, 1e-18));
    fluid.inject(
      0.5 * fluid.particleVolume,
      Vector3.zero(),
      Vector3.zero(),
      asParticles: true,
    );
    expect(fluid.count, 3);
  });

  test('what is left in the bank is let go once no more comes', () {
    // Mutation: keep it banked, and a third of a particle stays counted
    // and nowhere, however long the world runs.
    // Particles on a pane of glass, which keeps them particles.
    final fluid = ParticleFluid(medium: FluidMedium.water, spacing: 0.002);
    final pane = [PlaneObstacle(normal: Vector3(0, 1, 0), offset: 0.098)];
    final at = Vector3(0, 0.1, 0);
    fluid
      ..inject(
        3.3 * fluid.particleVolume,
        at,
        Vector3.zero(),
        asParticles: true,
      )
      // The step it came in on, more may still come.
      ..step(1 / 240, gravity: Vector3(0, -9.81, 0), obstacles: pane);
    expect(fluid.count, 3);
    fluid.step(1 / 240, gravity: Vector3(0, -9.81, 0), obstacles: pane);
    expect(fluid.count, 4);
    expect(fluid.dropCount, 0);
    expect(fluid.volumes.last, closeTo(0.3 * fluid.particleVolume, 1e-18));
    expect(fluid.volume, closeTo(3.3 * fluid.particleVolume, 1e-18));
    // And off the pane, it falls and lands as what it is.
    final glass = LiquidBody(
      shape: RevolvedVessel([
        Vector2(0, 0),
        Vector2(0.02, 0),
        Vector2(0.02, 0.2),
      ]),
      medium: FluidMedium.water,
      volume: 1e-6,
      modes: 2,
    )..place(Matrix3.identity(), Vector3(0, -0.15, 0));
    for (var i = 0; i < 240; i++) {
      fluid.step(
        1 / 240,
        gravity: Vector3(0, -9.81, 0),
        obstacles: [InsideWalls(glass)],
        receivers: [glass],
      );
    }
    expect(fluid.count, 0);
    expect(glass.volume, closeTo(1e-6 + 3.3 * fluid.particleVolume, 1e-18));
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
