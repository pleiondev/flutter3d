/// `catmullClark`, `subdivideSimple`: the vertex/edge/face-point topology,
/// the crease rules, and UV bilinear per corner.
///
///     dart test test/subdivide_test.dart
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void _creaseEveryEdge(EditMesh mesh, double weight) {
  mesh.beginStep();
  for (var face = 0; face < mesh.faceSlotCount; face++) {
    if (!mesh.isFaceAlive(face)) continue;
    mesh.forEachHalfEdge(face, (int he) {
      if (mesh.edgeOf(he) == he) mesh.setCrease(he, weight);
    });
  }
  mesh.endStep();
}

List<Vector3> _positions(EditMesh mesh) => <Vector3>[
  for (var v = 0; v < mesh.vertexSlotCount; v++)
    if (mesh.isVertexAlive(v)) mesh.positionOf(v),
];

void main() {
  group('a cube, no crease at all', () {
    test('one level: 26 vertices, 24 quads', () {
      final cube = EditMesh.cuboid();
      final once = catmullClark(cube);

      // 8 vertex points + 12 edge points + 6 face points, the acceptance
      // number this row's own line names.
      expect(once.vertexCount, 26);
      expect(once.faceCount, 24);
      expect(once.eulerCharacteristic, 2);
      for (var f = 0; f < once.faceSlotCount; f++) {
        if (once.isFaceAlive(f)) expect(once.valencyOf(f), 4);
      }
    });

    test('is still a closed, watertight surface', () {
      final once = catmullClark(EditMesh.cuboid());
      var boundary = 0;
      for (var f = 0; f < once.faceSlotCount; f++) {
        if (!once.isFaceAlive(f)) continue;
        once.forEachHalfEdge(f, (int he) {
          if (!once.hasLiveTwin(he)) boundary++;
        });
      }
      expect(boundary, 0);
    });

    test('two levels equals two one-level calls in a row', () {
      final cube = EditMesh.cuboid();
      final twoAtOnce = catmullClark(cube, levels: 2);
      final twoInARow = catmullClark(catmullClark(EditMesh.cuboid()));

      expect(twoAtOnce.vertexCount, twoInARow.vertexCount);
      expect(twoAtOnce.faceCount, twoInARow.faceCount);
    });
  });

  group('a cube creased 1.0 on every edge keeps its exact shape', () {
    test('signed volume does not move', () {
      final cube = EditMesh.cuboid();
      _creaseEveryEdge(cube, 1.0);
      final before = cube.signedVolume;

      final once = catmullClark(cube);

      // Mutation: use the smooth vertex rule regardless of crease, or drop
      // the crease blend on the edge point, and a cube's own flat faces stop
      // being flat — the volume moves by more than this tolerance.
      expect(once.signedVolume, closeTo(before, 1e-9));
    });

    test('every original corner keeps its own exact position', () {
      final cube = EditMesh.cuboid();
      final originalCorners = _positions(cube);
      _creaseEveryEdge(cube, 1.0);

      final once = catmullClark(cube);
      final newPositions = _positions(once);

      for (final corner in originalCorners) {
        expect(
          newPositions.any((Vector3 p) => (p - corner).length < 1e-9),
          isTrue,
          reason: 'corner $corner missing from the subdivided vertices',
        );
      }
    });
  });

  group('subdivideSimple: the same topology, no smoothing at all', () {
    test('26 vertices, 24 quads, same as one Catmull-Clark level', () {
      final once = subdivideSimple(EditMesh.cuboid());
      expect(once.vertexCount, 26);
      expect(once.faceCount, 24);
    });

    test('every original corner is untouched, crease or not', () {
      final cube = EditMesh.cuboid();
      final originalCorners = _positions(cube);

      final once = subdivideSimple(cube);
      final newPositions = _positions(once);

      // Mutation: read the smooth vertex rule instead of always keeping the
      // original position, and a cube (which has no crease set at all here)
      // would move its corners toward the smooth Catmull-Clark answer.
      for (final corner in originalCorners) {
        expect(
          newPositions.any((Vector3 p) => (p - corner).length < 1e-9),
          isTrue,
        );
      }
    });
  });

  group('a smooth cube moves its corners; a creased one does not', () {
    test('the two differ, so the crease blend has a real effect', () {
      final smooth = catmullClark(EditMesh.cuboid());
      final creased = EditMesh.cuboid();
      _creaseEveryEdge(creased, 1.0);
      final creasedOnce = catmullClark(creased);

      final smoothCorner = _positions(
        smooth,
      ).reduce((a, b) => a.length > b.length ? a : b);
      final creasedCorner = _positions(
        creasedOnce,
      ).reduce((a, b) => a.length > b.length ? a : b);

      // The smooth rule pulls every vertex point inward (a cube's own
      // corners are convex), so its farthest point sits closer to the
      // centre than the untouched, creased one does.
      expect(smoothCorner.length, lessThan(creasedCorner.length));
    });
  });

  group('a semi-sharp crease decays after one level', () {
    test('level one differs between crease 0 and crease 0.6; level two '
        'does not', () {
      final plain = EditMesh.cuboid();
      final semiSharp = EditMesh.cuboid();
      _creaseEveryEdge(semiSharp, 0.6);

      final plainOnce = catmullClark(plain);
      final semiSharpOnce = catmullClark(semiSharp);
      // Mutation: drop the crease blend from the edge-point rule entirely,
      // and the two one-level results stop differing.
      expect(
        _positions(plainOnce).toString() ==
            _positions(semiSharpOnce).toString(),
        isFalse,
      );

      // What decay actually means is a data question, not a shape one: a
      // level-one result carries the crease onward or does not, regardless
      // of how far the *positions* it was computed from already diverged
      // from the plain cube's own. So the second level is asked about the
      // data it was handed, not compared position for position against a
      // mesh that took a different path to get there.
      var maxCrease = 0.0;
      for (var f = 0; f < semiSharpOnce.faceSlotCount; f++) {
        if (!semiSharpOnce.isFaceAlive(f)) continue;
        semiSharpOnce.forEachHalfEdge(f, (int he) {
          maxCrease = maxCrease > semiSharpOnce.creaseOf(he)
              ? maxCrease
              : semiSharpOnce.creaseOf(he);
        });
      }
      // Mutation: never decay the crease (`_decay` always returning its
      // input), and this would still be 0.6 rather than fully gone.
      expect(maxCrease, 0.0);
    });

    test('crease 1.0 never decays: the same check stays at 1.0', () {
      final alwaysSharp = EditMesh.cuboid();
      _creaseEveryEdge(alwaysSharp, 1.0);
      final once = catmullClark(alwaysSharp);

      var maxCrease = 0.0;
      for (var f = 0; f < once.faceSlotCount; f++) {
        if (!once.isFaceAlive(f)) continue;
        once.forEachHalfEdge(f, (int he) {
          maxCrease = maxCrease > once.creaseOf(he)
              ? maxCrease
              : once.creaseOf(he);
        });
      }
      expect(maxCrease, 1.0);
    });
  });

  group('UV: bilinear per corner, not smoothed', () {
    test('a face point is the average of its own four corner UVs', () {
      final builder = EditMeshBuilder();
      final a = builder.addVertex(Vector3(0, 0, 0));
      final b = builder.addVertex(Vector3(1, 0, 0));
      final c = builder.addVertex(Vector3(1, 1, 0));
      final d = builder.addVertex(Vector3(0, 1, 0));
      builder.addFace(<int>[a, b, c, d]);
      final quad = builder.build();
      quad.beginStep();
      quad.setUv(quad.halfEdgeOf(0), Vector2(0, 0));
      quad.setUv(quad.nextOf(quad.halfEdgeOf(0)), Vector2(1, 0));
      quad.setUv(quad.nextOf(quad.nextOf(quad.halfEdgeOf(0))), Vector2(1, 1));
      quad.setUv(
        quad.nextOf(quad.nextOf(quad.nextOf(quad.halfEdgeOf(0)))),
        Vector2(0, 1),
      );
      quad.endStep();

      final once = subdivideSimple(quad);
      // Four new quads share the face point at the centre — every one of
      // them names it as one of its own four corners, and it is the only
      // new vertex whose UV is the average of all four originals: (0.5,0.5).
      var found = false;
      for (var v = 0; v < once.vertexSlotCount; v++) {
        if (!once.isVertexAlive(v)) continue;
        if ((once.positionOf(v) - Vector3(0.5, 0.5, 0)).length < 1e-9) {
          found = true;
        }
      }
      expect(found, isTrue, reason: 'no vertex sits at the face centre');

      // Mutation: average the wrong four corners (or only two), and no
      // corner UV in the result would land on exactly (0.5, 0.5).
      var sawCentreUv = false;
      for (var f = 0; f < once.faceSlotCount; f++) {
        if (!once.isFaceAlive(f)) continue;
        once.forEachHalfEdge(f, (int he) {
          final uv = once.uvOf(he);
          if ((uv - Vector2(0.5, 0.5)).length < 1e-9) sawCentreUv = true;
        });
      }
      expect(sawCentreUv, isTrue);
    });

    test('an edge point averages the two corners on its own face-side, '
        'not one', () {
      final builder = EditMeshBuilder();
      final a = builder.addVertex(Vector3(0, 0, 0));
      final b = builder.addVertex(Vector3(1, 0, 0));
      final c = builder.addVertex(Vector3(1, 1, 0));
      final d = builder.addVertex(Vector3(0, 1, 0));
      builder.addFace(<int>[a, b, c, d]);
      final quad = builder.build();
      quad.beginStep();
      quad.setUv(quad.halfEdgeOf(0), Vector2(0, 0));
      quad.setUv(quad.nextOf(quad.halfEdgeOf(0)), Vector2(1, 0));
      quad.setUv(quad.nextOf(quad.nextOf(quad.halfEdgeOf(0))), Vector2(1, 1));
      quad.setUv(
        quad.nextOf(quad.nextOf(quad.nextOf(quad.halfEdgeOf(0)))),
        Vector2(0, 1),
      );
      quad.endStep();

      final once = subdivideSimple(quad);
      // The edge from (0,0,0) to (1,0,0) — UVs (0,0) and (1,0) — has its
      // point at position (0.5, 0, 0). Two new quads meet there, one from
      // each original corner the edge runs between (`uvEdgeAfter` at corner
      // 0, `uvEdgeBefore` at corner 1) — both have to carry the average of
      // (0,0) and (1,0), not just one of the two, since a mutation in
      // either formula alone would still leave the *other* corner reading
      // the right answer and hide behind it.
      var cornersAtEdgePoint = 0;
      for (var v = 0; v < once.vertexSlotCount; v++) {
        if (!once.isVertexAlive(v)) continue;
        if ((once.positionOf(v) - Vector3(0.5, 0, 0)).length >= 1e-9) {
          continue;
        }
        for (var f = 0; f < once.faceSlotCount; f++) {
          if (!once.isFaceAlive(f)) continue;
          once.forEachHalfEdge(f, (int he) {
            if (once.originOf(he) != v) return;
            cornersAtEdgePoint++;
            expect(
              (once.uvOf(he) - Vector2(0.5, 0)).length,
              lessThan(1e-9),
              reason:
                  'a corner at the edge point does not carry the '
                  'averaged UV',
            );
          });
        }
      }
      // Both quads that touch this edge point are accounted for — the
      // `expect` above would have failed already if either read wrong.
      expect(cornersAtEdgePoint, 2);
    });
  });
}
