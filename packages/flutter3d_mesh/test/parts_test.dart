/// Taking a mesh apart and putting copies of pieces back.
///
/// A box is the shape that says what deleting means at each level: take a face
/// and its four corners stay, because five other faces still stand on them;
/// take a corner and the three faces on it go with it, and what is left has a
/// six-sided hole. Two boxes side by side are what separating is for.
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

/// Two boxes standing apart from each other.
EditMesh twoBoxes() {
  final one = EditMesh.cuboid();
  final points = <Vector3>[
    for (var v = 0; v < one.vertexSlotCount; v++) one.positionOf(v),
  ];
  final faces = <List<int>>[...one.faces()];
  final base = points.length;
  for (var v = 0; v < one.vertexSlotCount; v++) {
    points.add(one.positionOf(v)..add(Vector3(5, 0, 0)));
  }
  for (final face in one.faces()) {
    faces.add(<int>[for (final v in face) v + base]);
  }
  return EditMesh.fromFaces(points, faces);
}

/// How many half-edges have nothing live behind them.
int rimOf(EditMesh mesh) {
  var count = 0;
  for (var face = 0; face < mesh.faceSlotCount; face++) {
    if (!mesh.isFaceAlive(face)) continue;
    mesh.forEachHalfEdge(face, (int half) {
      if (!mesh.hasLiveTwin(half)) count++;
    });
  }
  return count;
}

