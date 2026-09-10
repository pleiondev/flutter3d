/// The primitives, built as quads and held to the engine's own answer.
///
/// **The oracle is the shape next door.** Every one of these has an engine
/// `Shape` with the same parameters, and the two describe the same surface — so
/// the volume, the bounds and the texture coordinates have to agree, whatever
/// the two do differently about vertices and triangles. Where they are meant to
/// differ, the test says which and why.
library;

import 'dart:math' as math;

import 'package:flutter3d_geometry/flutter3d_geometry.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// The six shapes, with the engine's defaults and with parameters nobody would
/// have hard-coded.
List<ParametricShape> everyShape() => <ParametricShape>[
  ParametricCuboid(),
  ParametricCuboid(size: Vector3(0.3, 2.5, 1.1)),
  const ParametricPlane(),
  const ParametricPlane(
    width: 3,
    depth: 0.7,
    widthSegments: 3,
    depthSegments: 2,
  ),
  const ParametricCylinder(segments: 16),
  const ParametricCylinder(
    radiusTop: 0.2,
    radiusBottom: 0.9,
    height: 2.2,
    segments: 7,
  ),
  const ParametricSphere(segments: 12, rings: 6),
  const ParametricSphere(radius: 1.4, segments: 9, rings: 5),
  const ParametricTorus(segments: 12, tubeSegments: 6),
  const ParametricTorus(
    radius: 1.2,
    tubeRadius: 0.3,
    segments: 9,
    tubeSegments: 5,
  ),
  ParametricLathe(
    profile: <Vector2>[
      Vector2(0, -0.5),
      Vector2(0.4, -0.2),
      Vector2(0.2, 0.1),
      Vector2(0.5, 0.5),
    ],
    segments: 10,
  ),
  ParametricLathe(
    profile: <Vector2>[Vector2(0.3, -0.4), Vector2(0.3, 0.4)],
    segments: 5,
    sweepAngle: math.pi,
  ),
];

/// The bounding box of an editable mesh.
Aabb3 boundsOf(EditMesh mesh) {
  final low = Vector3.all(double.infinity);
  final high = Vector3.all(double.negativeInfinity);
  final at = Vector3.zero();
  for (var vertex = 0; vertex < mesh.vertexSlotCount; vertex++) {
    if (!mesh.isVertexAlive(vertex)) continue;
    mesh.positionOf(vertex, at);
    Vector3.min(low, at, low);
    Vector3.max(high, at, high);
  }
  return Aabb3.minMax(low, high);
}

/// A number as five places, with a value that rounds to nothing written as a
/// plain zero — `-1.2e-16` and `0` are the same point, and the sign of a zero
/// is exactly the kind of difference a comparison of strings would invent.
String round(double value) =>
    (value.abs() < 5e-6 ? 0.0 : value).toStringAsFixed(5);

/// Every (position, texcoord) pair of a drawable mesh, rounded.
Set<String> pairsOf(MeshData mesh) {
  final stride = mesh.layout.floatsPerVertex;
  final positionAt = mesh.layout.floatOffsetOf(VertexLayout.position.name);
  final uvAt = mesh.layout.floatOffsetOf(VertexLayout.texcoord.name);
  return <String>{
    for (var row = 0; row < mesh.vertexCount; row++)
      <String>[
        for (var i = 0; i < 3; i++)
          round(mesh.vertices[row * stride + positionAt + i]),
        for (var i = 0; i < 2; i++)
          round(mesh.vertices[row * stride + uvAt + i]),
      ].join(','),
  };
}

/// Every (position, texcoord) pair an editable mesh's corners carry.
Set<String> cornerPairsOf(EditMesh mesh) {
  final found = <String>{};
  for (var face = 0; face < mesh.faceSlotCount; face++) {
    if (!mesh.isFaceAlive(face)) continue;
    mesh.forEachHalfEdge(face, (int half) {
      final at = mesh.positionOf(mesh.originOf(half));
      final uv = mesh.uvOf(half);
      found.add(
        <String>[
          round(at.x),
          round(at.y),
          round(at.z),
          round(uv.x),
          round(uv.y),
        ].join(','),
      );
    });
  }
  return found;
}

/// The triangles of a drawable mesh, as sorted corner triples, with the ones
/// that have no area left out.
Set<String> trianglesOf(MeshData mesh) {
  final stride = mesh.layout.floatsPerVertex;
  final at = mesh.layout.floatOffsetOf(VertexLayout.position.name);
  Vector3 corner(int row) => Vector3(
    mesh.vertices[row * stride + at],
    mesh.vertices[row * stride + at + 1],
    mesh.vertices[row * stride + at + 2],
  );

  final found = <String>{};
  for (var i = 0; i + 2 < mesh.indices.length; i += 3) {
    final a = corner(mesh.indices[i]);
    final b = corner(mesh.indices[i + 1]);
    final c = corner(mesh.indices[i + 2]);
    if ((b - a).cross(c - a).length < 1e-9) continue;
    found.add(
      (<String>[
        for (final it in <Vector3>[a, b, c])
          <String>[round(it.x), round(it.y), round(it.z)].join(','),
      ]..sort()).join('|'),
    );
  }
  return found;
}

