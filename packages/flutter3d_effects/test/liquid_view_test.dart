import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart'
    show NativeWorld;
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

import 'support.dart';

const int _floats = 16;

void main() {
  late NativeWorld world;
  setUp(() => world = NativeWorld());
  tearDown(() => world.dispose());

  test('a pond is drawn at its surface and a dry bank under its ground', () {
    // Eight cells a side, the left half a bank a metre up, the right half a
    // pond half a metre deep over ground at nought, a metre off the origin.
    final ground = <double>[
      for (var j = 0; j < 8; j++)
        for (var i = 0; i < 8; i++) i < 4 ? 1.0 : 0.0,
    ];
    final origin = Vector3(10.0, 1.0, 20.0);
    final water = world.createShallowLiquid(
      nx: 8,
      nz: 8,
      cell: 0.5,
      origin: origin,
      ground: ground,
    );
    world.fillShallowLiquid(water, x0: 12.0, z0: 0, x1: 99, z1: 99, level: 0.5);
    final view = LiquidView(
      world: world,
      liquid: water,
      ground: ground,
      device: softwareDevice(),
      scene: Scene(),
      look: Material(name: 'water'),
    )..update();
    final v = view.surfaceVertices;
    double at(int cell, int k) => v[cell * _floats + k];
    // Cell (6, 3): in the pond. Its surface over the origin, still, no
    // froth, and its depth for the material.
    const pond = 6 + 3 * 8;
    expect(at(pond, 0), closeTo(10.0 + 6.5 * 0.5, 1e-6));
    expect(at(pond, 1), closeTo(1.0 + 0.5, 1e-4));
    expect(at(pond, 6), closeTo(0.5, 1e-4));
    expect(at(pond, 12), closeTo(0.5, 1e-3));
    expect(at(pond, 13), closeTo(0.5, 1e-3));
    expect(at(pond, 14), 0.0);
    // Cell (1, 3): on the bank, dry: under the ground, not seen.
    const bank = 1 + 3 * 8;
    expect(at(bank, 1), lessThan(1.0 + 1.0));
    expect(at(bank, 6), 0.0);
    expect(
      () => LiquidView(
        world: world,
        liquid: water,
        ground: const <double>[0.0],
        device: softwareDevice(),
        scene: Scene(),
        look: Material(name: 'water'),
      ),
      throwsArgumentError,
    );
  });

  test('a waterfall is drawn as a sheet, its drops, its bubbles and froth', () {
    // A step two metres high with a pool under it, fed at the top.
    final ground = <double>[
      for (var j = 0; j < 4; j++)
        for (var i = 0; i < 24; i++) i < 8 ? 2.0 : 0.0,
    ];
    final water = world.createShallowLiquid(
      nx: 24,
      nz: 4,
      cell: 0.25,
      origin: Vector3.zero(),
      ground: ground,
    );
    world
      ..fillShallowLiquid(water, x0: 2.0, z0: -1, x1: 9, z1: 9, level: 0.5)
      ..setShallowSource(water, 0, x: 0.5, z: 0.5, radius: 0.3, rate: 0.05);
    final view = LiquidView(
      world: world,
      liquid: water,
      ground: ground,
      device: softwareDevice(),
      scene: Scene(),
      look: Material(name: 'water'),
    );
    var froth = 0.0;
    for (var i = 0; i < 300; i++) {
      world.step(1.0 / 60.0);
      view.update();
      for (var c = 0; c < water.cells; c++) {
        froth = froth > view.surfaceVertices[c * _floats + 14]
            ? froth
            : view.surfaceVertices[c * _floats + 14];
      }
    }
    expect(view.sprayInFlight, greaterThan(0));
    // Mutation: drop the sewing of rows in `_drawSheet` — no quads.
    expect(view.sheetQuads, greaterThan(0));
    expect(view.bubbleClouds, greaterThan(0));
    // Where the falls drive air in, the water is white.
    expect(froth, greaterThan(0.5));
  });
}
