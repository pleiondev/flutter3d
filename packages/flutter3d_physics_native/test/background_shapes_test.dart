// A liquid's shapes worked out on another isolate: the same numbers as the
// frame's own solve, only later.
@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show SimulationProfile;
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A round cut of a tube on a grid of [cells] cells across.
SurfaceModesRequest _roundCut(int cells) {
  final index = Int32List(cells * cells)..fillRange(0, cells * cells, -1);
  var inside = 0;
  for (var r = 0; r < cells; r++) {
    for (var c = 0; c < cells; c++) {
      final u = (c + 0.5) / cells - 0.5;
      final v = (r + 0.5) / cells - 0.5;
      if (u * u + v * v < 0.25) index[r * cells + c] = inside++;
    }
  }
  return SurfaceModesRequest(
    columns: cells,
    rows: cells,
    cell: 0.016 / cells,
    index: index,
    count: 6,
  );
}

void main() {
  test('the isolate answers what the frame would have, to the bit', () async {
    // Mutation: solve another way off the frame — the halving meniscus, the
    // conjugate gradients — and the bits differ.
    LiquidShapeCache.shared.clear();
    final background = BackgroundShapeSolver();
    addTearDown(background.dispose);
    final cut = _roundCut(24);
    final meniscus = MeniscusRequest(
      medium: FluidMedium.water,
      radius: 0.004,
      g: 9.81,
    );
    expect(background.surfaceModes(cut), isNull);
    expect(background.meniscus(meniscus), isNull);
    await background.settled();
    final modes = background.surfaceModes(cut)!;
    final menisci = background.meniscus(meniscus)!;
    final inline = solveSurfaceModes(cut);
    expect(modes.k2, inline.k2);
    for (var n = 0; n < inline.shapes.length; n++) {
      expect(modes.shapes[n], inline.shapes[n]);
    }
    final here = solveMeniscus(meniscus);
    expect(menisci.apexCurvature, here.apexCurvature);
    expect(menisci.wallRise, here.wallRise);
  });

  test('a world steps on while its shapes are worked out', () async {
    LiquidShapeCache.shared.clear();
    final background = BackgroundShapeSolver();
    addTearDown(background.dispose);
    final world = FluidWorld(
      gravity: Vector3(0, -9.81, 0),
      shapes: background,
      profile: SimulationProfile.accurate,
    );
    final tube = LiquidBody(
      shape: RevolvedVessel([
        Vector2(0, 0),
        Vector2(0.008, 0),
        Vector2(0.008, 0.1),
      ]),
      medium: FluidMedium.water,
      volume: 1e-5,
      modes: 4,
    );
    world.bodies.add(tube);
    tube.place(Matrix3.identity(), Vector3.zero());
    world.advance(world.step);
    await background.settled();
    for (var i = 0; i < 4; i++) {
      tube.place(Matrix3.identity(), Vector3.zero(), time: world.time);
      world.advance(world.step);
    }
    expect(tube.surface.wavenumbers, isNotEmpty);
    expect(background.pending, 0);
  });
}
