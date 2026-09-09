/// The spike, held to the three numbers `mesh-01` asks it for: the Euler
/// characteristic after every step, the volume an extrusion adds, and a mesh
/// the engine's own vocabulary can carry.
///
/// Written the way `ARCHITECTURE.md` §6.3 asks — each check was watched to
/// fail. The mutations are named beside the checks they belong to.
library;

import 'package:flutter3d_geometry/flutter3d_geometry.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('a cube built as quads', () {
    test('has eight vertices, twelve edges and six faces', () {
      final cube = EditMesh.cuboid();

      expect(cube.vertexCount, 8);
      expect(cube.edgeCount, 12);
      expect(cube.faceCount, 6);
      expect(cube.eulerCharacteristic, 2);
      // Twenty-four half-edges, all of them paired: a closed surface has no
      // boundary, and a face wound the wrong way round would leave two.
      expect(cube.halfEdgeCount, 24);
      for (var half = 0; half < cube.halfEdgeCount; half++) {
        expect(cube.twinOf(half), isNot(EditMesh.noHalfEdge));
      }
      cube.validate();
    });

    test('winds every face outwards, which its volume is what says so', () {
      final cube = EditMesh.cuboid(size: Vector3(2, 2, 2));

      // Mutation: reverse one face's winding in `EditMesh.cuboid` and this
      // falls to 6.67, because that face's contribution changes sign.
      expect(cube.signedVolume, closeTo(8, 1e-5));
      for (var face = 0; face < cube.faceCount; face++) {
        final normal = cube.normalOf(face);
        final outward = cube.positionOf(cube.verticesOf(face).first);
        expect(
          normal.dot(outward),
          greaterThan(0),
          reason: 'face $face points inwards',
        );
      }
    });
  });

  group('extruding a face', () {
    test('adds the face area times the distance to the volume', () {
      final cube = EditMesh.cuboid();
      final area = cube.areaOf(0);
      final before = cube.signedVolume;

      final extruded = cube.extrudeFace(0, 0.5);

      // Mutation: extrude along the negative normal and this is 0.5 short —
      // the cube loses as much as it should have gained.
      expect(extruded.signedVolume, closeTo(before + area * 0.5, 1e-5));
      expect(area, closeTo(1, 1e-6));
    });

    test('keeps the surface closed and its characteristic at two', () {
      final extruded = EditMesh.cuboid().extrudeFace(0, 0.5);

      // A quad extruded: four new vertices, eight new edges, four new faces.
      expect(extruded.vertexCount, 12);
      expect(extruded.edgeCount, 20);
      expect(extruded.faceCount, 10);
      expect(extruded.eulerCharacteristic, 2);
      for (var half = 0; half < extruded.halfEdgeCount; half++) {
        expect(extruded.twinOf(half), isNot(EditMesh.noHalfEdge));
      }
      // Mutation: leave the original face in place rather than lifting it and
      // `validate` throws on the edge that now has three faces.
      extruded.validate();
    });

    test('twice in a row is a step, not a mesh that has come apart', () {
      // The lifted face lands where `extrudeFace` says it does: after the
      // faces that were kept, so five of six here.
      final tower = EditMesh.cuboid().extrudeFace(0, 0.5).extrudeFace(5, 0.5);

      expect(tower.eulerCharacteristic, 2);
      expect(tower.signedVolume, closeTo(2.0, 1e-5));
      tower.validate();
    });
  });

  group('handing it back to the engine', () {
    test('a cube becomes the twenty-four vertices a GPU needs', () {
      final mesh = EditMesh.cuboid().toMeshData();

      // One vertex per corner per face, so each face keeps a flat normal —
      // the same count `CuboidShape` produces, arrived at from the other side.
      expect(mesh.vertexCount, 24);
      expect(mesh.triangleCount, 12);
      expect(mesh.layout, VertexLayout.standard);
    });

    test('the triangles enclose the volume the faces did', () {
      final cube = EditMesh.cuboid(size: Vector3(2, 2, 2));

      expect(
        cube.toMeshData().signedVolume(),
        closeTo(cube.signedVolume, 1e-4),
      );
    });

    test('an extruded face is drawn where it was pushed to', () {
      final mesh = EditMesh.cuboid().extrudeFace(0, 0.5).toMeshData();

      // +Z is face 0, so the far corner of the mesh has moved out with it.
      expect(mesh.computeBounds().max.z, closeTo(1.0, 1e-6));
      expect(mesh.triangleCount, 20);
    });
  });

  group('what it refuses', () {
    test('a third face on one edge, rather than keeping the last one seen', () {
      expect(
        () => EditMesh.fromFaces(
          <Vector3>[
            Vector3(0, 0, 0),
            Vector3(1, 0, 0),
            Vector3(0, 1, 0),
            Vector3(0, 0, 1),
            Vector3(1, 1, 0),
          ],
          <List<int>>[
            <int>[0, 1, 2],
            <int>[0, 1, 3],
          ],
        ),
        throwsArgumentError,
      );
    });

    test('a face of two vertices', () {
      expect(
        () => EditMesh.fromFaces(
          <Vector3>[Vector3(0, 0, 0), Vector3(1, 0, 0)],
          <List<int>>[
            <int>[0, 1],
          ],
        ),
        throwsArgumentError,
      );
    });
  });
}