void main() {
  group('deleting', () {
    test('a face of a box leaves its corners where they were', () {
      final mesh = EditMesh.cuboid();

      late OpResult result;
      edit(mesh, () {
        result = deleteSelection(
          mesh,
          Selection.of(ElementLevel.face, <int>[0]),
        );
      });

      expect(result.ok, isTrue);
      expect(mesh.faceCount, 5);
      // Mutation: take the vertices of a deleted face with it, and a box loses
      // four corners that five other faces are still standing on.
      expect(mesh.vertexCount, 8);
      expect(rimOf(mesh), 4);
      mesh.validate();
    });

    test('a corner of a box takes the three faces on it', () {
      final mesh = EditMesh.cuboid();

      edit(mesh, () {
        deleteSelection(mesh, Selection.of(ElementLevel.vertex, <int>[0]));
      });

      // Three faces meet at a corner, so three go and three stay — and what is
      // left has a six-sided hole where they were.
      expect(mesh.faceCount, 3);
      expect(mesh.vertexCount, 7);
      expect(rimOf(mesh), 6);
      mesh.validate();
    });

    test('an edge takes both faces on it', () {
      final mesh = EditMesh.cuboid();
      final edgeOne = mesh.edgeOf(mesh.halfEdgeOf(0));

      edit(mesh, () {
        deleteSelection(mesh, Selection.of(ElementLevel.edge, <int>[edgeOne]));
      });

      // Two, not four. Mutation: take every face standing on either end of the
      // edge, and the two more it reaches are ones nobody pointed at.
      expect(mesh.faceCount, 4);
      expect(mesh.vertexCount, 8);
      mesh.validate();
    });

    test('a lone quad takes its corners with it', () {
      final mesh = grid(1);

      edit(mesh, () {
        deleteSelection(mesh, Selection.of(ElementLevel.face, <int>[0]));
      });

      // Nothing else stands on them, so keeping them would leave a mesh whose
      // vertex count and bounding box describe geometry that is not there.
      expect(mesh.faceCount, 0);
      expect(mesh.vertexCount, 0);
    });

    test('what a vertex points at afterwards is on a live face', () {
      final mesh = grid(2);

      edit(mesh, () {
        deleteSelection(mesh, Selection.of(ElementLevel.face, <int>[0]));
      });

      // Mutation: skip `repairVertexLinks`, and the middle vertex still points
      // into the face that has just died — invisible until something walks the
      // fan around it, which every normal and every grown selection does.
      for (var vertex = 0; vertex < mesh.vertexSlotCount; vertex++) {
        if (!mesh.isVertexAlive(vertex)) continue;
        final out = mesh.outgoingOf(vertex);
        expect(out, isNot(EditMesh.none));
        expect(mesh.isFaceAlive(mesh.faceOf(out)), isTrue);
      }
      mesh.validate();
    });

    test('a delete comes back whole on undo', () {
      final mesh = EditMesh.cuboid();

      edit(mesh, () {
        deleteSelection(mesh, Selection.of(ElementLevel.vertex, <int>[0]));
      });
      expect(mesh.faceCount, 3);

      expect(mesh.undo(), isTrue);

      expect(mesh.faceCount, 6);
      expect(mesh.vertexCount, 8);
      expect(mesh.eulerCharacteristic, 2);
      mesh.validate();
    });

    test('nothing selected is refused with something to say', () {
      final mesh = EditMesh.cuboid();

      late OpResult result;
      edit(mesh, () {
        result = deleteSelection(mesh, Selection.empty(ElementLevel.face));
      });

      expect(result.ok, isFalse);
      expect(result.reason, contains('selected'));
      expect(mesh.faceCount, 6);
    });
  });

  group('duplicating', () {
    test('a whole box comes out as a second box in the same mesh', () {
      final mesh = EditMesh.cuboid();
      final everything = Selection.of(ElementLevel.face, <int>[
        for (var f = 0; f < mesh.faceSlotCount; f++) f,
      ]);

      late OpResult result;
      edit(mesh, () => result = duplicateSelection(mesh, everything));

      expect(mesh.vertexCount, 16);
      expect(mesh.faceCount, 12);
      // Two closed boxes: χ of 4, which is 2 apiece. Mutation: leave the copies
      // untwinned, and the second box is six loose quads — χ of 12, and every
      // edge of it a rim.
      expect(mesh.eulerCharacteristic, 4);
      expect(rimOf(mesh), 0);
      expect(mesh.signedVolume, closeTo(2, 1e-5));
      expect(result.selection.length, 6);
      mesh.validate();
    });

    test('the copy stands where the original does and moves on its own', () {
      final mesh = EditMesh.cuboid();

      late OpResult result;
      edit(mesh, () {
        result = duplicateSelection(
          mesh,
          Selection.of(ElementLevel.face, <int>[0]),
        );
      });

      expect(mesh.faceCount, 7);
      edit(mesh, () {
        translateSelection(mesh, result.selection, by: Vector3(0, 0, 3));
      });

      // The original is where it was: the copy shares nothing with it.
      expect(mesh.positionOf(4).z, closeTo(0.5, 1e-6));
      expect(mesh.positionOf(8).z, closeTo(3.5, 1e-6));
      mesh.validate();
    });

    test('what the faces carried comes with them', () {
      final mesh = EditMesh.cuboid();
      edit(mesh, () {
        mesh.setMaterialSlot(0, 3);
        mesh.forEachHalfEdge(
          0,
          (int half) => mesh.setUv(half, Vector2(0.5, 0)),
        );
      });

      late OpResult result;
      edit(mesh, () {
        result = duplicateSelection(
          mesh,
          Selection.of(ElementLevel.face, <int>[0]),
        );
      });

      final copy = result.selection.ids.single;
      // Mutation: build the copy and stop, and duplicating a face somebody
      // assigned a material and a texture to gives a blank one.
      expect(mesh.materialSlotOf(copy), 3);
      mesh.forEachHalfEdge(copy, (int half) {
        expect(mesh.uvOf(half).x, closeTo(0.5, 1e-6));
      });
    });
  });

  group('splitting off', () {
    test('the picture does not change and the sharing does', () {
      final mesh = grid(2);
      final before = mesh.signedVolume;

      late OpResult result;
      edit(mesh, () {
        result = splitSelection(
          mesh,
          Selection.of(ElementLevel.face, <int>[0]),
        );
      });

      expect(result.ok, isTrue);
      expect(mesh.faceCount, 4);
      // Three of the quad's corners were shared with its neighbours; the fourth
      // is its own already.
      expect(mesh.vertexCount, 12);
      expect(mesh.signedVolume, closeTo(before, 1e-9));
      // Eight round the outside of the sheet as before, and four more where
      // the quad let go of its two neighbours. Mutation: leave the twins
      // joined, and this is eight — the two pieces still hold each other, and
      // a vertex dragged from one takes the other with it.
      expect(rimOf(mesh), 12);
      mesh.validate();

      edit(mesh, () {
        translateSelection(mesh, result.selection, by: Vector3(0, 0, 1));
      });
      // The neighbours stayed flat, which is the whole point of the operation.
      expect(mesh.positionOf(4).z, closeTo(0, 1e-9));
    });

    test('a piece that already shares nothing is refused', () {
      final mesh = grid(1);

      late OpResult result;
      edit(mesh, () {
        result = splitSelection(
          mesh,
          Selection.of(ElementLevel.face, <int>[0]),
        );
      });

      expect(result.ok, isFalse);
      expect(result.reason, contains('share'));
    });
  });

  group('separating', () {
    test('two boxes come back as two meshes', () {
      final mesh = twoBoxes();
      expect(mesh.faceCount, 12);

      final parts = separateComponents(mesh);

      expect(parts, hasLength(2));
      for (final (part, _) in parts) {
        expect(part.vertexCount, 8);
        expect(part.faceCount, 6);
        expect(part.eulerCharacteristic, 2);
        expect(part.signedVolume, closeTo(1, 1e-5));
        part.validate();
      }
      expect(parts.first.$2.faces[0], 0);
      expect(parts.last.$2.faces[6], 0);
    });

    test('two boxes meeting at a corner are one part', () {
      // The second box's low corner is the first box's high one, so they share
      // that vertex and no edge at all.
      const order = <List<int>>[
        <int>[4, 5, 6, 7],
        <int>[1, 0, 3, 2],
        <int>[5, 1, 2, 6],
        <int>[0, 4, 7, 3],
        <int>[3, 7, 6, 2],
        <int>[0, 1, 5, 4],
      ];
      final points = <Vector3>[
        Vector3(0, 0, 0),
        Vector3(1, 0, 0),
        Vector3(1, 1, 0),
        Vector3(0, 1, 0),
        Vector3(0, 0, 1),
        Vector3(1, 0, 1),
        Vector3(1, 1, 1),
        Vector3(0, 1, 1),
        Vector3(2, 1, 1),
        Vector3(2, 2, 1),
        Vector3(1, 2, 1),
        Vector3(1, 1, 2),
        Vector3(2, 1, 2),
        Vector3(2, 2, 2),
        Vector3(1, 2, 2),
      ];
      const second = <int>[6, 8, 9, 10, 11, 12, 13, 14];
      final mesh = EditMesh.fromFaces(points, <List<int>>[
        ...order,
        for (final face in order) <int>[for (final v in face) second[v]],
      ]);
      expect(mesh.vertexCount, 15);
      expect(mesh.faceCount, 12);

      final parts = separateComponents(mesh);

      // Mutation: walk the islands through edges only, and this comes back as
      // two pieces — which is not what a person means by a loose part, and not
      // the relation `Selection.linked` uses either.
      expect(parts, hasLength(1));
      expect(parts.single.$1.faceCount, 12);
      expect(parts.single.$1.vertexCount, 15);
    });

    test('one box is one part, and the remap says nothing moved', () {
      final mesh = EditMesh.cuboid();

      final parts = separateComponents(mesh);

      expect(parts, hasLength(1));
      final (part, remap) = parts.single;
      expect(part.faceCount, 6);
      for (var vertex = 0; vertex < mesh.vertexSlotCount; vertex++) {
        expect(remap.vertices[vertex], isNot(EditMesh.none));
      }
    });

    test('a part carries what its faces did, and has no history', () {
      final mesh = twoBoxes();
      edit(mesh, () {
        mesh.setMaterialSlot(7, 5);
        mesh.forEachHalfEdge(7, (int half) => mesh.setUv(half, Vector2(1, 1)));
      });

      final parts = separateComponents(mesh);
      final (second, remap) = parts.last;
      final face = remap.faces[7];

      expect(second.materialSlotOf(face), 5);
      second.forEachHalfEdge(face, (int half) {
        expect(second.uvOf(half).y, closeTo(1, 1e-6));
      });
      // A rebuild renumbers everything, so a journal from before it would
      // replay against the wrong elements.
      expect(second.undoDepth, 0);
    });
  });
}
