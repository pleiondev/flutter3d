/// `bevelEdges`/`bevelVertices`: a corner cut off every beveled edge or
/// vertex, walled with a bridge quad per edge and a cap n-gon per vertex.
///
///     dart test test/bevel_test.dart
library;

import 'dart:math' as math;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:test/test.dart';

Selection allEdges(EditMesh mesh) => Selection.of(ElementLevel.edge, <int>[
  for (var he = 0; he < mesh.halfEdgeSlotCount; he++)
    if (mesh.edgeOf(he) == he && mesh.faceOf(he) != EditMesh.none) he,
]);

/// Runs [body] as one step of history — every operation in this package that
/// mutates a mesh in place expects an already-open step, the same reason
/// `inset_test.dart`'s own identical helper exists for `insetFaces`.
T edit<T>(EditMesh mesh, T Function() body) {
  mesh.beginStep();
  final result = body();
  mesh.endStep();
  return result;
}

void main() {
  group('bevelEdges on a whole cube: mesh-44\'s own acceptance', () {
    test('24 vertices, 26 faces, χ = 2, no boundary edges', () {
      final cube = EditMesh.cuboid();
      final result = edit(
        cube,
        () => bevelEdges(cube, allEdges(cube), width: 0.1),
      );

      expect(result.ok, isTrue, reason: result.reason);
      cube.validate();

      expect(cube.vertexCount, 24);
      expect(cube.faceCount, 26);
      expect(cube.eulerCharacteristic, 2);

      var boundary = 0;
      for (var f = 0; f < cube.faceSlotCount; f++) {
        if (!cube.isFaceAlive(f)) continue;
        cube.forEachHalfEdge(f, (int he) {
          if (!cube.hasLiveTwin(he)) boundary++;
        });
      }
      expect(boundary, 0);
    });

    test('8 triangular corner caps and 12 quad bridges among the 26', () {
      final cube = EditMesh.cuboid();
      edit(cube, () => bevelEdges(cube, allEdges(cube), width: 0.1));

      final byValency = <int, int>{};
      for (var f = 0; f < cube.faceSlotCount; f++) {
        if (!cube.isFaceAlive(f)) continue;
        final n = cube.valencyOf(f);
        byValency[n] = (byValency[n] ?? 0) + 1;
      }

      // Mutation: cap the vertex n-gon with the wrong valence, or fail to
      // separate a bridge from a shrunk original quad, and this count moves.
      expect(byValency[3], 8, reason: 'the eight corner caps');
      expect(byValency[4], 18, reason: '12 bridges + 6 shrunk original faces');
    });

    test('the shape stays convex and roughly cube-sized, not inverted', () {
      final cube = EditMesh.cuboid();
      final before = cube.signedVolume;
      edit(cube, () => bevelEdges(cube, allEdges(cube), width: 0.1));

      // Mutation: wind a cap or a bridge backwards, and the volume either
      // goes negative or collapses toward zero rather than staying close to
      // the original cube's own, slightly smaller for the corners cut off.
      expect(cube.signedVolume, greaterThan(0));
      expect(cube.signedVolume, lessThan(before));
      expect(cube.signedVolume, greaterThan(before * 0.8));
    });

    test('a second, independent implementation finds the same triangle '
        'area cut from each of the 8 corners', () {
      // Beveling every edge of a unit cube by w cuts a right tetrahedron off
      // each corner whose three cut edges each have length w*sqrt(2) — the
      // three original edges at a cube corner are mutually perpendicular,
      // so each new triangular face is equilateral with that side length.
      // Its own area, computed here from first principles rather than from
      // this file's own bevel code, is what the corner caps' summed area
      // should equal.
      final cube = EditMesh.cuboid();
      const width = 0.1;
      edit(cube, () => bevelEdges(cube, allEdges(cube), width: width));

      final side = width * math.sqrt(2);
      final expectedTriangleArea = math.sqrt(3) / 4 * side * side;

      var capAreaSum = 0.0;
      var capCount = 0;
      for (var f = 0; f < cube.faceSlotCount; f++) {
        if (!cube.isFaceAlive(f) || cube.valencyOf(f) != 3) continue;
        capAreaSum += cube.areaOf(f);
        capCount++;
      }
      expect(capCount, 8);
      expect(capAreaSum / capCount, closeTo(expectedTriangleArea, 1e-6));
    });
  });

  group('clampOverlap', () {
    test('a width bigger than half the edge is scaled down, not refused', () {
      final cube = EditMesh.cuboid(); // 1×1×1, every edge length 1
      final result = edit(
        cube,
        () => bevelEdges(cube, allEdges(cube), width: 10.0, clampOverlap: true),
      );
      expect(result.ok, isTrue, reason: result.reason);
      cube.validate();
      expect(cube.signedVolume, greaterThan(0));

      // A width of 10 was asked for; clamped, the actual width used should
      // be (shortest edge / 2) * 0.999 = 0.4995, not 10 — checked the same
      // way the acceptance test above checks the real corner-cap area,
      // against a width computed independently of this file's own clamp
      // arithmetic. Mutation: disable the clamp entirely and this triangle
      // is instead the one a width of 10 predicts, off by four orders of
      // magnitude.
      const clampedWidth = 1.0 / 2 * 0.999;
      final side = clampedWidth * math.sqrt(2);
      final expectedTriangleArea = math.sqrt(3) / 4 * side * side;
      var capAreaSum = 0.0;
      var capCount = 0;
      for (var f = 0; f < cube.faceSlotCount; f++) {
        if (!cube.isFaceAlive(f) || cube.valencyOf(f) != 3) continue;
        capAreaSum += cube.areaOf(f);
        capCount++;
      }
      expect(capCount, 8);
      expect(capAreaSum / capCount, closeTo(expectedTriangleArea, 1e-6));
    });
  });

  group('what it refuses', () {
    test('no edges selected', () {
      final cube = EditMesh.cuboid();
      final result = edit(
        cube,
        () => bevelEdges(cube, Selection.empty(ElementLevel.edge), width: 0.1),
      );
      expect(result.ok, isFalse);
    });

    test('segments above 1', () {
      final cube = EditMesh.cuboid();
      final result = edit(
        cube,
        () => bevelEdges(cube, allEdges(cube), width: 0.1, segments: 2),
      );
      expect(result.ok, isFalse);
      expect(result.reason, contains('segments'));
    });

    test('a face with only some of its own edges selected', () {
      final cube = EditMesh.cuboid();
      // One edge of one face, its neighbours left alone: the face this edge
      // belongs to has three other edges not in the selection.
      final oneCanonicalEdge = <int>[
        for (var he = 0; he < cube.halfEdgeSlotCount; he++)
          if (cube.edgeOf(he) == he) he,
      ].first;
      final result = edit(
        cube,
        () => bevelEdges(
          cube,
          Selection.of(ElementLevel.edge, <int>[oneCanonicalEdge]),
          width: 0.1,
        ),
      );
      expect(result.ok, isFalse);
      expect(result.reason, contains('every edge'));
    });
  });

  group('bevelVertices', () {
    test('beveling every vertex of a cube gives the same shape beveling '
        'every edge does', () {
      final byVertex = EditMesh.cuboid();
      final allVertices = Selection.of(ElementLevel.vertex, <int>[
        for (var v = 0; v < byVertex.vertexSlotCount; v++)
          if (byVertex.isVertexAlive(v)) v,
      ]);
      edit(byVertex, () => bevelVertices(byVertex, allVertices, width: 0.1));

      final byEdge = EditMesh.cuboid();
      edit(byEdge, () => bevelEdges(byEdge, allEdges(byEdge), width: 0.1));

      expect(byVertex.vertexCount, byEdge.vertexCount);
      expect(byVertex.faceCount, byEdge.faceCount);
      expect(byVertex.signedVolume, closeTo(byEdge.signedVolume, 1e-6));
    });
  });
}
