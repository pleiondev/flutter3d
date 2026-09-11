/// Rebuilding an editable mesh from a drawable one.
///
/// The three decisions an import makes are the three things tested here, and
/// each has a mutation named beside it: welding a cube's twenty-four vertices
/// back into eight corners, turning a mirrored face round so its neighbours
/// agree, and detaching the third face on an edge a half-edge mesh cannot hold.
library;

import 'dart:typed_data';

import 'package:flutter3d_geometry/flutter3d_geometry.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A mesh of raw triangles, the way a decoder hands one over.
MeshData triangleSoup(List<Vector3> points, List<int> indices) {
  final builder = MeshBuilder(VertexLayout.standard);
  for (final point in points) {
    builder.addVertex(position: point, normal: Vector3(0, 1, 0));
  }
  for (var i = 0; i + 2 < indices.length; i += 3) {
    builder.addTriangle(indices[i], indices[i + 1], indices[i + 2]);
  }
  return builder.build();
}

void main() {
  group('welding', () {
    test('a cube comes back as eight corners, and its shape is unchanged', () {
      final drawn = CuboidShape().build();
      // What the GPU needs: a corner per face normal meeting there.
      expect(drawn.vertexCount, 24);

      final (mesh, report, _) = importMeshData(drawn);

      // Eight corners, eighteen edges, twelve triangles — a triangulated cube,
      // and χ is still 2, which is the cheapest statement that nothing came
      // apart in the rebuild.
      expect(mesh.vertexCount, 8);
      expect(mesh.faceCount, 12);
      expect(mesh.edgeCount, 18);
      expect(mesh.eulerCharacteristic, 2);
      mesh.validate();

      expect(report.sourceVertices, 24);
      expect(report.weldedVertices, 8);
      expect(report.splitNonManifold, 0);
      expect(report.droppedDegenerate, 0);

      // The same box, still wound outwards.
      expect(mesh.signedVolume, closeTo(drawn.signedVolume(), 1e-5));
    });

    test('a sphere welds its seam, so nothing is left on a boundary', () {
      final drawn = const SphereShape(
        radius: 1,
        segments: 24,
        rings: 12,
      ).build();

      final (mesh, report, _) = importMeshData(drawn);

      expect(report.weldedVertices, lessThan(report.sourceVertices));
      // Mutation: quantise coordinates into one cell and look no further, and
      // the seam's two columns of vertices land on either side of a cell
      // boundary — welding on some machines and not others. What that leaves is
      // a slit up the sphere, which shows here as boundary edges.
      var boundary = 0;
      for (var half = 0; half < mesh.halfEdgeSlotCount; half++) {
        if (mesh.twinOf(half) == EditMesh.none) boundary++;
      }
      expect(boundary, 0, reason: 'the seam did not weld');
      mesh.validate();
    });

    test('welding at zero keeps vertices that only nearly coincide', () {
      final drawn = triangleSoup(
        <Vector3>[
          Vector3(0, 0, 0),
          Vector3(1, 0, 0),
          Vector3(0, 1, 0),
          // A hair away from the first, which an exporter's rounding produces.
          Vector3(1e-9, 0, 0),
          Vector3(1, 0, 0),
          Vector3(0, -1, 0),
        ],
        <int>[0, 1, 2, 3, 4, 5],
      );

      final (welded, _, _) = importMeshData(drawn);
      expect(welded.vertexCount, 4);

      final (apart, _, _) = importMeshData(drawn, weldEpsilon: 0);
      expect(apart.vertexCount, 5, reason: 'exact matches still weld');
    });

    test('a triangle that collapses when welded is dropped', () {
      final drawn = triangleSoup(
        <Vector3>[
          Vector3(0, 0, 0),
          Vector3(1, 0, 0),
          Vector3(0, 1, 0),
          // Three points, two of which are the same place: no area, no winding.
          Vector3(2, 0, 0),
          Vector3(2, 0, 0),
          Vector3(3, 0, 0),
        ],
        <int>[0, 1, 2, 3, 4, 5],
      );

      final (mesh, report, _) = importMeshData(drawn);

      expect(report.droppedDegenerate, 1);
      expect(mesh.faceCount, 1);
      mesh.validate();
    });
  });

  group('orientation', () {
    test('a face wound the wrong way is turned to match its neighbour', () {
      // Two triangles sharing an edge, the second one mirrored: both use the
      // edge 1 -> 2 in the same direction, which two faces of one surface never
      // do.
      final drawn = triangleSoup(
        <Vector3>[
          Vector3(0, 0, 0),
          Vector3(1, 0, 0),
          Vector3(1, 1, 0),
          Vector3(0, 1, 0),
        ],
        <int>[0, 1, 2, 1, 2, 3],
      );

      final (mesh, report, _) = importMeshData(drawn);

      // Mutation: skip `_repairOrientation` and the builder refuses the second
      // face outright — "the edge 1-2 is used twice the same way round" — so
      // the import would either lose it or detach it as a non-manifold split.
      expect(report.flippedFaces, 1);
      expect(report.splitNonManifold, 0);
      expect(mesh.faceCount, 2);
      mesh.validate();

      // And the two now share the edge properly, so it has a twin.
      var shared = 0;
      for (var half = 0; half < mesh.halfEdgeSlotCount; half++) {
        if (mesh.twinOf(half) != EditMesh.none) shared++;
      }
      expect(shared, 2, reason: 'one edge, seen from both faces');
    });

    test('a whole cube wound inside out stays consistent with itself', () {
      final drawn = CuboidShape().build();
      // Every triangle reversed, which is what a mirrored export looks like.
      final flipped = Uint32List.fromList(drawn.indices);
      for (var i = 0; i + 2 < flipped.length; i += 3) {
        final swap = flipped[i + 1];
        flipped[i + 1] = flipped[i + 2];
        flipped[i + 2] = swap;
      }
      final reversed = MeshData(
        layout: drawn.layout,
        vertices: drawn.vertices,
        indices: flipped,
      );

      final (mesh, report, _) = importMeshData(reversed);

      // Consistent, which is what the repair promises. Whether the whole shell
      // is inside out is a different question — the volume answers it, and the
      // repair deliberately does not, because a surface with a boundary has no
      // inside to be out of.
      expect(report.splitNonManifold, 0);
      expect(mesh.eulerCharacteristic, 2);
      expect(mesh.signedVolume, closeTo(-drawn.signedVolume(), 1e-5));
      mesh.validate();
    });

    test('two islands are repaired independently', () {
      final drawn = triangleSoup(
        <Vector3>[
          Vector3(0, 0, 0),
          Vector3(1, 0, 0),
          Vector3(0, 1, 0),
          Vector3(5, 0, 0),
          Vector3(6, 0, 0),
          Vector3(5, 1, 0),
        ],
        <int>[0, 1, 2, 3, 4, 5],
      );

      final (mesh, report, _) = importMeshData(drawn);

      // Nothing to disagree about: neither island touches the other, so no
      // flip is warranted and none happens.
      expect(report.flippedFaces, 0);
      expect(mesh.faceCount, 2);
      mesh.validate();
    });
  });

  group('non-manifold edges', () {
    test('a third face on one edge is detached, and the count says so', () {
      // Three triangles hanging off the edge 0-1, which is a shape a half-edge
      // mesh has no room for: a half-edge has one twin.
      final drawn = triangleSoup(
        <Vector3>[
          Vector3(0, 0, 0),
          Vector3(1, 0, 0),
          Vector3(0, 1, 0),
          Vector3(0, -1, 0),
          Vector3(0, 0, 1),
        ],
        <int>[0, 1, 2, 1, 0, 3, 0, 1, 4],
      );

      final (mesh, report, _) = importMeshData(drawn);

      // Mutation: let the builder see the third face and it throws — an import
      // that refuses a model somebody has is an import nobody can use, so the
      // edge is split and the fact is reported instead.
      expect(report.splitNonManifold, greaterThanOrEqualTo(1));
      expect(mesh.faceCount, 3, reason: 'no face is lost');
      expect(report.worthReporting, isTrue);
      mesh.validate();

      // The detached face has its own copies of the two vertices, so the mesh
      // holds more than the five places its points stand in.
      expect(mesh.vertexCount, greaterThan(5));
    });

    test('an ordinary model reports nothing worth reporting', () {
      final (_, report, _) = importMeshData(CuboidShape().build());

      expect(report.worthReporting, isFalse);
      expect(report.toString(), contains('12 faces'));
    });
  });

  group('what comes across', () {
    test('texture coordinates follow their corners', () {
      final drawn = const PlaneShape(width: 2, depth: 2).build();
      final uvAt = drawn.layout.floatOffsetOf(VertexLayout.texcoord.name);
      expect(uvAt, greaterThanOrEqualTo(0));

      final (mesh, _, _) = importMeshData(drawn);

      expect(mesh.hasLayer(MeshDomain.corner, MeshAttribute.uv0), isTrue);
      // A plane's corners span the unit square, so the imported corners do too.
      var lowest = 1.0;
      var highest = 0.0;
      for (var face = 0; face < mesh.faceSlotCount; face++) {
        mesh.forEachHalfEdge(face, (int half) {
          final uv = mesh.uvOf(half);
          lowest = uv.x < lowest ? uv.x : lowest;
          highest = uv.x > highest ? uv.x : highest;
        });
      }
      expect(lowest, closeTo(0, 1e-6));
      expect(highest, closeTo(1, 1e-6));
    });

    test('an import is the document\'s starting point, not an edit', () {
      final (mesh, _, _) = importMeshData(CuboidShape().build());

      // Nothing to undo: there is no state before the model existed, and a
      // history that offered one would empty the viewport.
      expect(mesh.undoDepth, 0);
      expect(mesh.undo(), isFalse);
    });
  });

  group('shape keys from morph targets', () {
    // A quad, as the raw soup a decoder hands over: two triangles, six
    // source vertices, welding down to the corners' own four positions —
    // p0 and p2 both appear twice, once in each triangle.
    final p0 = Vector3(0, 0, 0);
    final p1 = Vector3(1, 0, 0);
    final p2 = Vector3(1, 1, 0);
    final p3 = Vector3(0, 1, 0);
    MeshData quadWithTargets(List<MorphTarget> targets) {
      final soup = triangleSoup(<Vector3>[p0, p1, p2, p0, p2, p3], <int>[
        0,
        1,
        2,
        3,
        4,
        5,
      ]);
      return MeshData(
        layout: soup.layout,
        vertices: soup.vertices,
        indices: soup.indices,
        morphTargets: targets,
      );
    }

    test('no morph targets means no shape keys', () {
      final (_, _, shapeKeys) = importMeshData(quadWithTargets(const <MorphTarget>[]));
      expect(shapeKeys, isEmpty);
    });

    test(
      'one shape key a target, sized and positioned to the welded mesh, '
      'named from the target when it has one',
      () {
        final lift = Float32List.fromList(<double>[
          for (var i = 0; i < 6; i++) ...<double>[0, 0, 1],
        ]);
        final (mesh, _, shapeKeys) = importMeshData(
          quadWithTargets(<MorphTarget>[
            MorphTarget(vertexCount: 6, positions: lift, name: 'lift'),
          ]),
        );

        expect(mesh.vertexCount, 4);
        expect(shapeKeys, hasLength(1));
        expect(shapeKeys.single.vertexCount, mesh.vertexSlotCount);
        expect(shapeKeys.single.name, 'lift');

        // Every welded corner reads as its own base position plus the
        // uniform lift — checked against the mesh's own positions rather
        // than against p0..p3 directly, so a welded vertex's own final id
        // (not necessarily in p0..p3's own order) is not assumed.
        for (var v = 0; v < mesh.vertexCount; v++) {
          final base = mesh.positionOf(v);
          final shaped = shapeKeys.single.positionOf(v);
          expect(shaped.x, closeTo(base.x, 1e-6));
          expect(shaped.y, closeTo(base.y, 1e-6));
          expect(shaped.z, closeTo(base.z + 1, 1e-6));
        }
      },
    );

    test(
      "a delta that differs corner to corner lands on its own welded "
      'vertex, not a neighbour\'s — source 0 and source 3 both name p0, '
      'and must still agree',
      () {
        // Every corner's own delta, distinguishable by which of p0..p3 it
        // belongs to — a uniform delta (as the test above uses) cannot
        // catch a source/destination index mix-up, since every vertex
        // would read the same value regardless of which index actually
        // drove it. p0 appears at source 0 and source 3, in different
        // triangles, and must land on the identical delta both times: the
        // same welded vertex, the same point.
        final delta = Float32List.fromList(<double>[
          1, 0, 0, // source 0: p0
          0, 1, 0, // source 1: p1
          0, 0, 2, // source 2: p2
          1, 0, 0, // source 3: p0, again
          0, 0, 2, // source 4: p2, again
          3, 3, 3, // source 5: p3
        ]);
        final (mesh, _, shapeKeys) = importMeshData(
          quadWithTargets(<MorphTarget>[MorphTarget(vertexCount: 6, positions: delta)]),
        );
        final key = shapeKeys.single;

        Vector3 deltaAt(Vector3 point) {
          for (var v = 0; v < mesh.vertexCount; v++) {
            if ((mesh.positionOf(v) - point).length < 1e-6) {
              return key.positionOf(v) - mesh.positionOf(v);
            }
          }
          fail('no welded vertex at $point');
        }

        expect(deltaAt(p0).x, closeTo(1, 1e-6));
        expect(deltaAt(p0).y, closeTo(0, 1e-6));
        expect(deltaAt(p0).z, closeTo(0, 1e-6));
        expect(deltaAt(p1).y, closeTo(1, 1e-6));
        expect(deltaAt(p2).z, closeTo(2, 1e-6));
        expect(deltaAt(p3).x, closeTo(3, 1e-6));
        expect(deltaAt(p3).y, closeTo(3, 1e-6));
        expect(deltaAt(p3).z, closeTo(3, 1e-6));
      },
    );

    test(
      'two targets stay independent — neither one\'s own delta leaks into '
      'the other',
      () {
        final lift = Float32List.fromList(<double>[
          for (var i = 0; i < 6; i++) ...<double>[0, 0, 1],
        ]);
        final push = Float32List.fromList(<double>[
          for (var i = 0; i < 6; i++) ...<double>[2, 0, 0],
        ]);
        final (mesh, _, shapeKeys) = importMeshData(
          quadWithTargets(<MorphTarget>[
            MorphTarget(vertexCount: 6, positions: lift, name: 'lift'),
            MorphTarget(vertexCount: 6, positions: push, name: 'push'),
          ]),
        );

        expect(shapeKeys, hasLength(2));
        expect(shapeKeys.map((k) => k.name), <String>['lift', 'push']);
        for (var v = 0; v < mesh.vertexCount; v++) {
          final base = mesh.positionOf(v);
          final lifted = shapeKeys[0].positionOf(v);
          final pushed = shapeKeys[1].positionOf(v);
          expect(lifted.x, closeTo(base.x, 1e-6));
          expect(lifted.z, closeTo(base.z + 1, 1e-6));
          expect(pushed.x, closeTo(base.x + 2, 1e-6));
          expect(pushed.z, closeTo(base.z, 1e-6));
        }
      },
    );

    test('an unnamed target counts its own position rather than sharing '
        'one name', () {
      final zero = Float32List(18);
      final (_, _, shapeKeys) = importMeshData(
        quadWithTargets(<MorphTarget>[
          MorphTarget(vertexCount: 6, positions: zero),
          MorphTarget(vertexCount: 6, positions: zero),
        ]),
      );
      expect(shapeKeys.map((k) => k.name), <String>['shape 1', 'shape 2']);
    });
  });
}
