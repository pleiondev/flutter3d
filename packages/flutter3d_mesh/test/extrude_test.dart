/// Pushing faces and edges out.
///
/// The counts are the oracle, because an extrusion is a statement about
/// topology before it is one about shape: a box's face pushed out has to give
/// twelve vertices, twenty edges and ten faces, and χ has to still be 2. A
/// number that comes out wrong there is a mesh that looks right in one frame
/// and comes apart on the next operation.
library;

import 'dart:math' as math;

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

/// The corners of [face] as texture coordinates, in loop order.
List<Vector2> uvsOf(EditMesh mesh, int face) {
  final out = <Vector2>[];
  mesh.forEachHalfEdge(face, (int half) => out.add(mesh.uvOf(half)));
  return out;
}

void main() {
  group('a face of a box', () {
    test('comes out as twelve vertices, twenty edges and ten faces', () {
      final mesh = EditMesh.cuboid();
      final face = Selection.of(ElementLevel.face, <int>[0]);

      late OpResult result;
      edit(mesh, () {
        result = extrudeFaces(mesh, face, distance: 0.5);
      });

      expect(result.ok, isTrue);
      expect(mesh.vertexCount, 12);
      expect(mesh.edgeCount, 20);
      expect(mesh.faceCount, 10);
      expect(mesh.eulerCharacteristic, 2);
      // Mutation: leave the region's half-edges on the vertices they had, and
      // the four walls stand on nothing — twelve vertices, four of which no
      // face reaches, and a box with a lid floating over it.
      mesh.validate();

      // A unit box with half a unit more on top.
      expect(mesh.signedVolume, closeTo(1.5, 1e-5));
      expect(result.topologyChanged, isTrue);
      expect(result.selection.ids, <int>[0]);
    });

    test('a distance of zero still detaches and walls', () {
      final mesh = EditMesh.cuboid();

      edit(mesh, () {
        extrudeFaces(
          mesh,
          Selection.of(ElementLevel.face, <int>[0]),
          distance: 0,
        );
      });

      // The walls are there and stand at no height, which is what an
      // interactive extrusion looks like between the key and the drag.
      expect(mesh.faceCount, 10);
      expect(mesh.signedVolume, closeTo(1, 1e-5));
      mesh.validate();

      // And the drag is an ordinary transform over what the extrusion selected.
      edit(mesh, () {
        translateSelection(
          mesh,
          Selection.of(ElementLevel.face, <int>[0]),
          by: Vector3(0, 0, 2),
        );
      });
      expect(mesh.signedVolume, closeTo(3, 1e-5));
      mesh.validate();
    });

    test('the whole box has no rim to wall in, and says so', () {
      final mesh = EditMesh.cuboid();
      final everything = Selection.of(ElementLevel.face, <int>[
        for (var f = 0; f < mesh.faceSlotCount; f++) f,
      ]);

      late OpResult result;
      edit(mesh, () {
        result = extrudeFaces(mesh, everything, distance: 1);
      });

      // Mutation: build no walls and lift anyway, and a closed box grows a
      // second closed box inside itself with nothing joining them.
      expect(result.ok, isFalse);
      expect(result.reason, contains('rim'));
      expect(mesh.faceCount, 6);
    });

    test('nothing selected is refused with something to say', () {
      final mesh = EditMesh.cuboid();

      late OpResult result;
      edit(mesh, () {
        result = extrudeFaces(
          mesh,
          Selection.empty(ElementLevel.face),
          distance: 1,
        );
      });

      expect(result.ok, isFalse);
      expect(result.reason, contains('selected'));
    });
  });

  group('a region against one face at a time', () {
    test('two faces side by side share their seam and get six walls', () {
      final mesh = EditMesh.cuboid();
      // The +Z and +X faces of the box, which meet along an edge.
      final two = Selection.of(ElementLevel.face, <int>[0, 2]);
      final before = mesh.faceCount;

      edit(mesh, () => extrudeFaces(mesh, two, distance: 0.5));

      // Six, not eight: the edge between them is inside the selection, and a
      // wall there would be a wall through the middle of the new shape.
      // Mutation: wall every edge of every selected face, and this is eight —
      // two of them inside the solid, invisible and in every export.
      expect(mesh.faceCount, before + 6);
      expect(mesh.eulerCharacteristic, 2);
      mesh.validate();
    });

    test('one at a time gives each face its own four walls', () {
      final mesh = EditMesh.cuboid();
      final two = Selection.of(ElementLevel.face, <int>[0, 2]);
      final before = mesh.faceCount;

      edit(mesh, () {
        extrudeFaces(mesh, two, distance: 0.5, individual: true);
      });

      expect(mesh.faceCount, before + 8);
      mesh.validate();
    });

    test(
      'a region leans the way its faces do, weighted by how big they are',
      () {
        final mesh = EditMesh.cuboid();

        edit(mesh, () {
          extrudeFaces(
            mesh,
            Selection.of(ElementLevel.face, <int>[0, 2]),
            distance: 1,
          );
        });

        // Two equal faces at right angles, so the region goes out at forty-five
        // degrees in x and z and not at all in y. Mutation: average the face
        // normals without weighting them by area, and this still passes here
        // because the two faces are the same size — what it catches is the
        // direction being taken from one face rather than from both, which
        // would send the region straight out in z.
        var furthestZ = -9.0;
        var highest = -9.0;
        var tallest = -9.0;
        for (var v = 0; v < mesh.vertexSlotCount; v++) {
          if (!mesh.isVertexAlive(v)) continue;
          final at = mesh.positionOf(v);
          if (at.x > highest) highest = at.x;
          if (at.z > furthestZ) furthestZ = at.z;
          if (at.y > tallest) tallest = at.y;
        }
        final root = 0.5 + 1 / math.sqrt(2);
        expect(highest, closeTo(root, 1e-5));
        expect(furthestZ, closeTo(root, 1e-5));
        expect(tallest, closeTo(0.5, 1e-5), reason: 'nothing moves in y');
      },
    );
  });

  group('what a wall inherits', () {
    test('its texture is a unit square of its own', () {
      final mesh = EditMesh.cuboid();
      edit(mesh, () {
        mesh.forEachHalfEdge(0, (int half) => mesh.setUv(half, Vector2(9, 9)));
      });

      edit(mesh, () {
        extrudeFaces(
          mesh,
          Selection.of(ElementLevel.face, <int>[0]),
          distance: 1,
        );
      });

      // The first wall built, whose corners run across the edge and up the
      // extrusion. Mutation: copy the source face's corner onto all four and
      // every wall is one point of a texture stretched over it.
      final wall = uvsOf(mesh, 6);
      expect(wall[0], Vector2(0, 0));
      expect(wall[1], Vector2(1, 0));
      expect(wall[2], Vector2(1, 1));
      expect(wall[3], Vector2(0, 1));

      // The face on top keeps what it had.
      expect(uvsOf(mesh, 0).first, Vector2(9, 9));
    });

    test('a mesh with no texture layer does not grow one', () {
      final mesh = EditMesh.cuboid();

      edit(mesh, () {
        extrudeFaces(
          mesh,
          Selection.of(ElementLevel.face, <int>[0]),
          distance: 1,
        );
      });

      // Mutation: write the wall's coordinates whatever the mesh carries, and
      // an extrusion on a model that never had texture coordinates puts a
      // layer on every corner of it — a megabyte per sixty thousand corners
      // for information nobody entered.
      expect(mesh.hasLayer(MeshDomain.corner, MeshAttribute.uv0), isFalse);
    });

    test('the material and the shading come from the face below', () {
      final mesh = EditMesh.cuboid();
      edit(mesh, () {
        mesh
          ..setMaterialSlot(0, 4)
          ..setFaceFlag(0, FaceFlags.smooth, on: true);
      });

      edit(mesh, () {
        extrudeFaces(
          mesh,
          Selection.of(ElementLevel.face, <int>[0]),
          distance: 1,
        );
      });

      // Mutation: leave the walls on slot zero, and an extrusion of a face
      // somebody assigned a material to comes out wearing the default one.
      for (var wall = 6; wall < 10; wall++) {
        expect(mesh.materialSlotOf(wall), 4);
        expect(mesh.faceHas(wall, FaceFlags.smooth), isTrue);
      }
    });
  });

  group('history', () {
    test('an extrusion is one step, and the vertices it added go away', () {
      final mesh = EditMesh.cuboid();

      edit(mesh, () {
        extrudeFaces(
          mesh,
          Selection.of(ElementLevel.face, <int>[0]),
          distance: 0.5,
        );
      });
      expect(mesh.vertexSlotCount, 12);

      expect(mesh.undo(), isTrue);

      // Mutation: leave the slot counts where the extrusion put them, and the
      // undone vertices are still there — walked by every conversion, drawn as
      // four points nothing joins, and counted by every check.
      mesh.validate();
      expect(mesh.vertexSlotCount, 8);
      expect(mesh.faceSlotCount, 6);
      expect(mesh.vertexCount, 8);
      expect(mesh.faceCount, 6);
      expect(mesh.signedVolume, closeTo(1, 1e-5));

      expect(mesh.redo(), isTrue);
      expect(mesh.vertexCount, 12);
      expect(mesh.faceCount, 10);
      expect(mesh.signedVolume, closeTo(1.5, 1e-5));
      mesh.validate();
    });

    test('two extrusions in a row undo one at a time', () {
      final mesh = EditMesh.cuboid();
      final face = Selection.of(ElementLevel.face, <int>[0]);

      edit(mesh, () => extrudeFaces(mesh, face, distance: 0.5));
      edit(mesh, () => extrudeFaces(mesh, face, distance: 0.5));
      expect(mesh.signedVolume, closeTo(2, 1e-5));
      expect(mesh.faceCount, 14);

      expect(mesh.undo(), isTrue);
      expect(mesh.faceCount, 10);
      mesh.validate();

      expect(mesh.undo(), isTrue);
      expect(mesh.faceCount, 6);
      expect(mesh.vertexSlotCount, 8);
      mesh.validate();
    });
  });

  group('an edge on a rim', () {
    test('pulling it out widens the sheet', () {
      final mesh = grid(2);
      final rim = Selection.of(ElementLevel.face, <int>[
        for (var f = 0; f < mesh.faceSlotCount; f++) f,
      ]).boundary(mesh);
      // The three edges along one side of the sheet.
      final side = Selection.of(ElementLevel.edge, <int>[
        for (final edge in rim.ids)
          if (mesh.positionOf(mesh.originOf(edge)).y == 0 &&
              mesh.positionOf(mesh.originOf(mesh.nextOf(edge))).y == 0)
            edge,
      ]);
      expect(side.length, 2);

      late OpResult result;
      edit(mesh, () {
        result = extrudeEdges(mesh, side, by: Vector3(0, -1, 0));
      });

      expect(result.ok, isTrue);
      expect(mesh.faceCount, 6);
      expect(mesh.vertexCount, 12);
      // Mutation: leave the two new quads unjoined along the upright they
      // share, and the widened strip is two flaps with a slit between them.
      expect(mesh.eulerCharacteristic, 1);
      mesh.validate();
    });

    test('an edge with a face on both sides is refused', () {
      final mesh = grid(2);
      // The edge between two of the sheet's quads.
      var inner = EditMesh.none;
      mesh.forEachHalfEdge(0, (int half) {
        if (mesh.hasLiveTwin(half)) inner = mesh.edgeOf(half);
      });

      late OpResult result;
      edit(mesh, () {
        result = extrudeEdges(
          mesh,
          Selection.of(ElementLevel.edge, <int>[inner]),
          by: Vector3(0, 0, 1),
        );
      });

      // Mutation: build the quad anyway, and the edge has three faces on it —
      // which a half-edge mesh cannot hold, so one of the three silently loses
      // its twin.
      expect(result.ok, isFalse);
      expect(result.reason, contains('both sides'));
      expect(mesh.faceCount, 4);
    });
  });
}
