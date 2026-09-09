/// Which way a face points, which way its corners do, and turning both round.
///
/// The oracle for a corner normal is a shape whose right answer is known
/// without computing one: a cube's corners look along the face they are on
/// unless something says to round them off, and a sphere's look straight out
/// from the middle. The oracle for a flip is the sign of the volume.
library;

import 'dart:math' as math;

import 'package:flutter3d_geometry/flutter3d_geometry.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// Runs [body] as one step of history, which every write to a mesh needs.
void edit(EditMesh mesh, void Function() body) {
  mesh.beginStep();
  body();
  mesh.endStep();
}

/// Marks every live face smooth, which is what a file with a smoothing group
/// or a user pressing "shade smooth" produces.
void smoothEverything(EditMesh mesh) {
  edit(mesh, () {
    for (var face = 0; face < mesh.faceSlotCount; face++) {
      if (mesh.isFaceAlive(face)) {
        mesh.setFaceFlag(face, FaceFlags.smooth, on: true);
      }
    }
  });
}

/// Runs [visit] over every half-edge of every live face.
void forEachCorner(EditMesh mesh, void Function(int face, int half) visit) {
  for (var face = 0; face < mesh.faceSlotCount; face++) {
    if (!mesh.isFaceAlive(face)) continue;
    mesh.forEachHalfEdge(face, (int half) => visit(face, half));
  }
}

double degreesBetween(Vector3 a, Vector3 b) =>
    math.acos(a.dot(b).clamp(-1.0, 1.0)) * radians2Degrees;