void main() {
  group('a cylinder', () {
    test('is a wall of quads between two n-gon caps', () {
      final mesh = const ParametricCylinder(segments: 16).toEditMesh();

      // Sixteen walls and two caps, and the caps are one face each rather than
      // sixteen triangles somebody has to select together.
      expect(mesh.faceCount, 18);
      expect(mesh.vertexCount, 32);
      expect(mesh.eulerCharacteristic, 2);
      expect(mesh.signedVolume, greaterThan(0));
      mesh.validate();

      var quads = 0;
      var caps = 0;
      for (var face = 0; face < mesh.faceSlotCount; face++) {
        if (mesh.valencyOf(face) == 4) quads++;
        if (mesh.valencyOf(face) == 16) caps++;
      }
      expect(quads, 16);
      expect(caps, 2);
      // Mutation: put a vertex in the middle of a flat cap anyway, and a
      // cylinder comes out with two points no face reaches.
      expect(MeshChecks(mesh).isolatedVertices(), isNull);
    });

    test('its ring of uprights closes', () {
      final mesh = const ParametricCylinder(segments: 16).toEditMesh();
      // A wall quad, and the upright of it that runs between the two rims.
      var wall = EditMesh.none;
      var upright = EditMesh.none;
      for (
        var face = 0;
        face < mesh.faceSlotCount && wall == EditMesh.none;
        face++
      ) {
        if (mesh.valencyOf(face) != 4) continue;
        wall = face;
        mesh.forEachHalfEdge(face, (int half) {
          final from = mesh.positionOf(mesh.originOf(half));
          final to = mesh.positionOf(mesh.originOf(mesh.nextOf(half)));
          if ((from.y - to.y).abs() > 0.5) upright = half;
        });
      }

      final ring = Selection.edgeRing(mesh, upright);

      // Sixteen, which is the ring going all the way round and coming back —
      // and what a loop cut across the wall needs.
      expect(ring.length, 16);
    });

    test('the rim is sharp, so the cap does not bleed into the wall', () {
      final mesh = const ParametricCylinder(segments: 16).toEditMesh();
      // Asked with a threshold wide enough to smooth a right angle, so the
      // flag is the only thing left holding the rim apart. At the default
      // thirty degrees the angle between a cap and a wall breaks them anyway,
      // and a test there could not tell the flag from nothing.
      final normals = MeshNormals()
        ..build(mesh, smoothAngle: 100 * degrees2Radians);

      // A corner on the rim, seen from the cap and from the wall.
      var cap = EditMesh.none;
      for (var face = 0; face < mesh.faceSlotCount; face++) {
        if (mesh.valencyOf(face) == 16) cap = face;
      }
      var onCap = EditMesh.none;
      mesh.forEachHalfEdge(cap, (int half) => onCap = half);
      final onWall = mesh.twinOf(onCap);

      // Mutation: leave the rim unmarked, and the two corners average into one
      // normal — a cylinder whose cap curves into its side, which is the whole
      // reason the engine repeats the profile point there.
      expect(
        normals.cornerNormal(onCap).dot(normals.cornerNormal(onWall)),
        lessThan(0.1),
      );
      // The cap's own corner looks straight along the axis.
      expect(normals.cornerNormal(onCap).y.abs(), closeTo(1, 1e-5));
    });
  });

  group('every shape', () {
    test('validates, encloses what the engine says, and fills its texture', () {
      for (final shape in everyShape()) {
        final mesh = shape.toEditMesh();
        final engine = shape.drawn.build();
        final reason = shape.name;

        mesh.validate();
        expect(
          mesh.hasLayer(MeshDomain.corner, MeshAttribute.uv0),
          isTrue,
          reason: '$reason has no texture coordinates',
        );

        // Mutation: build the lathe rows without the engine's axis snapping,
        // and a sphere's pole comes out as a ring of hairs a micron wide — the
        // volume drifts and the bounds grow.
        expect(
          mesh.signedVolume,
          closeTo(engine.signedVolume(), 1e-4),
          reason: reason,
        );
        final bounds = boundsOf(mesh);
        final theirs = engine.computeBounds();
        for (var axis = 0; axis < 3; axis++) {
          expect(
            bounds.min[axis],
            closeTo(theirs.min[axis], 1e-5),
            reason: '$reason min $axis',
          );
          expect(
            bounds.max[axis],
            closeTo(theirs.max[axis], 1e-5),
            reason: '$reason max $axis',
          );
        }
      }
    });

    test('every corner it carries is one the engine carries too', () {
      for (final shape in everyShape()) {
        final ours = cornerPairsOf(shape.toEditMesh());
        final theirs = pairsOf(shape.drawn.build());

        // A subset rather than the same set: the engine has a vertex in the
        // middle of every flat cap and this does not, and it has the seam
        // column twice where this welds it. What must hold is that no corner
        // here carries a texture coordinate the engine would not — which is
        // the thing that decides whether a texture authored for one fits the
        // other. Mutation: take the arc length over the merged rows rather
        // than over the engine's, and a cylinder's cap and wall swap the run
        // of texture between them.
        expect(
          ours.difference(theirs),
          isEmpty,
          reason: '${shape.name} invented a corner',
        );
      }
    });
  });

  group('against the engine, corner for corner', () {
    test('a box is the same twenty-four vertices and the same triangles', () {
      final mesh = ParametricCuboid().toEditMesh();
      final ours = mesh.toMeshData();
      final theirs = CuboidShape().build();

      // Twenty-four, because a corner of a box carries three normals — which
      // is what the layout plan works out for itself from the flags.
      expect(ours.vertexCount, 24);
      expect(ours.triangleCount, 12);
      expect(trianglesOf(ours), trianglesOf(theirs));
      expect(pairsOf(ours), pairsOf(theirs));
    });

    test('a sheet of quads is the same triangles as the engine builds', () {
      const shape = ParametricPlane(
        width: 3,
        depth: 0.7,
        widthSegments: 3,
        depthSegments: 2,
      );

      expect(
        trianglesOf(shape.toEditMesh().toMeshData()),
        trianglesOf(shape.drawn.build()),
      );
    });

    test('a torus closes both ways round', () {
      final mesh = const ParametricTorus(
        segments: 12,
        tubeSegments: 6,
      ).toEditMesh();

      // Every face four-sided, nothing on a rim, and χ of zero — which is what
      // says the tube closed and the sweep closed. Mutation: leave the closing
      // repeat as a row of its own, and the tube is a strip with two rims.
      expect(mesh.faceCount, 72);
      expect(mesh.vertexCount, 72);
      expect(mesh.eulerCharacteristic, 0);
      expect(MeshChecks(mesh).boundaryEdges(), isNull);
      mesh.validate();

      // The tube's texture runs from zero to one and the seam carries both
      // ends, which is the one place a welded ring needs two coordinates for
      // one vertex. Mutation: give the seam the row's own `v` rather than the
      // one the arc length ran to, and the texture wraps back to zero a
      // segment early — every corner is still one the engine has, so only
      // asking for the seam itself finds it.
      final vs = <double>{};
      for (var face = 0; face < mesh.faceSlotCount; face++) {
        mesh.forEachHalfEdge(face, (int half) => vs.add(mesh.uvOf(half).y));
      }
      expect(vs, contains(0.0));
      expect(vs.any((double it) => (it - 1).abs() < 1e-6), isTrue);
    });

    test('a sphere keeps its poles as fans rather than flattening them', () {
      final mesh = const ParametricSphere(segments: 12, rings: 6).toEditMesh();

      // Twelve triangles at each pole and quads between the rings — a disc
      // there would be a sphere with two flat ends. Mutation: treat every axis
      // band as a cap, and the volume drops by the two spherical caps.
      var triangles = 0;
      for (var face = 0; face < mesh.faceSlotCount; face++) {
        if (mesh.valencyOf(face) == 3) triangles++;
      }
      expect(triangles, 24);
      expect(mesh.faceCount, 24 + 12 * 4);
      expect(MeshChecks(mesh).boundaryEdges(), isNull);
      mesh.validate();
    });

    test('a cone has one cap and a tip', () {
      final mesh = const ParametricCylinder(
        radiusTop: 0,
        segments: 8,
      ).toEditMesh();

      expect(mesh.signedVolume, greaterThan(0));
      // Eight walls up to the tip, and one cap under them.
      expect(mesh.faceCount, 9);
      expect(MeshChecks(mesh).boundaryEdges(), isNull);
      mesh.validate();
    });

    test('a lathe that sweeps half way round is left open', () {
      final mesh = ParametricLathe(
        profile: <Vector2>[Vector2(0.3, -0.4), Vector2(0.3, 0.4)],
        segments: 5,
        sweepAngle: math.pi,
      ).toEditMesh();

      // Five quads round half a cylinder — and it is a strip, so it has a rim.
      // Mutation: weld the seam whatever the sweep is, and half a tube comes
      // back closed.
      expect(mesh.faceCount, 5);
      expect(MeshChecks(mesh).boundaryEdges(), isNotNull);
      mesh.validate();
    });
  });
}
