/// The half-edge structure itself: what it promises about its own arrays, what
/// a tombstone means, what compaction hands back, and what an undo restores.
///
/// **The spike's tests are next door and ask a different question.**
/// `edit_mesh_test.dart` asks whether a cube is a cube and an extrusion adds
/// volume — arithmetic over the result. These ask about the representation:
/// that `outgoing` points at a half-edge which starts where it says, that a
/// deleted face stops being counted without renumbering anything, that
/// `compact` says where everything went, and that a step of edits comes back.
/// Every one of them was watched to fail, with the mutation named.
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// Two quads sharing an edge — the smallest mesh with a boundary, an interior
/// edge and a vertex of valency two, which is enough to break every invariant
/// on separately.
EditMesh twoQuads() => EditMesh.fromFaces(
  <Vector3>[
    Vector3(0, 0, 0),
    Vector3(1, 0, 0),
    Vector3(1, 1, 0),
    Vector3(0, 1, 0),
    Vector3(2, 0, 0),
    Vector3(2, 1, 0),
  ],
  <List<int>>[
    <int>[0, 1, 2, 3],
    <int>[1, 4, 5, 2],
  ],
);

void main() {
  group('what the arrays promise', () {
    test('a cube walks its loops and holds its invariants', () {
      final cube = EditMesh.cuboid();

      expect(cube.vertexCount, 8);
      expect(cube.faceCount, 6);
      expect(cube.edgeCount, 12);
      expect(cube.halfEdgeCount, 24);
      expect(cube.eulerCharacteristic, 2);
      cube.validate();

      for (var face = 0; face < cube.faceSlotCount; face++) {
        expect(cube.valencyOf(face), 4, reason: 'a cube is made of quads');
      }
    });

    test('outgoing starts where it says it does', () {
      final mesh = twoQuads();

      for (var vertex = 0; vertex < mesh.vertexSlotCount; vertex++) {
        final half = mesh.outgoingOf(vertex);
        if (half == EditMesh.none) continue;
        // Mutation: record the half-edge against the vertex it *arrives* at —
        // `_outgoing[to]` rather than `_outgoing[from]` in `addFace` — and this
        // fails, as does `validate`. Overwriting rather than keeping the first
        // one is *not* a mutation this catches, and that is worth knowing: every
        // half-edge a vertex could be given starts at that vertex, so which one
        // it holds is arbitrary and the invariant survives either way.
        expect(mesh.originOf(half), vertex);
      }
      mesh.validate();
    });

    test('two quads share one edge, and the rest are boundary', () {
      final mesh = twoQuads();

      expect(mesh.faceCount, 2);
      expect(mesh.vertexCount, 6);
      // Seven edges: six around the outside and the one down the middle.
      expect(mesh.edgeCount, 7);
      // An open surface, so the characteristic is 1 rather than 2.
      expect(mesh.eulerCharacteristic, 1);

      var paired = 0;
      mesh.forEachHalfEdge(0, (int half) {
        if (mesh.twinOf(half) != EditMesh.none) paired++;
      });
      expect(paired, 1, reason: 'exactly one edge of the first quad is shared');
    });

    test('walking a face touches each of its half-edges once', () {
      final mesh = twoQuads();
      final seen = <int>[];

      mesh.forEachHalfEdge(1, seen.add);

      expect(seen, hasLength(4));
      expect(seen.toSet(), hasLength(4));
      for (final half in seen) {
        expect(mesh.faceOf(half), 1);
      }
    });
  });

  group('tombstones', () {
    test('a deleted face stops counting and renumbers nothing', () {
      final mesh = twoQuads();
      final before = mesh.verticesOf(1);

      mesh
        ..beginStep()
        ..deleteFace(0);
      mesh.endStep();

      expect(mesh.faceCount, 1);
      expect(mesh.isFaceAlive(0), isFalse);
      // The slot is still there and face 1 is still face 1 — which is the whole
      // point: a selection, an undo record or an agent holding an id all keep
      // meaning what they meant.
      expect(mesh.faceSlotCount, 2);
      expect(mesh.verticesOf(1), before);
      mesh.validate();
    });

    test('the edge a deleted face shared becomes a boundary', () {
      final mesh = twoQuads();
      expect(mesh.edgeCount, 7);

      mesh
        ..beginStep()
        ..deleteFace(0);
      mesh.endStep();

      // Four edges left, all of them boundary: the shared one now has a live
      // face on one side only. Mutation: count a twin as paired without asking
      // whether its face is alive, and this stays 7 — every count the mesh
      // reports about itself would then be about faces that are not there.
      expect(mesh.edgeCount, 4);
      expect(mesh.faceCount, 1);
      // The two vertices only the deleted face used are still alive — removing
      // a face does not remove its corners, in this mesh or in any modeller —
      // so the characteristic is 6 − 4 + 1 rather than the 1 an isolated quad
      // would give.
      expect(mesh.vertexCount, 6);
      expect(mesh.eulerCharacteristic, 3);
    });

    test('a dead vertex is refused by validate if a live face names it', () {
      final mesh = twoQuads()
        ..beginStep()
        ..deleteVertex(0);
      mesh.endStep();

      expect(mesh.validate, throwsStateError);
    });
  });

  group('compaction', () {
    test('closes the gaps and says where everything went', () {
      final mesh = twoQuads()
        ..beginStep()
        ..deleteFace(0);
      mesh.endStep();
      // The vertices only the deleted face used are dead too — deleting them is
      // the caller's step, as it is in every modeller: a face can be removed
      // and its corners kept.
      mesh
        ..beginStep()
        ..deleteVertex(0)
        ..deleteVertex(3);
      mesh.endStep();

      final (compacted, remap) = mesh.compact();

      expect(compacted.vertexCount, 4);
      expect(compacted.faceCount, 1);
      expect(compacted.vertexSlotCount, 4, reason: 'no dead slots survive');
      expect(compacted.faceSlotCount, 1);
      compacted.validate();

      // Where the survivors went. Vertex 1 was the second of six and two before
      // it are gone, so it is now vertex 0.
      expect(remap.vertices[0], EditMesh.none);
      expect(remap.vertices[3], EditMesh.none);
      expect(remap.vertices[1], 0);
      expect(remap.faces[0], EditMesh.none);
      expect(remap.faces[1], 0);

      // And the face still names the same corners, through the map.
      final expected = <int>[
        for (final vertex in mesh.verticesOf(1)) remap.vertices[vertex],
      ];
      expect(compacted.verticesOf(0), expected);
    });

    test('a compacted mesh keeps the shape it had', () {
      final cube = EditMesh.cuboid(size: Vector3(2, 2, 2));
      final (compacted, _) = cube.compact();

      expect(compacted.signedVolume, closeTo(cube.signedVolume, 1e-6));
      expect(compacted.eulerCharacteristic, 2);
    });
  });

  group('a step of edits', () {
    test('moving vertices comes back on undo, and again on redo', () {
      final cube = EditMesh.cuboid();
      final before = cube.positionOf(0);

      cube
        ..beginStep()
        ..moveVertex(0, Vector3(5, 5, 5));
      cube.endStep();
      expect(cube.positionOf(0), Vector3(5, 5, 5));

      expect(cube.undo(), isTrue);
      expect(cube.positionOf(0), before);

      expect(cube.redo(), isTrue);
      expect(cube.positionOf(0), Vector3(5, 5, 5));
      cube.validate();
    });

    test('a deleted face comes back with its counts', () {
      final mesh = twoQuads()
        ..beginStep()
        ..deleteFace(0);
      mesh.endStep();
      expect(mesh.faceCount, 1);

      mesh.undo();

      // Mutation: leave the counts to the tombstone writes and skip `_recount`
      // after an undo, and this is 1 — the face is back in every array and the
      // mesh reports one fewer than it has.
      expect(mesh.faceCount, 2);
      expect(mesh.edgeCount, 7);
      mesh.validate();
    });

    test('a drag of forty moves is one step', () {
      final cube = EditMesh.cuboid();
      final start = cube.positionOf(0);

      cube.beginStep();
      for (var i = 1; i <= 40; i++) {
        cube.moveVertex(0, Vector3(i.toDouble(), 0, 0));
      }
      cube.endStep();

      expect(cube.undoDepth, 1);
      cube.undo();
      // The position from before the *first* of the forty writes, which is what
      // walking the step backwards buys — see `JournalledFloats`.
      expect(cube.positionOf(0), start);
    });

    test('the journal knows what it costs', () {
      final cube = EditMesh.cuboid();
      expect(cube.journalBytes, 0);

      cube
        ..beginStep()
        ..moveVertex(0, Vector3(1, 2, 3));
      cube.endStep();

      // Three floats written: three int32 indices and three float32 values.
      expect(cube.journalBytes, 24);
    });
  });
}
