/// `pro-sim-04`'s own timing acceptance: playing back a 4000-vertex frame
/// through `overwriteVertices` takes under 2ms.
///
///     flutter test test/simulation_playback_bench_test.dart
///
/// Same house style as `pro-eng-01`'s own
/// `packages/flutter3d/test/device_mesh_overwrite_bench_test.dart`: a
/// [FakeBackend] (records wiring, not content — see that file's own doc
/// comment for why this still measures something real, the CPU-side
/// arithmetic `overwriteVertices` and this call do on top of a backend's own
/// write), a warm-up loop so the first call does not measure the JIT, a real
/// [Stopwatch], and the measured number printed rather than only asserted —
/// this file's row is a real millisecond promise about real hardware, not
/// just a pass/fail.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter3d_modeler/src/simulation_playback.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/simulation_cache_stub.dart';

void main() {
  test('playing back a 4000-vertex frame takes under 2ms', () {
    const vertexCount = 4000;
    final meshData = MeshData(
      layout: VertexLayout.positionOnly,
      vertices: Float32List(vertexCount * 3),
      indices: Uint32List.fromList([0, 1, 2]),
    );
    final device = FakeBackend();
    final mesh = DeviceMesh.upload(device, meshData, keepSourceData: false);

    // A single frame whose positions differ from the mesh's own rest pose, so
    // the call is a real overwrite rather than a no-op write of zeros onto
    // zeros.
    final frame = Float32List(vertexCount * 3);
    for (var i = 0; i < frame.length; i++) {
      frame[i] = (i % 97) * 0.01;
    }
    final cache = SimulationCacheStub(vertexCount: vertexCount, frames: [frame]);

    // Warm, because the first call through a JIT measures the compiler.
    for (var i = 0; i < 50; i++) {
      playSimulationFrame(mesh, device, cache, 0);
    }

    const runs = 500;
    final stopwatch = Stopwatch()..start();
    for (var i = 0; i < runs; i++) {
      playSimulationFrame(mesh, device, cache, 0);
    }
    stopwatch.stop();

    final perCallMicros = stopwatch.elapsedMicroseconds / runs;
    // ignore: avoid_print — the number is the point of this file.
    print(
      'playSimulationFrame, $vertexCount vertices '
      '(${vertexCount * 12} bytes): ${perCallMicros.toStringAsFixed(1)} us',
    );

    expect(perCallMicros, lessThan(2000)); // 2ms, the row's own acceptance.
  });
}
