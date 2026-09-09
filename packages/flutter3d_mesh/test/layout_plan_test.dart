/// The arrangement a mesh takes on the way to a GPU, and refilling it cheaply.
///
/// Two oracles. For the arrangement it is `CuboidShape`, which builds the same
/// box the engine has always drawn: a plan over an editable cube has to arrive
/// at the same twenty-four vertices with the same normals, or the modeller and
/// the engine disagree about what a cube is. For the refill it is the buffer
/// itself — the rows that changed are counted, and the promise is that they are
/// exactly the rows asked for.
library;

import 'dart:typed_data';

import 'package:flutter3d_geometry/flutter3d_geometry.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// Runs [body] as one step of history.
void edit(EditMesh mesh, void Function() body) {
  mesh.beginStep();
  body();
  mesh.endStep();
}

/// A row of [buffer] as a printable key, rounded so float32 noise does not make
/// two equal vertices look different.
String rowKey(Float32List buffer, int stride, int row, int at, int count) =>
    <String>[
      for (var i = 0; i < count; i++)
        buffer[row * stride + at + i].toStringAsFixed(4),
    ].join(',');

/// Every (position, normal) pair a drawable mesh holds.
List<String> positionsAndNormals(MeshData mesh) {
  final stride = mesh.layout.floatsPerVertex;
  final positionAt = mesh.layout.floatOffsetOf(VertexLayout.position.name);
  final normalAt = mesh.layout.floatOffsetOf(VertexLayout.normal.name);
  final keys = <String>[];
  for (var i = 0; i < mesh.vertexCount; i++) {
    final position = rowKey(mesh.vertices, stride, i, positionAt, 3);
    final normal = rowKey(mesh.vertices, stride, i, normalAt, 3);
    keys.add('$position|$normal');
  }
  return keys..sort();
}

