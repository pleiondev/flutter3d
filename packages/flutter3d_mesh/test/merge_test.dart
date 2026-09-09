/// Taking edges and vertices out, and welding vertices together.
///
/// The two shapes that decide it. A triangulated box is what an import hands
/// over, and dissolving the diagonal of every pair of coplanar triangles has to
/// give back the six quads it was before somebody's exporter cut them up —
/// that is the operation's whole reason for existing. Two boxes glued face to
/// face are the other: welding them has to leave one solid rather than two with
/// a wall down the middle.
library;

import 'package:flutter3d_geometry/flutter3d_geometry.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// The eight corners of a box, in the order the six quads below name them.
List<Vector3> boxPoints(Vector3 low, Vector3 high) => <Vector3>[
  Vector3(low.x, low.y, low.z),
  Vector3(high.x, low.y, low.z),
  Vector3(high.x, high.y, low.z),
  Vector3(low.x, high.y, low.z),
  Vector3(low.x, low.y, high.z),
  Vector3(high.x, low.y, high.z),
  Vector3(high.x, high.y, high.z),
  Vector3(low.x, high.y, high.z),
];

List<List<int>> boxFaces(int base) => <List<int>>[
  <int>[base + 4, base + 5, base + 6, base + 7],
  <int>[base + 1, base + 0, base + 3, base + 2],
  <int>[base + 5, base + 1, base + 2, base + 6],
  <int>[base + 0, base + 4, base + 7, base + 3],
  <int>[base + 3, base + 7, base + 6, base + 2],
  <int>[base + 0, base + 1, base + 5, base + 4],
];

/// Two boxes standing side by side, touching along one face, each with its own
/// copies of the four points where they meet.
EditMesh gluedBoxes() => EditMesh.fromFaces(
  <Vector3>[
    ...boxPoints(Vector3.zero(), Vector3(1, 1, 1)),
    ...boxPoints(Vector3(1, 0, 0), Vector3(2, 1, 1)),
  ],
  <List<int>>[...boxFaces(0), ...boxFaces(8)],
);

/// A sheet of [n] by [n] quads.
EditMesh grid(int n) {
  final points = <Vector3>[
    for (var y = 0; y <= n; y++)
      for (var x = 0; x <= n; x++) Vector3(x.toDouble(), y.toDouble(), 0),
  ];
  int at(int x, int y) => y * (n + 1) + x;
  return EditMesh.fromFaces(points, <List<int>>[
    for (var y = 0; y < n; y++)
      for (var x = 0; x < n; x++)
        <int>[at(x, y), at(x + 1, y), at(x + 1, y + 1), at(x, y + 1)],
  ]);
}

/// Runs [body] as one step of history.
void edit(EditMesh mesh, void Function() body) {
  mesh.beginStep();
  body();
  mesh.endStep();
}

/// Dissolves every edge whose two faces lie in the same plane, and says how
/// many went. This is what "make the quads I had before triangulation" is.
int dissolveFlatEdges(EditMesh mesh) {
  var gone = 0;
  final here = Vector3.zero();
  final there = Vector3.zero();
  edit(mesh, () {
    for (var half = 0; half < mesh.halfEdgeSlotCount; half++) {
      if (!mesh.hasLiveTwin(half) || mesh.edgeOf(half) != half) continue;
      final face = mesh.faceOf(half);
      final other = mesh.faceOf(mesh.twinOf(half));
      if (!mesh.isFaceAlive(face) || !mesh.isFaceAlive(other)) continue;
      mesh.normalOf(face, here);
      mesh.normalOf(other, there);
      if (here.dot(there) > 0.9999 && mesh.dissolveEdge(half)) gone++;
    }
  });
  return gone;
}

