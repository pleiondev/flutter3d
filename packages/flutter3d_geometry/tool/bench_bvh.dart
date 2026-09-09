// ignore_for_file: avoid_print — a command-line benchmark whose whole output is
// stdout.

/// What picking a face costs, with a tree and without one.
///
///     dart compile exe tool/bench_bvh.dart -o /tmp/bench && /tmp/bench
///
/// **The question `p0-10` asks.** Clicking in a viewport means finding which
/// triangle a ray hits, and the honest baseline is asking every triangle. That
/// is fine for a cube and hopeless for a scan: the plan's thresholds are a ray
/// under 1 ms at 200 000 triangles, under 3 ms at a million, and a build under
/// 100 ms — if they hold, picking stays on the CPU and needs no id-buffer pass
/// and no half-edge neighbourhood search.
///
/// Sizes are triangle counts, not vertex counts, because that is what both the
/// tree and the scan are linear in.
library;

import 'dart:math';

import 'package:flutter3d_geometry/flutter3d_geometry.dart';
import 'package:vector_math/vector_math.dart' hide Ray;

/// A sphere of about [triangles] triangles: the shape a scan is worst at,
/// because every ray that misses still touches most of its bounding box.
MeshData sphereOf(int triangles) {
  // A sphere of s segments and r rings has 2 * s * r triangles; keeping
  // r = s / 2 gives roughly square quads.
  final segments = max(8, sqrt(triangles).round());
  return SphereShape(
    radius: 1,
    segments: segments,
    rings: segments ~/ 2,
  ).build();
}

double milliseconds(int iterations, void Function() body) {
  body();
  final stopwatch = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    body();
  }
  stopwatch.stop();
  return stopwatch.elapsedMicroseconds / iterations / 1000.0;
}

void main() {
  for (final wanted in <int>[50000, 200000, 1000000]) {
    final mesh = sphereOf(wanted);
    final triangles = mesh.indices.length ~/ 3;
    print('');
    print('--- $triangles triangles ------------------------------------');

    final build = milliseconds(3, () => TriangleBvh.fromMesh(mesh));
    print('build                       ${build.toStringAsFixed(2)} ms');

    final bvh = TriangleBvh.fromMesh(mesh);
    final refit = milliseconds(20, bvh.refit);
    print('refit                       ${refit.toStringAsFixed(2)} ms');

    // Ten thousand rays, seeded, aimed the way a person clicks: from where the
    // camera is, at the middle of the model.
    final random = Random(20260909);
    final rays = <Ray>[
      for (var i = 0; i < 10000; i++)
        () {
          final origin = Vector3(
            random.nextDouble() * 6 - 3,
            random.nextDouble() * 6 - 3,
            random.nextDouble() * 6 - 3,
          );
          return Ray(origin, (Vector3.zero() - origin)..normalize());
        }(),
    ];

    final perRay =
        milliseconds(3, () {
          for (final ray in rays) {
            bvh.raycast(ray);
          }
        }) /
        rays.length;
    print(
      'one ray, through the tree   ${(perRay * 1000).toStringAsFixed(1)} us',
    );

    // The baseline, on a hundred rays rather than ten thousand: a scan of a
    // million triangles is milliseconds apiece and ten thousand of them is a
    // benchmark nobody waits for.
    final offset = mesh.layout.floatOffsetOf(VertexLayout.position.name);
    final stride = mesh.layout.floatsPerVertex;
    Vector3 vertexAt(int index) => Vector3(
      mesh.vertices[index * stride + offset],
      mesh.vertices[index * stride + offset + 1],
      mesh.vertices[index * stride + offset + 2],
    );
    final sample = rays.take(100).toList(growable: false);
    final perScan =
        milliseconds(3, () {
          for (final ray in sample) {
            var best = double.infinity;
            for (var t = 0; t * 3 < mesh.indices.length; t++) {
              final hit = rayTriangle(
                ray,
                vertexAt(mesh.indices[t * 3]),
                vertexAt(mesh.indices[t * 3 + 1]),
                vertexAt(mesh.indices[t * 3 + 2]),
              );
              if (hit >= 0 && hit < best) best = hit;
            }
          }
        }) /
        sample.length;
    print(
      'one ray, asking every triangle '
      '${perScan.toStringAsFixed(2)} ms  '
      '(${(perScan / perRay).round()}x)',
    );
  }
}
