/// A huge mesh is cut into clusters that hold every triangle once, stay
/// within their size, and face one way enough to be culled — `C9`.
///
///     dart test test/cluster_mesh_test.dart
library;

import 'dart:math' as math;

import 'package:flutter3d_core/geometry.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:test/test.dart';

/// Each triangle as its three indices, sorted by the triple so two buffers
/// holding the same triangles in any order compare equal.
List<String> _triangles(MeshData mesh) => <String>[
  for (var t = 0; t < mesh.triangleCount; t++)
    mesh.indices.sublist(t * 3, t * 3 + 3).join(','),
]..sort();

void main() {
  final sphere = const SphereShape(
    radius: 1.0,
    segments: 256,
    rings: 128,
  ).build();
  final split = clusterMesh(sphere, maxTriangles: 512, minTriangles: 128);

  test('every triangle lands in exactly one cluster, winding kept', () {
    // Mutation: write a triangle's corners in another order, or drop the
    // last cluster's run, and the sorted triples no longer agree.
    expect(split.vertices, same(sphere.vertices));
    expect(_triangles(split), _triangles(sphere));
    final table = split.clusters!;
    expect(table.indexCount, sphere.indexCount);
  });

  test('clusters stay within their size', () {
    final table = split.clusters!;
    final sizes = <int>[
      for (var i = 0; i < table.length; i++) table.indexCountOf(i) ~/ 3,
    ];
    expect(sizes.every((size) => size <= 512), isTrue);
    // A closed sphere has no islands, so only the last cluster may be
    // left short of the minimum.
    expect(sizes.where((size) => size < 128).length, lessThanOrEqualTo(1));
    expect(table.length, lessThan(sphere.triangleCount ~/ 128 + 2));
  });

  test('clusters face one way enough to be culled from outside', () {
    // Mutation: take the newest candidate instead of the best-scored one, and
    // each cluster snakes across the sphere; its cone widens until it hardly
    // ever culls.
    final table = split.clusters!;
    final random = math.Random(4);
    var culled = 0, asked = 0;
    for (var trial = 0; trial < 50; trial++) {
      final theta = random.nextDouble() * math.pi * 2;
      final phi = math.acos(random.nextDouble() * 2 - 1);
      final distance = 3.0 + random.nextDouble() * 5.0;
      final x = distance * math.sin(phi) * math.cos(theta);
      final y = distance * math.cos(phi);
      final z = distance * math.sin(phi) * math.sin(theta);
      for (var i = 0; i < table.length; i++) {
        asked++;
        if (table.facesAwayFrom(i, x, y, z)) culled++;
      }
    }
    // From outside a sphere half of it faces away; the cones catch most of
    // that half.
    expect(culled / asked, greaterThan(0.3));
  });

  test('the same mesh splits the same way every time', () {
    final again = clusterMesh(sphere, maxTriangles: 512, minTriangles: 128);
    expect(again.indices, split.indices);
    expect(again.clusters!.firstIndices, split.clusters!.firstIndices);
  });

  test('a small mesh is one cluster', () {
    final small = const SphereShape(segments: 8, rings: 4).build();
    final split = clusterMesh(small);
    expect(split.clusters!.length, 1);
    expect(_triangles(split), _triangles(small));
  });
}
