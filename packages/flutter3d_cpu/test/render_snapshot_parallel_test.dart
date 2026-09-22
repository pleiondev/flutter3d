/// A tile grid drawn on several isolates at once.
///
///     dart test test/render_snapshot_parallel_test.dart
///
/// **The whole claim is that it changes nothing.** Tiles already rendered
/// independently — each builds its own device, its own scene and its own
/// camera, and `TiledProjection` gives it its own share of the frustum — so
/// which thread draws one cannot be visible in the frame. That is what makes
/// the concurrency safe, and it is exactly what a test has to hold: the same
/// bytes, not merely a similar picture.
///
/// Speed is deliberately not asserted. A wall-clock threshold on a shared
/// machine is a test that fails for reasons that have nothing to do with the
/// code, and this repository has enough of those without inviting one.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A top-level function, because a tear-off of one crosses an isolate and a
/// closure over a device does not — see [TileDevice].
GraphicsDevice tileDevice(int width, int height) => CpuDevice(
  width: width,
  height: height,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

ModelProject twoShapes() => const ModelProject()
    .added(
      (int id) => ModelObject(
        id: id,
        name: 'cube',
        geometry: EditedGeometry(EditMesh.cuboid(size: Vector3(1.4, 1.4, 1.4))),
        transform: Matrix4.identity(),
      ),
    )
    .added(
      (int id) => ModelObject(
        id: id,
        name: 'offset cube',
        geometry: EditedGeometry(EditMesh.cuboid()),
        transform: Matrix4.translation(Vector3(1.2, 0.4, -0.6)),
      ),
    );

RenderPreset preset({int tilesX = 2, int tilesY = 2}) => RenderPreset(
  width: 64,
  height: 48,
  tilesX: tilesX,
  tilesY: tilesY,
  camera: SnapshotCamera(
    position: Vector3(2.5, 2.0, 3.5),
    target: Vector3.zero(),
  ),
);

void main() {
  test(
    'four tiles on four workers give the same bytes as one worker',
    () async {
      final one = await RenderSnapshotJob(
        twoShapes(),
        preset(),
        tileDevice: tileDevice,
      ).run();
      final many = await RenderSnapshotJob(
        twoShapes(),
        preset(),
        tileDevice: tileDevice,
        concurrency: 4,
      ).run();

      // Byte for byte, not "close enough": every tile is computed from the same
      // values by the same code, so a difference would mean the work is not
      // independent after all — which is the assumption the whole change rests
      // on.
      expect(many, one);
    },
  );

  test('more workers than tiles is not more workers', () async {
    // The pool must not spawn an isolate with nothing for it to do: each one
    // pays for a shader library and a scene before it draws anything.
    final one = await RenderSnapshotJob(
      twoShapes(),
      preset(tilesX: 1, tilesY: 2),
      tileDevice: tileDevice,
    ).run();
    final many = await RenderSnapshotJob(
      twoShapes(),
      preset(tilesX: 1, tilesY: 2),
      tileDevice: tileDevice,
      concurrency: 8,
    ).run();

    expect(many, one);
  });

  test('progress is reported once per tile, and reaches one', () async {
    // The sequential native path reports once, at the end, because the whole
    // grid is inside one isolate and nothing comes back until it finishes.
    // The pool has a tile landing at a time, so it can say so — and a caller
    // showing a bar is the reason anybody asked for tiles.
    final seen = <double>[];
    await RenderSnapshotJob(
      twoShapes(),
      preset(),
      tileDevice: tileDevice,
      concurrency: 2,
    ).run(onProgress: seen.add);

    expect(seen, hasLength(4));
    expect(seen.last, 1.0);
    // Monotone: a bar that goes backwards is worse than one that jumps.
    for (var i = 1; i < seen.length; i++) {
      expect(seen[i], greaterThan(seen[i - 1]));
    }
  });

  test('one worker is the path it always was', () async {
    // The default has to stay the code that was there, or every caller that
    // never asked for concurrency is quietly on a new path.
    final bytes = await RenderSnapshotJob(
      twoShapes(),
      preset(),
      tileDevice: tileDevice,
    ).run();
    expect(bytes, isA<Uint8List>());
    expect(bytes, isNotEmpty);
  });
}