void main() {
  group('face normals', () {
    test('a cube points along the six axes', () {
      final mesh = EditMesh.cuboid();
      final normals = MeshNormals()..build(mesh);

      final seen = <String>{};
      for (var face = 0; face < mesh.faceSlotCount; face++) {
        final normal = normals.faceNormal(face);
        expect(normal.length, closeTo(1, 1e-6));
        // Exactly one component is ±1 and the others are zero, which is what
        // being axis-aligned means and what `normalOf` is asked for here.
        expect(
          normal.x.abs() + normal.y.abs() + normal.z.abs(),
          closeTo(1, 1e-6),
        );
        seen.add('${normal.x.round()},${normal.y.round()},${normal.z.round()}');
      }
      expect(seen, hasLength(6));
    });

    test('a dead face keeps no normal from before it died', () {
      final mesh = EditMesh.cuboid();
      final normals = MeshNormals()..build(mesh);
      expect(normals.faceNormal(0).length, closeTo(1, 1e-6));

      edit(mesh, () => mesh.deleteFace(0));
      normals.build(mesh);

      // Mutation: reuse the buffer without clearing it, and the deleted face
      // still answers with the normal it had — which is what a viewport drawing
      // from a stale buffer would show.
      expect(normals.faceNormal(0).length, 0);
    });
  });

  group('corner normals', () {
    test('a cube with no flags gives every corner its own face normal', () {
      final mesh = EditMesh.cuboid();
      final normals = MeshNormals()..build(mesh);

      // The default a mesh with no flags gets. Two things would each produce
      // it on their own here — nothing is marked smooth, and the edges are
      // square — so this one does not tell them apart; the gentle fold below
      // is what catches the flag being ignored, and the cube marked smooth is
      // what catches the angle being ignored.
      forEachCorner(mesh, (int face, int half) {
        expect(
          degreesBetween(normals.cornerNormal(half), normals.faceNormal(face)),
          closeTo(0, 1e-3),
        );
      });
    });

    test('a cube marked smooth still breaks, because its edges are square', () {
      final mesh = EditMesh.cuboid();
      smoothEverything(mesh);
      final normals = MeshNormals()..build(mesh);

      // Mutation: drop the dihedral test and the default threshold means
      // nothing — a smoothing group over a box rounds its edges off.
      forEachCorner(mesh, (int face, int half) {
        expect(
          degreesBetween(normals.cornerNormal(half), normals.faceNormal(face)),
          closeTo(0, 1e-3),
        );
      });
    });

    test('a cube smoothed past ninety degrees rounds off to its diagonals', () {
      final mesh = EditMesh.cuboid();
      smoothEverything(mesh);
      final normals = MeshNormals()
        ..build(mesh, smoothAngle: 100 * degrees2Radians);

      // Three faces meet at a corner of a cube, at equal angles, so the average
      // is the body diagonal — and it is the same from all three, which is what
      // says the fan was grouped rather than each corner answering alone.
      final root = 1 / math.sqrt(3);
      forEachCorner(mesh, (int _, int half) {
        final normal = normals.cornerNormal(half);
        expect(normal.x.abs(), closeTo(root, 1e-5));
        expect(normal.y.abs(), closeTo(root, 1e-5));
        expect(normal.z.abs(), closeTo(root, 1e-5));
      });
    });

    test('a sphere shades within six degrees of straight out', () {
      final (mesh, _) = importMeshData(
        const SphereShape(radius: 1, segments: 24, rings: 12).build(),
      );
      smoothEverything(mesh);
      final normals = MeshNormals()..build(mesh);

      // Mutation: never union across an edge, so a corner keeps its own face's
      // normal. A face of this sphere spans fifteen degrees, so its normal sits
      // some seven or eight degrees off the corner's radius and this fails —
      // which is exactly the faceting a smooth sphere must not have.
      var worst = 0.0;
      forEachCorner(mesh, (int _, int half) {
        final radial = mesh.positionOf(mesh.originOf(half))..normalize();
        final off = degreesBetween(normals.cornerNormal(half), radial);
        if (off > worst) worst = off;
      });
      expect(worst, lessThan(6));
    });

    test('a face nobody smoothed stays flat however gentle the fold', () {
      // Twenty degrees between the two quads, well inside the default
      // threshold — so the angle has nothing to say here and the only thing
      // keeping them apart is that neither is marked smooth. That is the case
      // the other cube tests cannot reach: a box's edges are square, so the
      // angle refuses them whatever the flags say.
      final mesh = EditMesh.fromFaces(
        <Vector3>[
          Vector3(0, 0, 0),
          Vector3(1, 0, 0),
          Vector3(1, 1, 0),
          Vector3(0, 1, 0),
          Vector3(1, 2, 0.36),
          Vector3(0, 2, 0.36),
        ],
        <List<int>>[
          <int>[0, 1, 2, 3],
          <int>[3, 2, 4, 5],
        ],
      );
      var shared = EditMesh.none;
      mesh.forEachHalfEdge(0, (int half) {
        if (mesh.twinOf(half) != EditMesh.none) shared = half;
      });

      final normals = MeshNormals()..build(mesh);
      final own = normals.faceNormal(0);
      // Mutation: drop the two `smooth` tests from `_breaks` and this fold is
      // averaged — every mesh that arrives without flags shades round, which is
      // the opposite of the rule a modeller expects.
      expect(
        degreesBetween(normals.cornerNormal(shared), own),
        closeTo(0, 1e-3),
      );

      smoothEverything(mesh);
      normals.build(mesh);
      expect(
        degreesBetween(normals.cornerNormal(shared), own),
        closeTo(9.9, 0.4),
      );
    });

    test('a sharp edge keeps the two faces on it apart', () {
      // A tent: two quads meeting at forty-five degrees along the edge 3-2.
      final mesh = EditMesh.fromFaces(
        <Vector3>[
          Vector3(0, 0, 0),
          Vector3(1, 0, 0),
          Vector3(1, 1, 0),
          Vector3(0, 1, 0),
          Vector3(1, 2, 1),
          Vector3(0, 2, 1),
        ],
        <List<int>>[
          <int>[0, 1, 2, 3],
          <int>[3, 2, 4, 5],
        ],
      );
      smoothEverything(mesh);

      // The half-edge of the first face along the shared edge.
      var shared = EditMesh.none;
      mesh.forEachHalfEdge(0, (int half) {
        if (mesh.twinOf(half) != EditMesh.none) shared = half;
      });
      expect(shared, isNot(EditMesh.none));

      final normals = MeshNormals();
      normals.build(mesh, smoothAngle: 60 * degrees2Radians);
      final averaged = normals.cornerNormal(shared);
      final own = normals.faceNormal(0);
      expect(degreesBetween(averaged, own), closeTo(22.5, 0.5));

      edit(mesh, () => mesh.setEdgeFlag(shared, EdgeFlags.sharp, on: true));
      normals.build(mesh, smoothAngle: 60 * degrees2Radians);

      // Mutation: drop the `sharp` test and the flag does nothing — a hard edge
      // authored by hand or read out of a file smooths itself away, whatever
      // the angle threshold says.
      expect(
        degreesBetween(normals.cornerNormal(shared), own),
        closeTo(0, 1e-3),
      );
    });

    test('cutting a face in two does not change the corner it was cut at', () {
      // A cube whose +Z face is two triangles rather than one quad, with the
      // diagonal running through corner 4. The surface is identical to a plain
      // cube's, so corner 4 must still look along the body diagonal.
      final plain = EditMesh.cuboid();
      final points = <Vector3>[
        for (var v = 0; v < plain.vertexSlotCount; v++) plain.positionOf(v),
      ];
      final mesh = EditMesh.fromFaces(points, <List<int>>[
        <int>[4, 5, 6],
        <int>[4, 6, 7],
        <int>[1, 0, 3, 2],
        <int>[5, 1, 2, 6],
        <int>[0, 4, 7, 3],
        <int>[3, 7, 6, 2],
        <int>[0, 1, 5, 4],
      ]);
      smoothEverything(mesh);
      final normals = MeshNormals()
        ..build(mesh, smoothAngle: 100 * degrees2Radians);

      var corner = EditMesh.none;
      forEachCorner(mesh, (int _, int half) {
        if (mesh.originOf(half) == 4) corner = half;
      });
      expect(corner, isNot(EditMesh.none));

      // Mutation: give every face an equal share instead of its angle at the
      // corner. The +Z face is counted twice because it happens to be cut in
      // two here, the normal tips nineteen degrees towards it, and a model
      // shades differently depending on how its quads were triangulated.
      final root = 1 / math.sqrt(3);
      // A hundredth of a degree of slack, which is what float32 positions cost
      // — and three orders of magnitude tighter than the mutation's nineteen.
      expect(
        degreesBetween(
          normals.cornerNormal(corner),
          Vector3(-root, -root, root),
        ),
        closeTo(0, 0.05),
      );
    });

    test('the angle at the corner is the share, not the face', () {
      // A flat sheet cut so one side of the middle vertex is one big quad and
      // the other is two slivers a hundredth as tall. Every face is coplanar,
      // so the weighting cannot change the answer and no mutation of it shows
      // here; what this is for is the arithmetic surviving a corner whose two
      // edges are all but parallel, which is where an `acos` of a dot product
      // would come back as noise or as NaN.
      final mesh = EditMesh.fromFaces(
        <Vector3>[
          Vector3(0, 0, 0),
          Vector3(2, 0, 0),
          Vector3(2, 2, 0),
          Vector3(0, 2, 0),
          Vector3(2, 0.01, 0),
          Vector3(4, 0, 0),
        ],
        <List<int>>[
          <int>[0, 1, 2, 3],
          <int>[1, 5, 4],
          <int>[4, 5, 2],
        ],
      );
      smoothEverything(mesh);
      final normals = MeshNormals()..build(mesh);

      forEachCorner(mesh, (int _, int half) {
        expect(normals.cornerNormal(half).z, closeTo(1, 1e-5));
      });
    });
  });

  group('turning a surface round', () {
    test('a flip changes the sign of the volume and nothing else', () {
      final mesh = EditMesh.cuboid();
      final before = mesh.signedVolume;
      expect(before, closeTo(1, 1e-5));

      edit(mesh, mesh.flipNormals);

      expect(mesh.signedVolume, closeTo(-1, 1e-5));
      expect(mesh.faceCount, 6);
      expect(mesh.vertexCount, 8);
      expect(mesh.eulerCharacteristic, 2);
      // Mutation: leave `_outgoing` alone after reversing the loops and this
      // throws — every vertex is pointed at by a half-edge that now starts at
      // its neighbour.
      mesh.validate();
    });

    test('the normals a renderer gets turn round with it', () {
      final mesh = EditMesh.cuboid();
      final normals = MeshNormals()..build(mesh);
      final was = normals.faceNormal(0);

      edit(mesh, mesh.flipNormals);
      normals.build(mesh);

      expect(degreesBetween(normals.faceNormal(0), was), closeTo(180, 1e-3));
    });

    test('a flip is one step of history', () {
      final mesh = EditMesh.cuboid()..beginStep();
      mesh.flipNormals();
      expect(mesh.endStep(), isTrue);
      expect(mesh.undoDepth, 1);

      expect(mesh.undo(), isTrue);
      expect(mesh.signedVolume, closeTo(1, 1e-5));
      mesh.validate();

      expect(mesh.redo(), isTrue);
      expect(mesh.signedVolume, closeTo(-1, 1e-5));
      mesh.validate();
    });

    test('a corner keeps its texture coordinate through a flip', () {
      final mesh = EditMesh.cuboid();
      final loop = <int>[];
      mesh.forEachHalfEdge(0, loop.add);
      edit(mesh, () {
        for (var i = 0; i < loop.length; i++) {
          mesh.setUv(loop[i], Vector2(i.toDouble(), 0));
        }
      });
      // What each corner's UV is, by the vertex it sits at.
      final byVertex = <int, double>{
        for (final half in loop) mesh.originOf(half): mesh.uvOf(half).x,
      };

      edit(mesh, mesh.flipNormals);

      // Mutation: skip `_rotateCorners` and every UV on the face slides one
      // corner round the loop — a texture that was aligned to a face comes back
      // rotated, which is the kind of thing nobody notices until it ships.
      mesh.forEachHalfEdge(0, (int half) {
        expect(mesh.uvOf(half).x, byVertex[mesh.originOf(half)]);
      });
    });
  });

  group('making a surface consistent', () {
    test('a cube wound inside out is turned outwards', () {
      final mesh = EditMesh.cuboid();
      edit(mesh, mesh.flipNormals);
      expect(mesh.signedVolume, lessThan(0));

      late bool turned;
      edit(mesh, () => turned = mesh.makeConsistent());
      expect(turned, isTrue);
      expect(mesh.signedVolume, closeTo(1, 1e-5));
      mesh.validate();
    });

    test('a cube that was already right is left alone', () {
      final mesh = EditMesh.cuboid();

      late bool turned;
      edit(mesh, () => turned = mesh.makeConsistent());
      expect(turned, isFalse);
      expect(mesh.signedVolume, closeTo(1, 1e-5));
    });

    test('an open surface is left alone whatever its volume says', () {
      // A cube with a face removed: the cone from the origin over what is left
      // is still negative, and there is still no inside for a normal to point
      // out of.
      final mesh = EditMesh.cuboid();
      edit(mesh, mesh.flipNormals);
      edit(mesh, () => mesh.deleteFace(0));
      final before = mesh.signedVolume;
      expect(before, lessThan(0));

      // Mutation: drop the `open` test and this flips — which is the bug that
      // turns half a scanned surface inside out on load, because the sign of an
      // open shell's volume is about where the origin happens to be.
      late bool turned;
      edit(mesh, () => turned = mesh.makeConsistent());
      expect(turned, isFalse);
      expect(mesh.signedVolume, before);
    });

    test('two islands are decided apart', () {
      final good = EditMesh.cuboid();
      final points = <Vector3>[];
      final faces = <List<int>>[];
      for (var vertex = 0; vertex < good.vertexSlotCount; vertex++) {
        points.add(good.positionOf(vertex));
      }
      faces.addAll(good.faces());
      // A second box beside it, wound inside out.
      final base = points.length;
      for (var vertex = 0; vertex < good.vertexSlotCount; vertex++) {
        points.add(good.positionOf(vertex)..add(Vector3(4, 0, 0)));
      }
      for (final face in good.faces()) {
        faces.add(<int>[for (final v in face.reversed) v + base]);
      }
      final mesh = EditMesh.fromFaces(points, faces);
      // The two cancel, so a mesh-wide sign has nothing to say.
      expect(mesh.signedVolume, closeTo(0, 1e-5));

      late bool turned;
      edit(mesh, () => turned = mesh.makeConsistent());
      expect(turned, isTrue);

      // Mutation: sum the volume over the whole mesh instead of per island and
      // nothing is flipped here at all — the good box hides the bad one.
      expect(mesh.signedVolume, closeTo(2, 1e-4));
      mesh.validate();
    });
  });

  group('through the conversion', () {
    test('a smoothed sphere hands the renderer smooth normals', () {
      final (mesh, _) = importMeshData(
        const SphereShape(radius: 1, segments: 16, rings: 8).build(),
      );
      smoothEverything(mesh);

      final drawn = mesh.toMeshData();
      final positionAt = drawn.layout.floatOffsetOf(VertexLayout.position.name);
      final normalAt = drawn.layout.floatOffsetOf(VertexLayout.normal.name);
      final stride = drawn.layout.floatsPerVertex;

      var worst = 0.0;
      for (var i = 0; i < drawn.vertexCount; i++) {
        final radial = Vector3(
          drawn.vertices[i * stride + positionAt],
          drawn.vertices[i * stride + positionAt + 1],
          drawn.vertices[i * stride + positionAt + 2],
        )..normalize();
        final normal = Vector3(
          drawn.vertices[i * stride + normalAt],
          drawn.vertices[i * stride + normalAt + 1],
          drawn.vertices[i * stride + normalAt + 2],
        );
        final off = degreesBetween(normal, radial);
        if (off > worst) worst = off;
      }
      expect(worst, lessThan(9));
    });

    test('a cube without flags still converts to flat faces', () {
      final drawn = EditMesh.cuboid().toMeshData();
      final normalAt = drawn.layout.floatOffsetOf(VertexLayout.normal.name);
      final stride = drawn.layout.floatsPerVertex;

      for (var i = 0; i < drawn.vertexCount; i++) {
        final normal = Vector3(
          drawn.vertices[i * stride + normalAt],
          drawn.vertices[i * stride + normalAt + 1],
          drawn.vertices[i * stride + normalAt + 2],
        );
        expect(
          normal.x.abs() + normal.y.abs() + normal.z.abs(),
          closeTo(1, 1e-5),
        );
      }
    });
  });
}
