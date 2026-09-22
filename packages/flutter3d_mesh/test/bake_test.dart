/// `pro-rt-04`/`pro-rt-05`: the UV rasterizer, the normal-map cage, the
/// dilation, and the AO/curvature/thickness maps over the same texels.
///
///     dart test test/bake_test.dart
library;

import 'package:flutter3d_core/geometry.dart' show TriangleBvh;
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A unit quad on the `z = 0` plane, UV-mapped corner to corner — the
/// simplest low mesh a bake can be reasoned about analytically on.
EditMesh sheet({double z = 0, bool facingDown = false}) {
  final builder = EditMeshBuilder();
  builder
    ..addVertex(Vector3(0, 0, z))
    ..addVertex(Vector3(1, 0, z))
    ..addVertex(Vector3(1, 1, z))
    ..addVertex(Vector3(0, 1, z));
  // The winding is the normal: the same four corners the other way round is
  // the same quad facing -Z, which is what a bake has to follow rather than
  // the world's own +Z.
  final int face = builder.addFace(
    facingDown ? <int>[3, 2, 1, 0] : <int>[0, 1, 2, 3],
  );
  final EditMesh mesh = builder.build();
  mesh.beginStep();
  mesh.forEachHalfEdge(face, (int he) {
    final Vector3 at = mesh.positionOf(mesh.originOf(he));
    mesh.setUv(he, Vector2(at.x, at.y));
  });
  mesh.endStep();
  mesh.clearJournal();
  return mesh;
}

/// A sphere of [radius] about [centre], as a tree to cast against.
TriangleBvh sphere({double radius = 1, Vector3? centre}) {
  final EditMesh mesh = ParametricSphere(
    radius: radius,
    segments: 48,
    rings: 24,
  ).toEditMesh();
  final Vector3 at = centre ?? Vector3.zero();
  if (at.length2 > 0) {
    mesh.beginStep();
    for (var v = 0; v < mesh.vertexSlotCount; v++) {
      if (!mesh.isVertexAlive(v)) continue;
      mesh.moveVertex(v, mesh.positionOf(v)..add(at));
    }
    mesh.endStep();
  }
  return surfaceOf(mesh);
}

