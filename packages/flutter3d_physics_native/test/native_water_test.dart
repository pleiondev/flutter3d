/// Water through the binding: the C tests hold the stream, the falls, the
/// waves and the floating against their physics; this holds the calls — a
/// pond made, fed, read and taken away, and a float held up in it.
library;

import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  late NativeWorld world;
  setUp(() => world = NativeWorld());
  tearDown(() => world.dispose());

  test('a pond fed by a spring holds what it was given', () {
    final pond = world.createWater(
      nx: 20,
      nz: 20,
      cell: 0.25,
      origin: Vector3(-2.5, 0.0, -2.5),
      ground: List<double>.filled(400, 0.0),
    );
    expect(pond.cells, 400);
    world
      ..fillWater(pond, x0: -9, z0: -9, x1: 9, z1: 9, level: 0.5)
      ..setWaterSource(pond, 0, x: 0.0, z: 0.0, radius: 0.3, rate: 0.01);
    final before = world.waterVolume(pond).held;
    expect(before, closeTo(0.5 * 25.0, 1e-3));
    for (var i = 0; i < 60; i++) {
      world.step(1.0 / 60.0);
    }
    // Mutation: the spring not passed to the core — nothing is added.
    expect(world.waterVolume(pond).held, closeTo(before + 0.01, 1e-4));
    final read = world.readWaterSurface(pond);
    expect(read.surface.length, 400);
    expect(read.depth[210], greaterThan(0.49));
    expect(world.readWaterFlow(pond).length, 800);
    final at = world.sampleWater(pond, 0.0, 0.0)!;
    expect(at.surface, closeTo(0.5, 0.01));
    expect(world.sampleWater(pond, 9.0, 9.0), isNull);
    expect(world.readSpray(), isEmpty);
    // No falls, so nothing drags air down.
    expect(world.readBubbles(), isEmpty);
    expect(
      () => world.setWaterSource(pond, 16, x: 0, z: 0, rate: 1),
      throwsArgumentError,
    );
    expect(
      () => world.createWater(
        nx: 2,
        nz: 2,
        cell: 1,
        origin: Vector3.zero(),
        ground: <double>[0, 0, 0],
      ),
      throwsArgumentError,
    );
    expect(world.removeWater(pond), isTrue);
    expect(world.containsWater(pond), isFalse);
  });

  test('water poured on a slope runs off an open edge', () {
    // A channel sloping down x, its end open: what is poured at the top
    // runs off the far end, and what is held and what ran off is what was
    // poured. Raising the ground under still water raises its surface.
    final channel = world.createWater(
      nx: 32,
      nz: 4,
      cell: 0.25,
      origin: Vector3.zero(),
      ground: <double>[
        for (var j = 0; j < 4; j++)
          for (var i = 0; i < 32; i++) 1.0 - 0.03 * i,
      ],
    );
    world
      ..setWaterBed(channel, roughness: 0.03, openEdges: true)
      ..pourWater(channel, 1.0, 0.5, radius: 0.5, volume: 0.5);
    for (var i = 0; i < 600; i++) {
      world.step(1.0 / 60.0);
    }
    final v = world.waterVolume(channel);
    expect(v.lost, greaterThan(0.1));
    expect(v.held + v.lost, closeTo(0.5, 1e-4));
    expect(
      () => world.setWaterBed(channel, roughness: -1),
      throwsArgumentError,
    );

    final basin = world.createWater(
      nx: 4,
      nz: 4,
      cell: 1.0,
      origin: Vector3.zero(),
      ground: List<double>.filled(16, 0.0),
    );
    world
      ..fillWater(basin, x0: 0, z0: 0, x1: 4, z1: 4, level: 0.5)
      ..setWaterGround(basin, List<double>.filled(16, 0.2));
    expect(world.sampleWater(basin, 2.0, 2.0)!.surface, closeTo(0.7, 1e-6));
  });

  test('spray and bubbles are read for one water of several', () {
    // A step two metres high with a pool under it, fed at the top: its
    // sheet falls and drags air into the pool. A still pond beside it
    // throws nothing.
    final falls = world.createWater(
      nx: 24,
      nz: 4,
      cell: 0.25,
      origin: Vector3.zero(),
      ground: <double>[
        for (var j = 0; j < 4; j++)
          for (var i = 0; i < 24; i++) i < 8 ? 2.0 : 0.0,
      ],
    );
    final pond = world.createWater(
      nx: 8,
      nz: 8,
      cell: 0.25,
      origin: Vector3(20.0, 0.0, 0.0),
      ground: List<double>.filled(64, 0.0),
    );
    world
      ..fillWater(falls, x0: 2.0, z0: -1, x1: 9, z1: 9, level: 0.5)
      ..fillWater(pond, x0: 0, z0: 0, x1: 99, z1: 99, level: 0.3)
      ..setWaterSource(falls, 0, x: 0.5, z: 0.5, radius: 0.3, rate: 0.05);
    // Five seconds: the stream reaches the lip in two, its sheet lands and
    // drags air in by four.
    for (var i = 0; i < 300; i++) {
      world.step(1.0 / 60.0);
    }
    // Mutation: drop the filter in `_readOfWater` — the pond reads the
    // falls' spray as its own.
    expect(world.readSpray(of: falls), isNotEmpty);
    expect(world.readSpray(of: falls), world.readSpray());
    expect(world.readSpray(of: pond), isEmpty);
    expect(world.readBubbles(of: falls), isNotEmpty);
    expect(world.readBubbles(of: pond), isEmpty);
  });

  test('a ball lighter than water floats in it', () {
    final pond = world.createWater(
      nx: 32,
      nz: 32,
      cell: 0.1,
      origin: Vector3(-1.6, 0.0, -1.6),
      ground: List<double>.filled(32 * 32, 0.0),
    );
    world.fillWater(pond, x0: -9, z0: -9, x1: 9, z1: 9, level: 1.0);
    final ball = world.addBody(position: Vector3(0.0, 1.2, 0.0), mass: 10.0);
    world.setShape(ball, const NativeShape.sphere(0.2));
    for (var i = 0; i < 300; i++) {
      world.step(1.0 / 60.0);
    }
    // Ten kilograms in a ball of 33 litres: under three tenths of it is
    // under water, so it rides with its centre above the surface.
    expect(world.positionOf(ball).y, inInclusiveRange(1.0, 1.2));
  });
}
