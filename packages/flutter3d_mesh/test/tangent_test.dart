/// The tangent frame a normal map is read in.
///
/// **The sign of `w` is the whole test.** A tangent pointing the wrong way
/// along a texture is a surface lit from the wrong side, and it is invisible on
/// anything symmetric — which is most test shapes. So the oracle is the
/// engine's own generator over the engine's own boxes and planes: a mesh that
/// went round through `EditMesh` and came back has to agree with one that never
/// left, corner for corner. The other half is a mirrored island, where `w` is
/// the only thing that says the texture is flipped.
library;

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

/// Every (position, tangent) pair of a mesh, rounded and sorted so two meshes
/// that describe the same surface compare equal whatever order they hold it in.
List<String> framesOf(MeshData mesh) {
  final stride = mesh.layout.floatsPerVertex;
  final positionAt = mesh.layout.floatOffsetOf(VertexLayout.position.name);
  final tangentAt = mesh.layout.floatOffsetOf(VertexLayout.tangent.name);
  String at(int row, int offset, int count) => <String>[
    for (var i = 0; i < count; i++)
      mesh.vertices[row * stride + offset + i].toStringAsFixed(3),
  ].join(',');

  return <String>[
    for (var row = 0; row < mesh.vertexCount; row++)
      '${at(row, positionAt, 3)}|${at(row, tangentAt, 4)}',
  ]..sort();
}

/// A mesh imported from [drawn] with its coplanar diagonals dissolved, so the
/// quads the engine built come back as quads rather than pairs of triangles.
EditMesh asQuads(MeshData drawn) {
  final (mesh, _) = importMeshData(drawn);
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
      if (here.dot(there) > 0.9999) mesh.dissolveEdge(half);
    }
  });
  return mesh;
}

/// The `w` of every vertex.
List<double> signsOf(MeshData mesh) {
  final stride = mesh.layout.floatsPerVertex;
  final at = mesh.layout.floatOffsetOf(VertexLayout.tangent.name);
  return <double>[
    for (var row = 0; row < mesh.vertexCount; row++)
      mesh.vertices[row * stride + at + 3],
  ];
}

void main() {
  group('against the engine', () {
    test('a box that went round through an edit mesh comes back the same', () {
      final engine = CuboidShape().build().withGeneratedTangents();
      final drawn = asQuads(CuboidShape().build()).toMeshData();

      // Twenty-four vertices in both, and every one of them the same place
      // with the same frame. Mutation: leave the tangent slots at zero, and a
      // model drawn with a normal map comes out black — which the layout
      // *declares* a tangent for, so nothing downstream would even warn.
      expect(drawn.vertexCount, 24);
      expect(framesOf(drawn), framesOf(engine));
    });

    test('a plane agrees too, and its tangents run along the texture', () {
      final engine = const PlaneShape(
        width: 2,
        depth: 2,
      ).build().withGeneratedTangents();
      final drawn = asQuads(
        const PlaneShape(width: 2, depth: 2).build(),
      ).toMeshData();

      expect(drawn.vertexCount, 4);
      expect(framesOf(drawn), framesOf(engine));
      // All facing the same way, so all four signs agree.
      expect(signsOf(drawn).toSet(), hasLength(1));
    });
  });

  group('a mirrored island', () {
    test('flips the sign and nothing else', () {
      // Two quads side by side with the same shape and the same normal, whose
      // texture coordinates run opposite ways: the second is the mirror of the
      // first, and `w` is the only number that says so.
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
        // The first runs left to right in u.
        const straight = <List<double>>[
          <double>[0, 0],
          <double>[1, 0],
          <double>[1, 1],
          <double>[0, 1],
        ];
        // The second runs right to left, which is a mirror.
        const mirrored = <List<double>>[
          <double>[1, 0],
          <double>[0, 0],
          <double>[0, 1],
          <double>[1, 1],
        ];
        for (final face in <int>[0, 1]) {
          final uvs = face == 0 ? straight : mirrored;
          var corner = 0;
          mesh.forEachHalfEdge(face, (int half) {
            final uv = uvs[corner++];
            mesh.setUv(half, Vector2(uv[0], uv[1]));
          });
        }
      });

      final drawn = mesh.toMeshData();
      final signs = signsOf(drawn);

      // Mutation: take the sign from the winding rather than from the texture,
      // and both islands come out the same — a normal map on the mirrored half
      // of a model then lights from the wrong side, which is the one bug this
      // number exists to prevent.
      expect(signs.toSet(), <double>{-1.0, 1.0});
      expect(signs.where((double it) => it > 0), isNotEmpty);
      expect(signs.where((double it) => it < 0), isNotEmpty);
    });
  });

  group('who generates them', () {
    test('a plan leaves them alone unless it is asked', () {
      final (mesh, _) = importMeshData(CuboidShape().build());
      final plan = MeshLayoutPlan()..build(mesh);

      // The buffer-reuse path fills what a row can be filled with, and a
      // tangent is not that: it is accumulated over the triangles a vertex is
      // in. Mutation: generate them here anyway, and the mesh handed back is a
      // copy — so the next `fillVerticesOf` into the reused buffer no longer
      // reaches what the caller is holding.
      expect(signsOf(plan.toMeshData(mesh)).toSet(), <double>{0.0});

      expect(
        signsOf(plan.toMeshData(mesh, withTangents: true)).toSet(),
        isNot(<double>{0.0}),
      );
    });

    test('a layout with no tangent is left as it is', () {
      final drawn = asQuads(
        CuboidShape().build(),
      ).toMeshData(layout: VertexLayout.positionNormalTexcoord);

      expect(drawn.layout.has(VertexLayout.tangent), isFalse);
      expect(drawn.vertexCount, 24);
    });

    test('a mesh with no texture coordinates still gets a frame', () {
      // Every texture coordinate is the neutral zero, so there is no
      // parametrization to derive a direction from. What matters is that the
      // frame is still a frame — a unit tangent and a sign of ±1 — rather than
      // four zeros, which a shader would read as a surface with no width.
      final drawn = EditMesh.cuboid().toMeshData();
      final stride = drawn.layout.floatsPerVertex;
      final at = drawn.layout.floatOffsetOf(VertexLayout.tangent.name);

      expect(drawn.layout.has(VertexLayout.tangent), isTrue);
      for (var row = 0; row < drawn.vertexCount; row++) {
        final tangent = Vector3(
          drawn.vertices[row * stride + at],
          drawn.vertices[row * stride + at + 1],
          drawn.vertices[row * stride + at + 2],
        );
        expect(tangent.length, closeTo(1, 1e-5));
        expect(drawn.vertices[row * stride + at + 3].abs(), 1);
      }
    });
  });
}
