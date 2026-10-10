import 'dart:math' as math;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart'
    show
        NativeLiquidProperties,
        NativeWorld,
        nativeSprayFloats,
        nativeSpraySheet;
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
      look: RenderMaterial(name: 'water'),
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
    // Cell (3, 3): the bank's edge beside the pond, drawn level with the
    // pond, half a metre under its own ground, so that the water ends where
    // it meets the bank. Mutation: draw it at its ground — a wedge of
    // surface slanting up the bank.
    const shore = 3 + 3 * 8;
    expect(at(shore, 1), closeTo(1.0 + 0.5, 1e-4));
    expect(at(shore, 6), closeTo(0.5 - 1.0, 1e-4));
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
        look: RenderMaterial(name: 'water'),
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
      look: RenderMaterial(name: 'water'),
      mist: const MistSettings(share: 0.01),
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
    // It plunges whole into the pool: no strand of it frays. Mutation:
    // take no strand for plunging — its foot frays as if it parted.
    final sheet = view.sheetVertices;
    for (var q = 0; q < view.sheetQuads * 4; q++) {
      expect(sheet[q * _floats + 12], 0.0);
    }
    // It plunges whole, as the core says, so with nothing broken into
    // drops no mist goes up. Mutation: let the sheet's landing raise it.
    final spray = world.readSpray(capacity: 4000, of: water);
    var drops = 0;
    for (var o = 0; o < spray.length; o += nativeSprayFloats) {
      if (spray[o + 9] != nativeSpraySheet) drops++;
    }
    expect(drops, 0);
    expect((view.nodes[3] as InstancedMeshNode).count, 0);
    // The air it drives down is drawn as clouds that stay under the
    // surface: each seen sphere's top under the water drawn over it. Mutation:
    // spread every cloud over half a cell, however near the surface.
    final bubbles = view.nodes[4] as InstancedMeshNode;
    final b = bubbles.instanceData;
    for (var k = 0; k < bubbles.count; k++) {
      final o = k * InstancedMeshNode.floatsPerInstance;
      if (b[o + 16] == 0.0) continue;
      final i = (b[o + 3] / 0.25).floor(), j = (b[o + 11] / 0.25).floor();
      final top = view.surfaceVertices[(i + j * 24) * _floats + 1];
      expect(b[o + 7] + b[o], lessThanOrEqualTo(top + 1e-4));
    }
  });

  test('falling water raises as much mist as its speed says', () {
    // Three times DOE-HDBK-3010's spill correlation at the fall that lands
    // at 9.9 m/s is 3.2·10⁻⁴: what Sun and colleagues' nappe, plunging at
    // that speed, rained down clear of its pool (4·10⁻⁴, within a factor
    // of two or three). Mutations: the handbook's correlation without its
    // factor of three for water — 1.1·10⁻⁴; the fall's height taken as the
    // speed's, not its square's — nothing like either.
    expect(mistShare(9.9), closeTo(3.25e-4, 0.1e-4));
    // At 11.3 m/s, more than the 3·10⁻⁴ Liu and colleagues caught on one
    // plate below their jet; as the speed to the 3.3; never past 1.5 %.
    expect(mistShare(11.3), greaterThan(3e-4));
    expect(
      mistShare(20.0) / mistShare(10.0),
      closeTo(math.pow(2.0, 3.3), 0.01),
    );
    expect(mistShare(80.0), 0.015);
    // A share given stands, whatever the speed.
    expect(const MistSettings(share: 0.01).shareAt(30.0), 0.01);
    expect(const MistSettings().shareAt(9.9), mistShare(9.9));
  });

  test('drops stop as much light as their size says', () {
    // Two-millimetre rain: twice its cross-section, 3V / d, to a part in a
    // hundred. Mutation: ρ²/2 throughout — what holds only for the finest.
    expect(
      LiquidView.dropShadow(volume: 1e-6, diameter: 0.002),
      closeTo(3e-6 / 0.002, 3e-6 / 0.002 * 0.01),
    );
    // Drops of ten nanometres, far finer than light: next to nothing.
    // Mutation: two throughout — a cloud of them a white wall.
    expect(
      LiquidView.dropShadow(volume: 1e-6, diameter: 1e-8),
      lessThan(1e-3 * 3e-6 / 1e-8),
    );
    // A cloud of it spread normally σ either way is that over 2πσ² deep
    // through its middle.
    expect(LiquidView.cloudDepth(2.0 * 3.14159265, 1.0), closeTo(1.0, 1e-6));
  });

  test('a thin sheet frays where it parts, and falls on as its drops', () {
    // A shelf four metres over a pool, fed a trickle: the sheet off it is a
    // few millimetres thick and parts a few centimetres down.
    final ground = <double>[
      for (var j = 0; j < 4; j++)
        for (var i = 0; i < 24; i++) i < 6 ? 4.0 : 0.0,
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
      ..setShallowSource(water, 0, x: 0.3, z: 0.5, radius: 0.3, rate: 0.004);
    final view = LiquidView(
      world: world,
      liquid: water,
      ground: ground,
      device: softwareDevice(),
      scene: Scene(),
      look: RenderMaterial(name: 'water'),
    );
    for (var i = 0; i < 400; i++) {
      world.step(1.0 / 60.0);
      view.update(1.0 / 60.0);
    }
    // Each strand clear at its lip and frayed through at its foot, where it
    // is gone. Mutation: never fray it.
    final sheet = view.sheetVertices;
    var clear = 0, parted = 0;
    for (var q = 0; q < view.sheetQuads * 4; q++) {
      final red = sheet[q * _floats + 12], alpha = sheet[q * _floats + 15];
      if (red == 0.0) clear++;
      if (red == 1.0) {
        parted++;
        expect(alpha, 0.0);
      }
    }
    expect(clear, greaterThan(0));
    expect(parted, greaterThan(0));
    // Below, every piece of drops is drawn as a cloud as thick as its drops
    // make it, at least a cell across. Mutation: draw them at no depth.
    final spray = world.readSpray(capacity: 4000, of: water);
    var drops = 0;
    for (var o = 0; o < spray.length; o += nativeSprayFloats) {
      if (spray[o + 9] != nativeSpraySheet) drops++;
    }
    final clouds = view.nodes[2] as InstancedMeshNode;
    expect(drops, greaterThan(0));
    expect(clouds.count, drops);
    for (var k = 0; k < clouds.count; k++) {
      final o = k * InstancedMeshNode.floatsPerInstance;
      expect(clouds.instanceData[o + 16], greaterThan(0.0));
      expect(clouds.instanceData[o], greaterThanOrEqualTo(3.0 * 0.125));
    }
  });

  test('a falls is heard, and misted, by the gravity of its world', () {
    // The waterfall above: a step two metres high, fed at the top, a sheet
    // falling off its lip.
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
    for (var i = 0; i < 300; i++) {
      world.step(1.0 / 60.0);
    }
    // Wide enough that nothing is clamped: loudness is then the logarithm
    // of the power over eighteen decades, and a power g times another is
    // ln g / ln 10¹⁸ louder.
    const scale = HearingScale(quiet: 1e-9, loud: 1e9, reference: 1.0);
    final hearing = PhysicsHearing(
      world,
      fireScale: scale,
      fallScale: scale,
      splashScale: scale,
    )..listen(water);
    // The Earth's, to the bit: a new world's gravity, read through the core's
    // f32, is the 9.81 every number heard and drawn was made with before
    // they read it from the world.
    expect(world.gravityMagnitude, standardGravity);
    hearing.update(0.1);
    final earth = <int, double>{
      for (final fall in hearing.falls) fall.key: fall.loudness,
    };
    expect(earth, isNotEmpty);
    // The same water, the same drops in the air, on the Moon: each falls
    // gives up its weight times its speed, and its weight is the Moon's.
    // Mutation: hear the falls by 9.81 rather than the world's
    // `gravityMagnitude` in `_hearFalls` — fails because every fall is as
    // loud as it was on the Earth.
    world.gravity = Vector3(0.0, -1.62, 0.0);
    final moon = world.gravityMagnitude;
    expect(moon, closeTo(1.62, 1e-6));
    hearing.update(0.1);
    expect(hearing.falls, hasLength(earth.length));
    for (final fall in hearing.falls) {
      expect(
        fall.loudness - earth[fall.key]!,
        closeTo(math.log(moon / standardGravity) / math.log(1e18), 1e-9),
      );
    }
    // And mist: from the height a fall lands at 10 m/s from, v²/2g, six
    // times as high on the Moon, Ar = ρ²gH³/μ² goes as g⁻², the share as
    // g^−1.1. Mutation: keep `const g = 9.81` in `mistShare` — fails because
    // the Moon's share comes out the Earth's.
    expect(
      mistShare(10.0, g: moon) / mistShare(10.0),
      closeTo(math.pow(moon / standardGravity, -1.1), 1e-9),
    );
    // Honey's viscosity, from its preset: near ten thousand times water's
    // (the catalog's 10 Pa·s over 1.002 mPa·s), Ar goes as μ⁻², the share
    // as μ^−1.1 of water's.
    final thicker =
        NativeLiquidProperties.honey.viscosity /
        NativeLiquidProperties.water.viscosity;
    expect(thicker, closeTo(1e4, 100.0));
    expect(
      mistShare(10.0, viscosity: NativeLiquidProperties.honey.viscosity) /
          mistShare(10.0),
      closeTo(math.pow(thicker, -1.1), 1e-12),
    );
  });
}
