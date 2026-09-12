/// What `DeviceMesh.overwriteVertices` itself costs on top of a backend's own
/// write — `view-14`'s own acceptance number: 1% of 200k vertices, under a
/// millisecond.
///
///     flutter test test/device_mesh_overwrite_bench_test.dart
///
/// **[FakeBackend]'s own `overwriteGeometry` records wiring, not content —
/// it copies nothing.** So this is not a measurement of a real write, on
/// this backend or any other; Impeller needs a real device and WebGL a
/// browser to answer that, the same reason `skeleton_posing_test.dart`'s own
/// benchmark is JIT rather than AOT and neither answers for every platform.
/// What runs regardless of backend is `overwriteVertices`'s own bounds-refit
/// arithmetic — the part this row's own cycle added — which is exactly the
/// part a naive mistake there (rescanning the whole mesh instead of the
/// touched range, say) would show up in first. A real backend's own write on
/// top of this is real work still to measure on real hardware.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('overwriting 1% of a 200k-vertex mesh', () {
    const vertexCount = 200000;
    const layout = VertexLayout.standard;
    final mesh = MeshData(
      layout: layout,
      vertices: Float32List(vertexCount * layout.floatsPerVertex),
      indices: Uint32List.fromList(<int>[0, 1, 2]),
    );
    final device = FakeBackend();
    final target = DeviceMesh.upload(device, mesh, keepSourceData: false);

    final stride = target.vertices.lengthInBytes ~/ target.vertexCount;
    const touched = vertexCount ~/ 100; // 1%.
    final patch = ByteData(stride * touched);

    // Warm, because the first call through a JIT measures the compiler.
    for (var i = 0; i < 100; i++) {
      target.overwriteVertices(device, 0, patch);
    }

    final stopwatch = Stopwatch()..start();
    const runs = 1000;
    for (var i = 0; i < runs; i++) {
      target.overwriteVertices(device, 0, patch);
    }
    stopwatch.stop();

    final perCall = stopwatch.elapsedMicroseconds / runs;
    // ignore: avoid_print — the number is the point of this file.
    print(
      'overwriteVertices, $touched of $vertexCount vertices '
      '(${patch.lengthInBytes} bytes): ${perCall.toStringAsFixed(1)} us',
    );

    // A budget, not the literal acceptance number: the row's own "<1 ms" is
    // a promise about a real backend's own write, on top of the bounds-refit
    // arithmetic this measures — [FakeBackend] contributes none of it. A
    // hundred microseconds is two orders of magnitude under the row's own
    // millisecond, room enough that a regression which lost most of that —
    // the refit loop reading every vertex instead of the touched range, say
    // — is caught here before it ever reaches a real device.
    expect(perCall, lessThan(100));
  });
}
