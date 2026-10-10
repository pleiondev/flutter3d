import 'dart:math' as math;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

import 'support.dart';

void main() {
  test('a burning block is drawn alight, chars, and goes out wet', () {
    final world = NativeWorld();
    addTearDown(world.dispose);
    final device = softwareDevice();
    final block = world.addBody(
      position: Vector3(0.0, 0.05, 0.0),
      type: NativeBodyType.fixed,
      mass: 0.6,
    );
    world
      ..setShape(block, NativeShape.box(Vector3(0.05, 0.05, 0.05)))
      ..setMaterial(block, NativeMaterial.wood())
      ..setTemperature(block, 690.0);
    final look = MeshNode(
      DeviceMesh.upload(
        device,
        CuboidShape(size: Vector3(0.1, 0.1, 0.1)).build(),
      ),
      RenderMaterial(
        name: 'wood',
        baseColor: LinearColor.fromSrgb(0.42, 0.28, 0.16, 1.0),
      ),
    );
    final view = FireView(
      world: world,
      device: device,
      scene: Scene(),
      renderer: Renderer.create(device: device),
      detail: FireDetail.light,
    )..watch(block, look);
    for (var i = 0; i < 600; i++) {
      world.step(0.1);
      view.update(0.1);
    }
    expect(view.burning, 1);
    expect(view.watts, greaterThan(0.0));
    expect(view.tongues, greaterThan(0));
    expect(view.puffs, greaterThan(0));
    expect(view.firelight.single.intensity, greaterThan(0.0));
    // A minute in, alight all over, char covers it: it is black, and its
    // char glows.
    // Mutation: colour by the fuel gone in `_char` — a quarter gone is a
    // look a quarter of the way to black.
    expect(look.material.baseColor.toSrgb().r, closeTo(0.06, 1e-6));
    expect(look.material.emissive.r, greaterThan(0.0));
    world.addWater(block, 0.5);
    for (var i = 0; i < 100; i++) {
      world.step(0.1);
      view.update(0.1);
    }
    // Out: nothing more sent up, and what was sent has gone. The char
    // stays black, cooled by the water past giving any light the eye sees.
    expect(view.burning, 0);
    expect(view.firelight.every((l) => l.intensity == 0.0), isTrue);
    expect(view.tongues, 0);
    expect(look.material.baseColor.toSrgb().r, closeTo(0.06, 1e-6));
    expect(look.material.emissive.r, lessThan(1e-9));
  });

  test('smoke is as dark as its plume carries soot, thinning as it rises', () {
    // A 100 kW wood fire on a 0.5 m base: 0.015/15 g of soot a kJ, stopping
    // 8.7 m² a gram, across a plume 0.24(z − z₀) wide rising at McCaffrey's
    // 1.11·Q^(1/3)·z^(−1/3). Mutation: take the plume's radius for its
    // width in `_plumeDepth` — half as dark everywhere.
    const kw = 100.0, base = 0.5, z = 4.0;
    final origin = 0.083 * math.pow(kw, 0.4) - 1.02 * base;
    final b = 0.12 * (z - origin);
    final u = 1.11 * math.pow(kw, 1 / 3) * math.pow(z, -1 / 3);
    final soot = 0.015 / 15.0 * kw;
    expect(
      FireView.plumeDepth(kw, base, z),
      closeTo(2.0 * 8.7 * soot / (math.pi * b * u), 1e-9),
    );
    // A tyre's fire of the same heat makes 0.092 of what burns soot at
    // 32 MJ/kg: its plume is 2.9 times as dark as wood's. Mutation: the
    // depth drawn with wood's soot whatever the fire says.
    final rubber = NativeMaterial.rubber();
    expect(
      FireView.plumeDepth(
            kw,
            base,
            z,
            sootYield: rubber.sootYield / rubber.heatOfCombustion,
          ) /
          FireView.plumeDepth(kw, base, z),
      closeTo((0.092 / 32.0) / (0.015 / 15.0), 1e-3),
    );
    // Higher up, wider and slower, it thins as z^(−2/3) once z₀ is small
    // beside z. Mutation: the plume's speed taken as constant — it thins
    // as 1/z instead.
    final far = FireView.plumeDepth(kw, base, 40.0);
    final ratio = far / FireView.plumeDepth(kw, base, 20.0);
    expect(ratio, closeTo(math.pow(2.0, -2 / 3), 0.03));
  });
}
