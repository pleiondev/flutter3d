/// Moving what is selected, and what the result says about it.
///
/// A transform is the operation with the sharpest promise: positions change and
/// nothing else does. So the tests measure both halves — the geometry by volume
/// and by position, and the promise by reading the whole topology before and
/// after and asking whether one number of it moved.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// Runs [body] as one step of history.
void edit(EditMesh mesh, void Function() body) {
  mesh.beginStep();
  body();
  mesh.endStep();
}

/// Every link in the mesh, written down so it can be compared with itself.
List<int> topologyOf(EditMesh mesh) => <int>[
  for (var half = 0; half < mesh.halfEdgeSlotCount; half++) ...<int>[
    mesh.originOf(half),
    mesh.nextOf(half),
    mesh.twinOf(half),
    mesh.faceOf(half),
  ],
  for (var face = 0; face < mesh.faceSlotCount; face++) mesh.halfEdgeOf(face),
  for (var vertex = 0; vertex < mesh.vertexSlotCount; vertex++)
    mesh.outgoingOf(vertex),
];

Selection everything(EditMesh mesh) => Selection.of(ElementLevel.vertex, <int>[
  for (var v = 0; v < mesh.vertexSlotCount; v++)
    if (mesh.isVertexAlive(v)) v,
]);

void main() {
  group('what a transform promises', () {
    test('the topology is shared whole, not rebuilt', () {
      final mesh = EditMesh.cuboid();
      final before = topologyOf(mesh);

      late OpResult result;
      edit(mesh, () {
        result = translateSelection(
          mesh,
          everything(mesh),
          by: Vector3(5, 0, 0),
        );
      });

      expect(result.ok, isTrue);
      // Mutation: report `topologyChanged: true` and a viewport rebuilds the
      // layout plan on every frame of a drag — sixty-eight milliseconds where
      // one microsecond would do.
      expect(result.topologyChanged, isFalse);
      expect(topologyOf(mesh), before);
      mesh.validate();
    });

    test('the result names the rows a viewport has to refill', () {
      final mesh = EditMesh.cuboid();
      final two = Selection.of(ElementLevel.vertex, <int>[1, 3]);

      late OpResult result;
      edit(mesh, () {
        result = translateSelection(mesh, two, by: Vector3(0, 1, 0));
      });

      expect(result.movedVertices, <int>[1, 3]);

      // And they are exactly the rows a plan refills, which is the whole point
      // of handing them over.
      final plan = MeshLayoutPlan()..build(mesh);
      final buffer = Float32List(plan.vertexCount * plan.floatsPerVertex);
      expect(plan.fillVerticesOf(mesh, buffer, result.movedVertices), 6);
    });

    test('a face selection moves the vertices under it', () {
      final mesh = EditMesh.cuboid();
      final face = Selection.of(ElementLevel.face, <int>[0]);

      late OpResult result;
      edit(mesh, () {
        result = translateSelection(mesh, face, by: Vector3(0, 0, 1));
      });

      // Four corners, and the selection it hands back is still the face — a
      // person who selected a face has a face selected afterwards.
      expect(result.movedVertices, hasLength(4));
      expect(result.selection.level, ElementLevel.face);
      expect(mesh.positionOf(4).z, closeTo(1.5, 1e-6));
      expect(mesh.positionOf(0).z, closeTo(-0.5, 1e-6));
    });

    test('nothing selected is a refusal with something to say', () {
      final mesh = EditMesh.cuboid();

      late OpResult result;
      edit(mesh, () {
        result = translateSelection(
          mesh,
          Selection.empty(ElementLevel.vertex),
          by: Vector3(1, 0, 0),
        );
      });

      // Mutation: return `OpResult.done` with nothing moved, and a person
      // pressing the key with an empty selection sees no message and no change
      // and cannot tell which of the two happened.
      expect(result.ok, isFalse);
      expect(result.reason, contains('selected'));
      expect(mesh.positionOf(0).x, closeTo(-0.5, 1e-6));
    });
  });

  group('the geometry', () {
    test('a scale of two is eight times the volume', () {
      final mesh = EditMesh.cuboid();
      expect(mesh.signedVolume, closeTo(1, 1e-5));

      edit(mesh, () {
        scaleSelection(mesh, everything(mesh), by: Vector3(2, 2, 2));
      });

      expect(mesh.signedVolume, closeTo(8, 1e-4));
      mesh.validate();
    });

    test('a scale happens about the middle of what is selected', () {
      final mesh = EditMesh.cuboid();
      // The +Z face on its own: scaling it about the whole cube's centre would
      // move it in z, and about its own middle it stays where it is.
      final face = Selection.of(ElementLevel.face, <int>[0]);

      edit(mesh, () => scaleSelection(mesh, face, by: Vector3(2, 2, 2)));

      // Mutation: take the pivot from the mesh rather than the selection, and
      // the face lifts to z = 1 — a person scaling a face watches it slide away
      // from the model.
      expect(mesh.positionOf(4).z, closeTo(0.5, 1e-6));
      expect(mesh.positionOf(4).x, closeTo(-1, 1e-6));
      expect(mesh.positionOf(0).z, closeTo(-0.5, 1e-6));
    });

    test('a rotation about a pivot leaves the pivot where it is', () {
      final mesh = EditMesh.cuboid();
      final quarterTurn = Quaternion.axisAngle(Vector3(0, 0, 1), math.pi / 2);

      edit(mesh, () {
        rotateSelection(
          mesh,
          everything(mesh),
          by: quarterTurn,
          pivot: Vector3(0.5, 0.5, 0),
        );
      });

      // The corner standing on the pivot in x and y does not move in either.
      final at = mesh.positionOf(2);
      expect(at.x, closeTo(0.5, 1e-6));
      expect(at.y, closeTo(0.5, 1e-6));
      // Mutation: apply the rotation without moving to the pivot and back, and
      // the box turns about the origin instead — every rotation with a gizmo
      // somewhere other than the centre throws the model across the viewport.
      expect(mesh.positionOf(0).x, closeTo(1.5, 1e-6));
      expect(mesh.signedVolume, closeTo(1, 1e-4));
    });

    test('a rotation of a whole box keeps its shape', () {
      final mesh = EditMesh.cuboid();
      final before = mesh.signedVolume;

      edit(mesh, () {
        rotateSelection(
          mesh,
          everything(mesh),
          by: Quaternion.axisAngle(Vector3(1, 1, 1)..normalize(), 0.7),
        );
      });

      expect(mesh.signedVolume, closeTo(before, 1e-5));
      mesh.validate();
    });
  });

  group('history', () {
    test('an undo puts the positions back exactly as they were', () {
      final mesh = EditMesh.cuboid();
      final before = Float32List.fromList(mesh.positions);

      edit(mesh, () {
        rotateSelection(
          mesh,
          everything(mesh),
          by: Quaternion.axisAngle(Vector3(0, 1, 0), 0.37),
        );
      });
      expect(mesh.positions, isNot(before));

      expect(mesh.undo(), isTrue);

      // Every float, not every float to a tolerance: the journal holds what was
      // there rather than an inverse transform, which is the difference between
      // an undo and a second edit that nearly cancels the first.
      expect(mesh.positions, before);
    });

    test('a drag of forty frames is one step', () {
      final mesh = EditMesh.cuboid();
      final before = Float32List.fromList(mesh.positions);

      edit(mesh, () {
        for (var frame = 0; frame < 40; frame++) {
          translateSelection(mesh, everything(mesh), by: Vector3(0.1, 0, 0));
        }
      });

      expect(mesh.positionOf(0).x, closeTo(3.5, 1e-5));
      expect(mesh.undoDepth, 1);
      expect(mesh.undo(), isTrue);
      expect(mesh.positions, before);
    });
  });

  group('the middle of a selection', () {
    test('it is the median of the vertices, not the box around them', () {
      // Three points along a line with two of them at one end: the median sits
      // where they are, the middle of the bounding box sits half way.
      final mesh = EditMesh.fromFaces(
        <Vector3>[Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(6, 0, 0)],
        <List<int>>[
          <int>[0, 1, 2],
        ],
      );

      // Mutation: take the centre of the bounding box and this is three.
      expect(medianOf(mesh, everything(mesh)).x, closeTo(2, 1e-6));
    });

    test('an empty selection has no middle rather than a wrong one', () {
      final mesh = EditMesh.cuboid();

      expect(
        medianOf(mesh, Selection.empty(ElementLevel.face)),
        Vector3.zero(),
      );
    });
  });
}
