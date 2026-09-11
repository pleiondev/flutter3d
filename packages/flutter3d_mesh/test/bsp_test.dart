/// `booleanUnion`/`booleanSubtract`/`booleanIntersect`: the BSP boolean
/// algorithm `mesh-47`'s own row names, checked against volumes worked out
/// independently of this file's own code.
///
///     dart test test/bsp_test.dart
library;

import 'dart:math' as math;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

EditMesh translatedCuboid(Vector3 offset, {Vector3? size}) {
  final mesh = EditMesh.cuboid(size: size);
  mesh.beginStep();
  for (var v = 0; v < mesh.vertexSlotCount; v++) {
    if (!mesh.isVertexAlive(v)) continue;
    mesh.moveVertex(v, mesh.positionOf(v) + offset);
  }
  mesh.endStep();
  return mesh;
}

/// Offset on all three axes, deliberately: two cubes offset along one axis
/// alone share the other two axes' own extents exactly, which makes every
/// one of their non-touching faces *also* exactly coplanar with the other
/// solid's own face in the same plane (both cubes' bottom faces sit at the
/// same z, for instance, purely because neither cube was moved in z) — a
/// degenerate case this file wants to test on purpose, not stumble into by
/// accident in a test meant to check an ordinary overlap. See the group
/// below named for exactly this case.
const _ordinaryOffset = (0.5, 0.3, 0.2);

void main() {
  group('booleanUnion: cube ∪ cube, volume worked out analytically', () {
    test('two unit cubes overlapping off-axis, sharing no face\'s plane', () {
      // A spans [-0.5, 0.5]³. B, shifted by (0.5, 0.3, 0.2), spans
      // [0, 1] × [-0.2, 0.8] × [-0.3, 0.7]. The overlap is
      // [0, 0.5] × [-0.2, 0.5] × [-0.3, 0.5] — 0.5 × 0.7 × 0.8 = 0.28 —
      // worked out here, not by running the code under test a second time;
      // union = 1 + 1 - 0.28 = 1.72.
      final (dx, dy, dz) = _ordinaryOffset;
      final a = EditMesh.cuboid();
      final b = translatedCuboid(Vector3(dx, dy, dz));

      final result = booleanUnion(a, b);
      expect(result, isNotNull);
      result!.mesh.validate();

      // Volume, not topology: the library doc comment says why a T-junction
      // can leave this open in places `validate()` itself does not object
      // to (an unpaired half-edge is a boundary, not an inconsistency), and
      // why the volume stays correct regardless.
      expect(result.mesh.signedVolume, closeTo(1.72, 1e-6));
    });

    test('two cubes that do not touch: volume is just the sum', () {
      final a = EditMesh.cuboid();
      final b = translatedCuboid(Vector3(10, 0, 0));

      final result = booleanUnion(a, b);
      expect(result, isNotNull);
      expect(result!.mesh.signedVolume, closeTo(2.0, 1e-6));
    });
  });

  group('booleanSubtract: cube − sphere, within 1%', () {
    test('a sphere fully inside a cube cuts out close to its own volume', () {
      // A cube of half-size 1 (volume 8) with a radius-0.5 sphere (volume
      // 4/3 π 0.5³ ≈ 0.5236) cut from its centre — the sphere's own
      // tessellation makes the faceted mesh's volume a little less than the
      // ideal sphere's, which is exactly why the acceptance asks for 1%
      // rather than an exact match.
      final cube = EditMesh.cuboid(size: Vector3(2, 2, 2));
      final sphere = const ParametricSphere(
        radius: 0.5,
        segments: 32,
        rings: 16,
      ).toEditMesh();

      final result = booleanSubtract(cube, sphere);
      expect(result, isNotNull);
      result!.mesh.validate();

      const sphereVolume = 4 / 3 * math.pi * 0.5 * 0.5 * 0.5;
      const expected = 8.0 - sphereVolume;
      final relativeError =
          (result.mesh.signedVolume - expected).abs() / expected;
      // Mutation: swap a sign in the subtract recipe's own invert calls, and
      // this either comes back near zero (an empty shell) or near 8.5
      // (the sphere added rather than removed) — nowhere near a 1% band.
      expect(relativeError, lessThan(0.01));
    });
  });

  group('booleanIntersect', () {
    test('two cubes offset off-axis: the overlap alone', () {
      final (dx, dy, dz) = _ordinaryOffset;
      final a = EditMesh.cuboid();
      final b = translatedCuboid(Vector3(dx, dy, dz));

      final result = booleanIntersect(a, b);
      expect(result, isNotNull);
      result!.mesh.validate();
      // The same 0.28 overlap the union test above works out by hand.
      expect(result.mesh.signedVolume, closeTo(0.28, 1e-6));
    });

    test('two cubes that do not touch: nothing to intersect', () {
      final a = EditMesh.cuboid();
      final b = translatedCuboid(Vector3(10, 0, 0));
      final result = booleanIntersect(a, b);
      // Null is the honest answer for two solids that share no volume at
      // all, not a mesh of zero faces pretending to be one.
      expect(result, isNull);
    });
  });

  group('a coplanar face warns rather than failing', () {
    test('two cubes sharing a face exactly', () {
      // Adjacent along x with every other extent identical: not just the
      // touching faces but all six of each cube's own faces sit in the same
      // plane as the corresponding face of the other. This is the case the
      // library doc comment names directly — a genuine, known source of
      // imprecision in the classic algorithm, not a bug this file works
      // around — so what this test asks for is the acceptance's own literal
      // wording: it warns and it does not crash, not that the geometry it
      // hands back is exact.
      final a = EditMesh.cuboid(size: Vector3(1, 1, 1));
      final b = translatedCuboid(Vector3(1, 0, 0));

      final result = booleanUnion(a, b);
      expect(result, isNotNull);
      result!.mesh.validate();

      // Mutation: never increment `CsgTolerance.coplanarCount`, and this
      // pair — which shares every face's own plane, not just a touching
      // edge — would still say nothing happened.
      expect(result.warnings, isNotEmpty);
      expect(result.mesh.signedVolume, greaterThan(0));
    });
  });

  group('what it refuses', () {
    test('more triangles between the two inputs than maxPolygons allows', () {
      final a = EditMesh.cuboid();
      final b = translatedCuboid(Vector3(0.5, 0, 0));
      final result = booleanUnion(a, b, maxPolygons: 1);
      expect(result, isNull);
    });
  });
}