void main() {
  group('the arrangement', () {
    test('a sharp cube is the cube the engine already draws', () {
      final mesh = EditMesh.cuboid();
      final plan = MeshLayoutPlan()..build(mesh);

      // Twenty-four and thirty-six: eight corners seen from three faces each,
      // and six quads cut in two.
      expect(plan.vertexCount, 24);
      expect(plan.triangleCount, 12);
      expect(plan.indices.length, 36);

      // Mutation: merge corners by vertex alone, ignoring the fan they are in,
      // and a cube plans eight vertices — every corner averaging three faces,
      // which is a sphere-shaped box.
      expect(
        positionsAndNormals(plan.toMeshData(mesh)),
        positionsAndNormals(CuboidShape().build()),
      );
    });

    test('every row says which corner and which vertex it came from', () {
      final mesh = EditMesh.cuboid();
      final plan = MeshLayoutPlan()..build(mesh);

      for (var row = 0; row < plan.vertexCount; row++) {
        final corner = plan.gpuVertexToCorner[row];
        expect(plan.gpuVertexToVertex[row], mesh.originOf(corner));
        expect(plan.rowOfCorner(corner), row);
      }
    });

    test('a smooth surface shares the vertices its fans agree on', () {
      final drawn = const SphereShape(
        radius: 1,
        segments: 16,
        rings: 8,
      ).build();
      final (flatMesh, _) = importMeshData(drawn);
      final (smoothMesh, _) = importMeshData(drawn);
      edit(smoothMesh, () {
        for (var face = 0; face < smoothMesh.faceSlotCount; face++) {
          if (smoothMesh.isFaceAlive(face)) {
            smoothMesh.setFaceFlag(face, FaceFlags.smooth, on: true);
          }
        }
      });

      final flat = MeshLayoutPlan()..build(flatMesh);
      final smooth = MeshLayoutPlan()..build(smoothMesh);

      // Mutation: never merge, and both numbers are the corner count — the
      // saving this whole class is for disappears, and a smooth sphere costs
      // five times the vertices it needs.
      expect(flat.vertexCount, flatMesh.halfEdgeCount);
      expect(smooth.vertexCount, lessThan(flat.vertexCount ~/ 3));
      expect(smooth.triangleCount, flat.triangleCount);
    });

    test('a seam splits a vertex the normals would have shared', () {
      // Two quads in one plane, so nothing about the shading separates them.
      final mesh = EditMesh.fromFaces(
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
      edit(mesh, () {
        for (var face = 0; face < mesh.faceSlotCount; face++) {
          mesh.setFaceFlag(face, FaceFlags.smooth, on: true);
        }
      });

      final joined = MeshLayoutPlan()..build(mesh);
      expect(joined.vertexCount, 6, reason: 'one row per corner of the sheet');

      // Now give the two faces different texture coordinates at the vertices
      // they share, which is what a seam is.
      edit(mesh, () {
        for (var face = 0; face < mesh.faceSlotCount; face++) {
          mesh.forEachHalfEdge(face, (int half) {
            mesh.setUv(half, Vector2(face.toDouble(), 0));
          });
        }
      });

      final split = MeshLayoutPlan()..build(mesh);
      // Mutation: merge on the fan alone and a seam vanishes — two faces that
      // sample different parts of a texture are handed one vertex, and one of
      // them draws with the other's coordinates.
      expect(split.vertexCount, 8);
    });

    test('two faces painted differently do not share a vertex either', () {
      final mesh = EditMesh.fromFaces(
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
      edit(mesh, () {
        for (var face = 0; face < mesh.faceSlotCount; face++) {
          mesh.setFaceFlag(face, FaceFlags.smooth, on: true);
          mesh.forEachHalfEdge(face, (int half) {
            mesh.setColour(half, Vector4(face.toDouble(), 0, 0, 1));
          });
        }
      });

      // Mutation: leave the colour out of the comparison and the two faces
      // share the vertices along their edge — the painted boundary between them
      // moves, because one of the two colours simply wins.
      expect((MeshLayoutPlan()..build(mesh)).vertexCount, 8);
    });

    test('a triangle knows the face it was cut from', () {
      final mesh = EditMesh.fromFaces(
        <Vector3>[
          Vector3(0, 0, 0),
          Vector3(2, 0, 0),
          Vector3(2, 1, 0),
          Vector3(1, 1, 0),
          Vector3(1, 2, 0),
          Vector3(0, 2, 0),
          Vector3(4, 0, 0),
          Vector3(5, 0, 0),
          Vector3(4, 1, 0),
        ],
        <List<int>>[
          <int>[0, 1, 2, 3, 4, 5],
          <int>[6, 7, 8],
        ],
      );

      final plan = MeshLayoutPlan()..build(mesh);

      expect(plan.triangleCount, 5);
      // Four from the L and one from the triangle beside it. Mutation: leave
      // `triangleToFace` unwritten and every triangle claims face zero — a pick
      // anywhere on the mesh selects the first face, which is the bug a
      // one-face test could never see.
      final faces = <int>[
        for (var t = 0; t < plan.triangleCount; t++) plan.triangleToFace[t],
      ];
      expect(faces.where((int face) => face == 0), hasLength(4));
      expect(faces.where((int face) => face == 1), hasLength(1));
      expect(plan.fannedAnyFace, isFalse);
    });

    test('a face that could not be cut is reported', () {
      final mesh = EditMesh.fromFaces(
        <Vector3>[
          Vector3(0, 0, 0),
          Vector3(2, 2, 0),
          Vector3(2, 0, 0),
          Vector3(0, 2, 0),
        ],
        <List<int>>[
          <int>[0, 1, 2, 3],
        ],
      );

      final plan = MeshLayoutPlan()..build(mesh);

      expect(plan.fannedAnyFace, isTrue);
      expect(plan.triangleCount, 2);
    });
  });

  group('one plan per material', () {
    test('only the faces carrying the slot are planned', () {
      final mesh = EditMesh.cuboid();
      edit(mesh, () {
        mesh.setMaterialSlot(0, 1);
        mesh.setMaterialSlot(1, 1);
      });

      final first = MeshLayoutPlan()..build(mesh, materialSlot: 0);
      final second = MeshLayoutPlan()..build(mesh, materialSlot: 1);

      // Four faces against two, and no vertex is in both — a draw call takes
      // one material, so the split has to happen somewhere and it happens here
      // rather than in the renderer.
      expect(first.triangleCount, 8);
      expect(second.triangleCount, 4);
      expect(first.vertexCount, 16);
      expect(second.vertexCount, 8);
      expect(first.triangleCount + second.triangleCount, 12);
    });

    test('a mesh nobody assigned is all one slot', () {
      final mesh = EditMesh.cuboid();
      final plan = MeshLayoutPlan()..build(mesh, materialSlot: 0);
      expect(plan.triangleCount, 12);
    });
  });

  group('refilling', () {
    test('naming a vertex rewrites its rows and nothing else', () {
      final mesh = EditMesh.cuboid();
      final plan = MeshLayoutPlan()..build(mesh);
      final buffer = Float32List(plan.vertexCount * plan.floatsPerVertex);
      plan.fillVertices(mesh, buffer);
      final before = Float32List.fromList(buffer);

      // Poisoned first, because "wrote the right values" and "wrote only these
      // rows" are different promises: a fill that rewrote everything from the
      // same mesh would leave the other rows looking untouched. With rubbish in
      // them, a row that still holds rubbish afterwards is a row nothing wrote.
      buffer.fillRange(0, buffer.length, 999);

      edit(mesh, () => mesh.moveVertex(3, Vector3(-5, 5, -5)));
      final written = plan.fillVerticesOf(mesh, buffer, <int>[3]);

      // A cube corner belongs to three faces, so it owns three rows.
      expect(written, 3);

      var touched = 0;
      for (var row = 0; row < plan.vertexCount; row++) {
        final at = row * plan.floatsPerVertex;
        final untouched = <bool>[
          for (var i = 0; i < plan.floatsPerVertex; i++) buffer[at + i] == 999,
        ].every((bool it) => it);
        if (untouched) continue;
        touched++;
        expect(plan.gpuVertexToVertex[row], 3);
        // And what it wrote is the mesh as it is now, not what was there.
        expect(buffer[at], isNot(before[at]));
      }
      // Mutation: rewrite the whole buffer instead of the rows named, and this
      // is twenty-four — which is the difference between uploading a hundred
      // bytes while somebody drags a corner and uploading the whole mesh.
      expect(touched, 3);
    });

    test('a refill puts the new positions in, not stale ones', () {
      final mesh = EditMesh.cuboid();
      final plan = MeshLayoutPlan()..build(mesh);
      final buffer = Float32List(plan.vertexCount * plan.floatsPerVertex);
      plan.fillVertices(mesh, buffer);

      edit(mesh, () => mesh.moveVertex(3, Vector3(-5, 5, -5)));
      plan.fillVerticesOf(mesh, buffer, <int>[3]);

      final positionAt = plan.layout.floatOffsetOf(VertexLayout.position.name);
      for (var row = 0; row < plan.vertexCount; row++) {
        if (plan.gpuVertexToVertex[row] != 3) continue;
        final at = row * plan.floatsPerVertex + positionAt;
        expect(buffer[at], closeTo(-5, 1e-6));
        expect(buffer[at + 1], closeTo(5, 1e-6));
        expect(buffer[at + 2], closeTo(-5, 1e-6));
      }
    });

    test('a vertex nobody planned is asked for and costs nothing', () {
      final mesh = EditMesh.cuboid();
      final plan = MeshLayoutPlan()..build(mesh);
      final buffer = Float32List(plan.vertexCount * plan.floatsPerVertex);

      expect(plan.fillVerticesOf(mesh, buffer, <int>[-1, 900]), 0);
    });

    test('a full fill and a per-vertex fill agree', () {
      final mesh = EditMesh.cuboid();
      final plan = MeshLayoutPlan()..build(mesh);
      final whole = Float32List(plan.vertexCount * plan.floatsPerVertex);
      final piecemeal = Float32List(plan.vertexCount * plan.floatsPerVertex);

      plan.fillVertices(mesh, whole);
      final written = plan.fillVerticesOf(mesh, piecemeal, <int>[
        for (var v = 0; v < mesh.vertexSlotCount; v++) v,
      ]);

      expect(written, plan.vertexCount);
      expect(piecemeal, whole);
    });
  });

  group('through the mesh', () {
    test('a conversion hands out buffers of its own', () {
      final mesh = EditMesh.cuboid();
      final first = mesh.toMeshData();
      final vertices = Float32List.fromList(first.vertices);
      final indices = Uint32List.fromList(first.indices);

      // A face fewer, so the second conversion writes a shorter plan into the
      // arrays the first one would be sharing.
      edit(mesh, () {
        mesh
          ..moveVertex(0, Vector3(-9, -9, -9))
          ..deleteFace(0);
      });
      final second = mesh.toMeshData();
      expect(second.triangleCount, 10);

      // Mutation: hand back a view of the plan's index buffer instead of a
      // copy, and the second conversion rewrites the first — a caller holding
      // a mesh for a screenshot or an export gets the new triangles with the
      // tail of the old ones still on the end of them.
      expect(first.vertices, vertices);
      expect(first.indices, indices);
    });

    test('a converted cube is still twelve triangles of the right size', () {
      final drawn = EditMesh.cuboid().toMeshData();

      expect(drawn.vertexCount, 24);
      expect(drawn.triangleCount, 12);
      final bounds = drawn.computeBounds();
      expect(bounds.max.x - bounds.min.x, closeTo(1, 1e-6));
    });
  });
}