void main() {
  group('the rasterizer', () {
    test('covers the texels the UVs reach and no others', () {
      final covered = <String>{};
      rasterizeUv(
        sheet(),
        16,
        (BakeSample it) => covered.add('${it.x},${it.y}'),
      );
      // The quad spans the whole 0..1 square, so every texel of a 16² map is
      // on it — and the count says the fill is not off by a row.
      expect(covered, hasLength(16 * 16));
    });

    test('and hands back an orthonormal frame at each of them', () {
      rasterizeUv(sheet(), 4, (BakeSample it) {
        expect(it.normal.length, closeTo(1, 1e-5));
        expect(it.tangent.length, closeTo(1, 1e-5));
        expect(it.bitangent.length, closeTo(1, 1e-5));
        expect(it.tangent.dot(it.normal), closeTo(0, 1e-5));
        expect(it.bitangent.dot(it.normal), closeTo(0, 1e-5));
        // The sheet faces +Z and U increases along +X: the frame is the one
        // a renderer reconstructs, not an arbitrary basis that happens to be
        // perpendicular.
        expect(it.normal.z.abs(), closeTo(1, 1e-5));
        expect(it.tangent.x.abs(), closeTo(1, 1e-5));
      });
    });

    test('a mesh with no UVs bakes nothing rather than throwing', () {
      var samples = 0;
      rasterizeUv(EditMesh.cuboid(), 8, (BakeSample _) => samples++);
      expect(samples, 0);
    });

    test('and a size below one is not a size', () {
      expect(
        () => rasterizeUv(sheet(), 0, (BakeSample _) {}),
        throwsArgumentError,
      );
    });
  });

  group('the normal map', () {
    test('is flat where the high surface is parallel to the low one', () {
      // A second sheet just below the first: the analytic answer at every
      // texel is (0, 0, 1), which is what a tangent-space map calls "no
      // change". Flat against flat, so the only thing that can be wrong
      // here is the frame or the cage.
      final BakedMap map = bakeNormalMap(
        low: sheet(),
        high: surfaceOf(sheet(z: -0.05)),
        size: 32,
        shell: 0.2,
      );

      expect(map.at(16, 16, 2), closeTo(1, 2 / 255));
      expect(map.at(16, 16, 0).abs(), lessThan(2 / 255));
      expect(map.at(16, 16, 1).abs(), lessThan(2 / 255));
    });

    test('and a sphere under it bakes the bulge the row asks for', () {
      // A sphere touching the sheet from below, its pole under the middle
      // texel. The analytic answer there is (0, 0, 1) and it falls away
      // toward the edges of the patch — the row's own "sphere→cube: the
      // face centre matches analytically".
      //
      // **The tolerance is the sphere's own faceting, not the bake's.** A
      // parametric sphere of forty-eight segments has facets seven and a
      // half degrees wide, and a ray lands on one facet rather than on the
      // ideal surface, so the centre texel is within a facet's own tilt of
      // straight up rather than within a 255th.
      final BakedMap map = bakeNormalMap(
        low: sheet(),
        high: sphere(radius: 2, centre: Vector3(0.5, 0.5, -2.02)),
        size: 32,
        shell: 0.2,
      );
      expect(map.at(16, 16, 2), greaterThan(0.99));
      expect(map.at(2, 16, 2), lessThan(map.at(16, 16, 2)));
    });

    test('and follows the low mesh rather than the world', () {
      // The same geometry with the sheet's own normal pointing the other
      // way: the tangent-space answer is still "no change", and a map
      // written in world space would be (0, 0, -1) here.
      final BakedMap map = bakeNormalMap(
        low: sheet(facingDown: true),
        high: surfaceOf(sheet(z: 0.05, facingDown: true)),
        size: 32,
        shell: 0.2,
      );
      expect(map.at(16, 16, 2), closeTo(1, 2 / 255));
    });

    test('a texel whose cage is empty is left uncovered', () {
      final BakedMap map = bakeNormalMap(
        low: sheet(),
        // Far out of reach of a shell of 0.01.
        high: sphere(radius: 1, centre: Vector3(0.5, 0.5, -20)),
        size: 8,
        shell: 0.01,
      );
      // **A texel with nothing in its cage is not a texel that bakes to
      // zero.** Mutation: take whatever the ray eventually hits. A low mesh
      // that has sunk below the detail then picks up the geometry on the far
      // side of the model, which is worse than a hole `dilate` can fill.
      expect(map.covered.every((int it) => it == 0), isTrue);
    });

    test('is written to eight bits with the right bias', () {
      final BakedMap map = BakedMap(2, 3);
      map.write(0, 0, <double>[0, 0, 1]);
      map.write(1, 1, <double>[-1, 0, 0]);
      final bytes = map.toRgba8(bias: 1, scale: 0.5);
      // A flat normal is the familiar (128, 128, 255).
      expect(bytes[0], 128);
      expect(bytes[1], 128);
      expect(bytes[2], 255);
      expect(bytes[3], 255);
      // And one pointing fully along -U is (0, 128, 128).
      expect(bytes[(1 * 2 + 1) * 4], 0);
    });
  });

  group('dilation', () {
    test('pushes the edge outward and leaves the inside alone', () {
      final BakedMap map = BakedMap(8, 1);
      map.write(4, 4, <double>[1]);
      expect(map.covered.where((int it) => it != 0), hasLength(1));

      dilate(map, rings: 2);

      // Two rings out from one texel is a 5×5 block.
      expect(map.covered.where((int it) => it != 0), hasLength(25));
      expect(map.at(4, 4, 0), 1);
      expect(map.at(5, 4, 0), 1);
      // **Mutation: blur instead of flooding.** The covered texel would move
      // toward its empty neighbours and the island's own edge would fade,
      // which is the seam this exists to prevent rather than the one it
      // draws.
      expect(map.at(4, 4, 0), 1);
    });

    test('and stops when there is nothing left to grow into', () {
      final BakedMap map = BakedMap(4, 1);
      map.write(0, 0, <double>[1]);
      dilate(map, rings: 64);
      expect(map.covered.every((int it) => it != 0), isTrue);
    });

    test('an empty map stays empty', () {
      final BakedMap map = BakedMap(4, 1);
      dilate(map);
      expect(map.covered.every((int it) => it == 0), isTrue);
    });
  });

  group('the masks', () {
    test('a plane under open sky is unoccluded', () {
      final BakedMap map = bakeAmbientOcclusion(
        low: sheet(),
        high: surfaceOf(sheet()),
        size: 8,
        samples: 32,
        distance: 2,
      );
      // **The row's own "a plane gives AO=1".** Every ray leaves a flat
      // surface and meets nothing; a bias that was too small would have the
      // surface occluding itself and this would come out near zero.
      expect(map.at(4, 4, 0), closeTo(1, 1e-6));
    });

    test('and a right angle is about half', () {
      // A second sheet standing up along `x = 0`: half the hemisphere over
      // the floor near the wall is blocked.
      final builder = EditMeshBuilder();
      builder
        ..addVertex(Vector3(0, 0, 0))
        ..addVertex(Vector3(0, 1, 0))
        ..addVertex(Vector3(0, 1, 1))
        ..addVertex(Vector3(0, 0, 1));
      builder.addFace(<int>[0, 1, 2, 3]);
      final TriangleBvh wall = surfaceOf(builder.build());

      final BakedMap map = bakeAmbientOcclusion(
        low: sheet(),
        high: wall,
        size: 16,
        samples: 128,
        distance: 4,
      );
      // Right up against the wall, half the sky is gone. The row's own
      // "a 90° angle ≈0.5"; the tolerance is what a hundred and twenty-eight
      // Halton samples over a finite wall can promise.
      expect(map.at(0, 8, 0), closeTo(0.5, 0.12));
      // And well away from it, almost none of it is.
      expect(map.at(15, 8, 0), greaterThan(0.85));
    });

    test('curvature reads flat as the middle of the range', () {
      final BakedMap map = bakeCurvature(low: sheet(), size: 8);
      expect(map.at(4, 4, 0), closeTo(0.5, 1e-6));
    });

    test('and thickness reads a sheet with nothing behind it as solid', () {
      final BakedMap map = bakeThickness(
        low: sheet(),
        high: surfaceOf(sheet()),
        size: 8,
        samples: 16,
        distance: 1,
      );
      // Nothing under the sheet, so every ray runs the full distance: the
      // far side is as far away as the query looks.
      expect(map.at(4, 4, 0), closeTo(1, 1e-6));
    });

    test('a bake is the same bytes twice', () {
      BakedMap once() => bakeAmbientOcclusion(
        low: sheet(),
        high: sphere(radius: 2, centre: Vector3(0.5, 0.5, -1.6)),
        size: 8,
        samples: 16,
        distance: 2,
      );
      // **Halton rather than `Random`.** Mutation: seed a generator. Two
      // runs of the same bake then differ, and every golden that contains a
      // baked map becomes a test nobody can keep green.
      expect(once().data, once().data);
    });
  });

  group('what it costs', () {
    test('a thousand-triangle high mesh at 256² in a few seconds', () {
      final stopwatch = Stopwatch()..start();
      final BakedMap map = bakeNormalMap(
        low: sheet(),
        high: sphere(radius: 2, centre: Vector3(0.5, 0.5, -1.6)),
        size: 256,
        shell: 0.6,
      );
      stopwatch.stop();
      // ignore: avoid_print
      print(
        'bake: 256² over ${256 * 256} texels in '
        '${stopwatch.elapsedMilliseconds} ms',
      );
      expect(map.covered.where((int it) => it != 0).length, greaterThan(1000));
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 30)));
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
