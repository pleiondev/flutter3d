/// Shrinking a face's own border inward, and walling in the ring it leaves.
///
///     dart test test/inset_test.dart
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// Runs [body] as one step of history.
void edit(EditMesh mesh, void Function() body) {
  mesh.beginStep();
  body();
  mesh.endStep();
}

Selection faceZero() => Selection.of(ElementLevel.face, <int>[0]);

void main() {
  group('insetFaces', () {
    test('a cube face: +4 vertices, +4 quads', () {
      final mesh = EditMesh.cuboid();
      final beforeVertices = mesh.vertexCount;
      final beforeFaces = mesh.faceCount;

      late OpResult result;
      edit(mesh, () {
        result = insetFaces(mesh, faceZero(), thickness: 0.1);
      });
      expect(result.reason, isNull);
      mesh.validate();

      // Mutation: reuse the boundary's own vertices for the inner ring
      // instead of adding a fresh set — the count stops moving with the
      // inset at all.
      expect(mesh.vertexCount, beforeVertices + 4);
      // Mutation: delete the original face and rebuild it instead of
      // remapping its half-edges onto the new ring — the face count would
      // then move by five (four walls plus a fresh inner face) rather than
      // four, since nothing here is meant to add the inner face twice.
      expect(mesh.faceCount, beforeFaces + 4);
    });

    test('ux-39: one quad on its own insets to five faces', () {
      final mesh = EditMesh.fromFaces(
        <Vector3>[
          Vector3(0, 0, 0),
          Vector3(1, 0, 0),
          Vector3(1, 1, 0),
          Vector3(0, 1, 0),
        ],
        <List<int>>[
          <int>[0, 1, 2, 3],
        ],
      );

      mesh.beginStep();
      final OpResult result = insetFaces(
        mesh,
        Selection.of(ElementLevel.face, <int>[0]),
        thickness: 0.2,
      );
      mesh.endStep();

      // The row's own acceptance: the face itself, remapped onto the inner
      // ring, and one wall per edge. Mutation: add the inner face as a new
      // one instead of remapping — six faces, and the original's material
      // and smoothing left on a face nobody can see.
      expect(result.reason, isNull);
      expect(mesh.faceCount, 5);
      mesh.validate();
    });

    test('the inset face keeps its own id, remapped onto the new ring', () {
      final mesh = EditMesh.cuboid();
      late OpResult result;
      edit(mesh, () {
        result = insetFaces(mesh, faceZero(), thickness: 0.1);
      });
      expect(result.selection.ids, <int>[0]);
      expect(mesh.isFaceAlive(0), isTrue);
    });

    // The plan's own worked number: a face inset by 0.1 on every side has an
    // inner boundary a further 0.1 in from each edge, so a unit square's
    // inner face has side 1 - 2*0.1 = 0.8 and area 0.8^2 = (1 - 0.2)^2.
    test('a unit square face insets to area (1 - 0.2)^2', () {
      final mesh = EditMesh.cuboid();
      edit(mesh, () => insetFaces(mesh, faceZero(), thickness: 0.1));
      expect(mesh.areaOf(0), closeTo(0.64, 1e-6));
    });

    test('the four faces around it keep their own boundary untouched', () {
      final mesh = EditMesh.cuboid();
      final around = <int>[for (var f = 1; f < mesh.faceCount; f++) f];
      final before = <int, List<Vector3>>{
        for (final f in around)
          f: <Vector3>[for (final v in mesh.verticesOf(f)) mesh.positionOf(v)],
      };

      edit(mesh, () => insetFaces(mesh, faceZero(), thickness: 0.1));

      // Mutation: move the original boundary vertices instead of leaving
      // them for the walls to share — every face around the inset one would
      // then have moved too, which is exactly what inset (unlike extrude,
      // which detaches) must never do.
      for (final f in around) {
        final now = <Vector3>[
          for (final v in mesh.verticesOf(f)) mesh.positionOf(v),
        ];
        expect(now, before[f]);
      }
    });

    test('depth pushes the inner ring along the face normal too', () {
      final mesh = EditMesh.cuboid();
      edit(
        mesh,
        () => insetFaces(mesh, faceZero(), thickness: 0.1, depth: 0.3),
      );
      mesh.validate();

      // Face 0 is the cuboid's own +Z face — its inner ring should have
      // moved from z=0.5 to z=0.8.
      for (final v in mesh.verticesOf(0)) {
        expect(mesh.positionOf(v).z, closeTo(0.8, 1e-6));
      }
    });

    test('no selection is refused rather than a silent no-op', () {
      final mesh = EditMesh.cuboid();
      late OpResult result;
      edit(mesh, () {
        result = insetFaces(
          mesh,
          Selection.empty(ElementLevel.face),
          thickness: 0.1,
        );
      });
      expect(result.reason, contains('no faces'));
    });

    test('a sharp corner ends up the same thickness from both its edges as a '
        'square corner does — the angle correction, checked as the geometric '
        'property it actually promises rather than a hand-worked position', () {
      // An isosceles triangle with a sharp ~22.6° angle at its apex A —
      // sharp enough that an uncorrected inset (move by `thickness` along
      // the raw bisector, with no 1/cos(half-angle) scaling) lands
      // nowhere near `thickness` from either edge.
      final apex = Vector3(0, 5, 0);
      final left = Vector3(-1, 0, 0);
      final right = Vector3(1, 0, 0);
      final mesh = EditMesh.fromFaces(
        <Vector3>[apex, left, right],
        <List<int>>[
          <int>[0, 1, 2],
        ],
      );
      const thickness = 0.1;

      edit(mesh, () => insetFaces(mesh, faceZero(), thickness: thickness));
      mesh.validate();

      // The new vertex nearest the apex — by construction, the only new
      // vertex added is the inset counterpart for each of the three
      // original corners, and this is the one closest to `apex`.
      Vector3? nearestToApex;
      var bestDistance = double.infinity;
      for (var v = 0; v < mesh.vertexSlotCount; v++) {
        if (!mesh.isVertexAlive(v)) continue;
        final p = mesh.positionOf(v);
        if (p == apex) continue; // the original corner itself
        final d = (p - apex).length;
        if (d < bestDistance) {
          bestDistance = d;
          nearestToApex = p;
        }
      }
      expect(nearestToApex, isNotNull);

      // Perpendicular distance from a point to the (infinite) line through
      // `from` in direction `dir` (unit length).
      double perpendicularDistance(Vector3 point, Vector3 from, Vector3 dir) {
        final toPoint = point - from;
        final along = toPoint.dot(dir);
        final closest = from + dir.scaled(along);
        return (point - closest).length;
      }

      final toLeft = (left - apex).normalized();
      final toRight = (right - apex).normalized();

      // Mutation: drop the `/ cosHalfAngle` correction in `_insetPositions`
      // — at a ~22.6° corner the uncorrected offset lands roughly 2.6x too
      // close to the apex along both edges, which these two assertions
      // both catch on their own.
      expect(
        perpendicularDistance(nearestToApex!, apex, toLeft),
        closeTo(thickness, 1e-6),
      );
      expect(
        perpendicularDistance(nearestToApex, apex, toRight),
        closeTo(thickness, 1e-6),
      );
    });
  });
}