void main() {
  group('dissolving an edge', () {
    test('two faces of a cube become one six-sided face', () {
      final mesh = EditMesh.cuboid();
      final between = mesh.halfEdgeOf(0);

      edit(mesh, () => expect(mesh.dissolveEdge(between), isTrue));

      expect(mesh.faceCount, 5);
      expect(mesh.vertexCount, 8);
      expect(mesh.edgeCount, 11);
      expect(mesh.eulerCharacteristic, 2);
      mesh.validate();

      final merged = mesh.faceOf(mesh.halfEdgeOf(0));
      expect(mesh.valencyOf(merged), 6);

      // Mutation: leave `outgoing` pointing at the half-edge that was removed.
      // `validate` does not catch this one — it only asks that the half-edge
      // still starts at the vertex, and the removed one does — so it is asked
      // here directly: a vertex whose way into the mesh is a link on no loop
      // is a vertex nothing can walk a fan from.
      for (var vertex = 0; vertex < mesh.vertexSlotCount; vertex++) {
        final out = mesh.outgoingOf(vertex);
        expect(mesh.faceOf(out), isNot(EditMesh.none));
        expect(mesh.isFaceAlive(mesh.faceOf(out)), isTrue);
      }
    });

    test('a triangulated box goes back to being six quads', () {
      final (mesh, _) = importMeshData(CuboidShape().build());
      expect(mesh.faceCount, 12);

      expect(dissolveFlatEdges(mesh), 6);

      expect(mesh.faceCount, 6);
      expect(mesh.vertexCount, 8);
      expect(mesh.eulerCharacteristic, 2);
      for (var face = 0; face < mesh.faceSlotCount; face++) {
        if (mesh.isFaceAlive(face)) expect(mesh.valencyOf(face), 4);
      }
      mesh.validate();
      expect(mesh.signedVolume, closeTo(1, 1e-5));
    });

    test('an edge with nothing behind it is refused', () {
      final mesh = grid(1);
      // A lone quad: every one of its edges is on the boundary.
      edit(mesh, () => expect(mesh.dissolveEdge(mesh.halfEdgeOf(0)), isFalse));

      // Mutation: dissolve it anyway and the face it belonged to is left with
      // a loop of three links, two of which no longer point at each other.
      expect(mesh.faceCount, 1);
      mesh.validate();
    });

    test('two faces that meet more than once are refused', () {
      // A flat bag: two triangles on the same three points, wound against each
      // other, so all three of their edges are shared.
      final mesh = EditMesh.fromFaces(
        <Vector3>[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)],
        <List<int>>[
          <int>[0, 1, 2],
          <int>[0, 2, 1],
        ],
      );

      // Mutation: drop the count of how often the two faces meet, and merging
      // them leaves a loop that runs down one side of the bag and back up the
      // other — three corners naming two points.
      edit(mesh, () => expect(mesh.dissolveEdge(mesh.halfEdgeOf(0)), isFalse));
      expect(mesh.faceCount, 2);
      mesh.validate();
    });

    test('a dissolve is one step of history', () {
      final mesh = EditMesh.cuboid();
      edit(mesh, () => mesh.dissolveEdge(mesh.halfEdgeOf(0)));
      expect(mesh.faceCount, 5);

      expect(mesh.undo(), isTrue);

      // `validate` first, because it is the check with a guard on it.
      // Mutation: rewire `next` without recording it, and the undo restores
      // the tombstone while leaving the merged loop in place — a face marked
      // live whose loop runs through six links and never comes back.
      mesh.validate();
      expect(mesh.faceCount, 6);
      expect(mesh.valencyOf(mesh.faceOf(mesh.halfEdgeOf(0))), 4);

      expect(mesh.redo(), isTrue);
      expect(mesh.faceCount, 5);
      mesh.validate();
    });
  });

  group('dissolving a vertex', () {
    test('four quads round a point become one eight-sided face', () {
      final mesh = grid(2);

      edit(mesh, () => expect(mesh.dissolveVertex(4), isTrue));

      expect(mesh.faceCount, 1);
      expect(mesh.vertexCount, 8);
      expect(mesh.valencyOf(mesh.faceOf(mesh.halfEdgeOf(0))), 8);
      // A disc, not a sphere: eight points, eight edges, one face.
      expect(mesh.eulerCharacteristic, 1);
      mesh.validate();
    });

    test('a corner of a cube leaves a six-sided face', () {
      final mesh = EditMesh.cuboid();

      edit(mesh, () => expect(mesh.dissolveVertex(0), isTrue));

      expect(mesh.vertexCount, 7);
      expect(mesh.faceCount, 4);
      expect(mesh.eulerCharacteristic, 2);
      mesh.validate();
    });

    test(
      'a vertex on a boundary is refused, because its fan is not a ring',
      () {
        final mesh = grid(2);

        // Mutation: walk the fan without checking that every step has a live
        // face behind it, and a corner of the sheet reads a twin that is not
        // there. There is no polygon around a vertex on an edge of the world.
        edit(mesh, () => expect(mesh.dissolveVertex(0), isFalse));
        expect(mesh.faceCount, 4);
        mesh.validate();
      },
    );

    test('a dissolve of a vertex comes back on undo', () {
      final mesh = grid(2);
      edit(mesh, () => mesh.dissolveVertex(4));
      expect(mesh.faceCount, 1);

      expect(mesh.undo(), isTrue);
      expect(mesh.faceCount, 4);
      expect(mesh.vertexCount, 9);
      mesh.validate();
    });
  });

  group('merging by distance', () {
    test('two boxes glued face to face become one solid', () {
      final mesh = gluedBoxes();
      expect(mesh.vertexCount, 16);
      expect(mesh.faceCount, 12);

      final (merged, report) = mergeByDistance(mesh);

      // Twelve points, ten faces: the wall between them is gone, and so are the
      // four pairs of coincident corners. Mutation: keep the coincident faces
      // and this is twelve faces with a partition nothing can see, χ of 4
      // rather than 2, and twice the surface area to export.
      expect(merged.vertexCount, 12);
      expect(merged.faceCount, 10);
      expect(merged.eulerCharacteristic, 2);
      expect(merged.signedVolume, closeTo(2, 1e-5));
      merged.validate();

      expect(report.merged, 4);
      expect(report.droppedCoincident, 2);
      expect(report.worthReporting, isTrue);
    });

    test('a mesh with nothing to weld comes back unchanged', () {
      final mesh = EditMesh.cuboid();

      final (merged, report) = mergeByDistance(mesh);

      expect(merged.vertexCount, 8);
      expect(merged.faceCount, 6);
      expect(report.worthReporting, isFalse);
      expect(report.merged, 0);
      merged.validate();
    });

    test('a third face on a welded edge is detached and counted', () {
      // Three flaps standing on the same edge, each with its own copies of the
      // two points at the hinge.
      final points = <Vector3>[];
      final faces = <List<int>>[];
      for (final away in <Vector3>[
        Vector3(0, 1, 0),
        Vector3(0, 0, 1),
        Vector3(0, -1, 0),
      ]) {
        final base = points.length;
        points
          ..add(Vector3(0, 0, 0))
          ..add(Vector3(1, 0, 0))
          ..add(Vector3(1, 0, 0) + away)
          ..add(Vector3(0, 0, 0) + away);
        faces.add(<int>[base, base + 1, base + 2, base + 3]);
      }
      final mesh = EditMesh.fromFaces(points, faces);

      final (merged, report) = mergeByDistance(mesh);

      // Mutation: hand the third flap to the builder without splitting and it
      // throws — "the edge is used twice the same way round" — so a merge
      // somebody asked for would lose the model instead of reporting.
      expect(report.splitNonManifold, greaterThanOrEqualTo(1));
      expect(merged.faceCount, 3);
      merged.validate();
    });

    test('only the vertices named are candidates', () {
      final mesh = gluedBoxes();
      // One of the four pairs standing in the same place along the wall.
      final one = Selection.of(ElementLevel.vertex, <int>[1, 8]);

      final (merged, report) = mergeByDistance(mesh, within: one);

      // Mutation: ignore `within` and this welds all four pairs and takes the
      // wall out with them — a person closing one seam would find the rest of
      // the model closed too.
      expect(report.merged, 1);
      expect(merged.vertexCount, 15);
      expect(merged.faceCount, 12, reason: 'the wall still has two sides');
      merged.validate();
    });

    test('vertices that are named but not in the same place stay apart', () {
      final mesh = gluedBoxes();
      final apart = Selection.of(ElementLevel.vertex, <int>[8, 9]);

      final (merged, report) = mergeByDistance(mesh, within: apart);

      expect(report.merged, 0);
      expect(merged.vertexCount, 16);
    });

    test('what the merge carried across', () {
      final mesh = gluedBoxes();
      edit(mesh, () {
        mesh.setMaterialSlot(0, 3);
        mesh.forEachHalfEdge(0, (int half) {
          mesh.setUv(half, Vector2(0.25, 0.75));
        });
      });

      final (merged, report) = mergeByDistance(mesh);
      final face = report.remap.faces[0];

      // Mutation: build the mesh and stop, and every material assignment, UV
      // and sharp edge in the document is gone the first time somebody welds
      // two vertices.
      expect(face, isNot(EditMesh.none));
      expect(merged.materialSlotOf(face), 3);
      merged.forEachHalfEdge(face, (int half) {
        expect(merged.uvOf(half).x, closeTo(0.25, 1e-6));
      });
    });

    test('the remap says where every vertex went', () {
      final mesh = gluedBoxes();

      final (merged, report) = mergeByDistance(mesh);

      // The two boxes' copies of a shared corner land on the same new vertex,
      // which is what makes them one solid.
      // Box A's (1, 0, 0) is vertex 1; box B's own copy of it is vertex 8.
      expect(report.remap.vertices[1], report.remap.vertices[8]);
      expect(report.remap.vertices[0], isNot(report.remap.vertices[8]));
      for (var vertex = 0; vertex < mesh.vertexSlotCount; vertex++) {
        expect(report.remap.vertices[vertex], lessThan(merged.vertexCount));
      }
    });
  });

  group('merging at a point', () {
    test('the named vertices become one, where they were told', () {
      final mesh = grid(2);
      final corner = Selection.of(ElementLevel.vertex, <int>[0, 1]);

      final (merged, report) = mergeAt(mesh, corner, Vector3(9, 9, 0));

      expect(merged.vertexCount, 8);
      expect(report.merged, 1);
      final landed = report.remap.vertices[0];
      expect(report.remap.vertices[1], landed);
      expect(merged.positionOf(landed).x, closeTo(9, 1e-6));

      // The quad those two were adjacent corners of is now a triangle, and the
      // one that only touched one of them is unchanged.
      expect(merged.faceCount, 4);
      merged.validate();
    });

    test('a face that collapses onto a line is dropped, not kept flat', () {
      // A single triangle, two of whose corners are told to become one.
      final mesh = EditMesh.fromFaces(
        <Vector3>[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)],
        <List<int>>[
          <int>[0, 1, 2],
        ],
      );

      final (merged, report) = mergeAt(
        mesh,
        Selection.of(ElementLevel.vertex, <int>[0, 1]),
        Vector3.zero(),
      );

      // Mutation: keep a loop of two corners and the builder refuses it — "a
      // face of 2 vertices" — so a merge a person asked for throws instead of
      // reporting what it had to throw away.
      expect(report.droppedDegenerate, 1);
      expect(merged.faceCount, 0);
    });

    test('merging is not an edit with a history', () {
      final mesh = grid(2);
      // With a layer on it, so the copying of attributes writes a step: on a
      // mesh carrying nothing there would be no journal to clear and no way to
      // tell whether it was cleared.
      edit(mesh, () => mesh.setMaterialSlot(0, 1));

      final (merged, _) = mergeAt(
        mesh,
        Selection.of(ElementLevel.vertex, <int>[0, 1]),
        Vector3.zero(),
      );

      // A rebuild renumbers everything, so a journal from before it would
      // replay against the wrong elements — the same rule `compact` follows.
      expect(merged.undoDepth, 0);
      expect(merged.undo(), isFalse);
      // And the mesh it came from is untouched.
      expect(mesh.vertexCount, 9);
    });
  });
}
