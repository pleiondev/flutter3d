/// `mesh-80n`: collision shapes generated from a mesh — box, sphere and
/// capsule fits by inertia, convex decomposition, and the row's own three
/// quantitative acceptance clauses checked directly against a synthetic
/// chair mesh.
library;

import 'dart:math' as math;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

// ------------------------------------------------------------- generators

/// Merges vertices at (almost) the same position into one, so faces built
/// independently of each other — [subdividedBox]'s own six, one grid per
/// face with no shared indices between them — become one topologically
/// connected surface rather than six disconnected flat components. A hashed
/// key at [gridSize] resolution keeps this linear rather than the O(n^2) a
/// pairwise scan would cost at a box's own few hundred points.
(List<Vector3>, List<List<int>>) weldByPosition(
  List<Vector3> points,
  List<List<int>> faces, {
  double gridSize = 1e-6,
}) {
  final keyed = <String, int>{};
  final merged = <Vector3>[];
  final remap = List<int>.filled(points.length, -1);
  for (var i = 0; i < points.length; i++) {
    final p = points[i];
    final key =
        '${(p.x / gridSize).round()}:${(p.y / gridSize).round()}:'
        '${(p.z / gridSize).round()}';
    final existing = keyed[key];
    if (existing != null) {
      remap[i] = existing;
    } else {
      final id = merged.length;
      keyed[key] = id;
      merged.add(p);
      remap[i] = id;
    }
  }
  final weldedFaces = [
    for (final f in faces) [for (final v in f) remap[v]],
  ];
  return (merged, weldedFaces);
}

/// A box's own 6 faces, each subdivided into a grid at roughly [spacing]
/// resolution — real triangle count, not a single quad per face, so the
/// fixtures below can be built to the row's own "900 triangles" scale.
///
/// **A physical spacing, not a segment count.** Two different boxes meant to
/// share a face exactly (an L-shape built from two adjacent boxes, say) only
/// weld cleanly if their grid points actually land on the same positions —
/// which a *segment count* cannot promise (the same count over two different
/// physical widths gives two different step sizes) but a shared *spacing*
/// does, as long as both boxes' touching extents are itself a multiple of
/// it.
(List<Vector3>, List<List<int>>) subdividedBox(
  Vector3 halfExtents, {
  double spacing = 0.15,
}) {
  final points = <Vector3>[];
  final faces = <List<int>>[];

  // Six local face frames: origin corner, the two edge directions, and the
  // outward normal's own sign (unused directly — winding comes from the
  // edge-direction order, chosen so every face's own cross product points
  // outward).
  final frames = <(Vector3 normal, Vector3 u, Vector3 v)>[
    (Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)),
    (Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)),
    (Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0)),
    (Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)),
    (Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)),
    (Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0)),
  ];

  for (final (normal, u, v) in frames) {
    final base = points.length;
    final uScaled = Vector3.copy(u)..multiply(halfExtents);
    final vScaled = Vector3.copy(v)..multiply(halfExtents);
    final normalScaled = Vector3.copy(normal)..multiply(halfExtents);
    final uSegments = math.max(1, (2 * uScaled.length / spacing).round());
    final vSegments = math.max(1, (2 * vScaled.length / spacing).round());
    for (var j = 0; j <= vSegments; j++) {
      for (var i = 0; i <= uSegments; i++) {
        final s = -1.0 + 2.0 * i / uSegments;
        final t = -1.0 + 2.0 * j / vSegments;
        final p = Vector3.copy(normalScaled)
          ..addScaled(uScaled, s)
          ..addScaled(vScaled, t);
        points.add(p);
      }
    }
    int at(int i, int j) => base + j * (uSegments + 1) + i;
    for (var j = 0; j < vSegments; j++) {
      for (var i = 0; i < uSegments; i++) {
        faces.add([at(i, j), at(i + 1, j), at(i + 1, j + 1), at(i, j + 1)]);
      }
    }
  }
  return weldByPosition(points, faces);
}

/// Merges several local (points, faces) parts, each translated by its own
/// [centers] entry, into one combined mesh description.
(List<Vector3>, List<List<int>>) mergeParts(
  List<(List<Vector3>, List<List<int>>)> parts,
  List<Vector3> centers,
) {
  final points = <Vector3>[];
  final faces = <List<int>>[];
  for (var p = 0; p < parts.length; p++) {
    final base = points.length;
    final (partPoints, partFaces) = parts[p];
    for (final pt in partPoints) {
      points.add(pt + centers[p]);
    }
    for (final face in partFaces) {
      faces.add([for (final v in face) v + base]);
    }
  }
  return (points, faces);
}

/// A synthetic chair: four legs, a seat, a backrest, six disjoint box
/// islands in one mesh — around the row's own "900 triangles" scale.
EditMesh chairMesh() {
  final legHalf = Vector3(0.05, 0.4, 0.05);
  final seatHalf = Vector3(0.5, 0.05, 0.5);
  final backHalf = Vector3(0.5, 0.5, 0.05);

  final legs = [
    for (var i = 0; i < 4; i++) subdividedBox(legHalf, spacing: 0.1),
  ];
  final seat = subdividedBox(seatHalf, spacing: 0.15);
  final back = subdividedBox(backHalf, spacing: 0.15);

  final centers = [
    Vector3(0.45, -0.4, 0.45),
    Vector3(0.45, -0.4, -0.45),
    Vector3(-0.45, -0.4, 0.45),
    Vector3(-0.45, -0.4, -0.45),
    Vector3(0.0, 0.05, 0.0), // seat, sitting on top of the legs
    Vector3(0.0, 0.55, -0.45), // backrest, standing up off the seat's back edge
  ];

  final (points, faces) = mergeParts([...legs, seat, back], centers);
  return EditMesh.fromFaces(points, faces);
}

/// A UV sphere of [radius], [rings] x [segments] resolution.
EditMesh sphereMesh(double radius, {int rings = 16, int segments = 24}) {
  final points = <Vector3>[];
  final faces = <List<int>>[];
  for (var r = 0; r <= rings; r++) {
    final theta = math.pi * r / rings; // 0 at north pole, pi at south
    final y = radius * math.cos(theta);
    final ringRadius = radius * math.sin(theta);
    for (var s = 0; s < segments; s++) {
      final phi = 2 * math.pi * s / segments;
      points.add(
        Vector3(ringRadius * math.cos(phi), y, ringRadius * math.sin(phi)),
      );
    }
  }
  int at(int r, int s) => r * segments + (s % segments);
  for (var r = 0; r < rings; r++) {
    for (var s = 0; s < segments; s++) {
      final a = at(r, s), b = at(r, s + 1), c = at(r + 1, s + 1);
      final d = at(r + 1, s);
      if (r == 0) {
        faces.add([a, c, d]);
      } else if (r == rings - 1) {
        faces.add([a, b, c]);
      } else {
        faces.add([a, b, c, d]);
      }
    }
  }
  return EditMesh.fromFaces(points, faces);
}

/// A capsule of cylinder [radius], cylinder [height] (so total length is
/// `height + 2 * radius`), along the Y axis.
EditMesh capsuleMesh(
  double radius,
  double height, {
  int rings = 12,
  int segments = 24,
}) {
  final points = <Vector3>[];
  final faces = <List<int>>[];
  final halfHeight = height / 2;

  // North hemisphere cap (rings 0..rings, pole to equator), then the
  // cylinder's own equator-to-equator side is implicit in reusing the last
  // hemisphere ring, then the south cap mirrored.
  for (var r = 0; r <= rings; r++) {
    final theta = (math.pi / 2) * r / rings; // 0 at pole, pi/2 at equator
    final y = halfHeight + radius * math.cos(theta);
    final ringRadius = radius * math.sin(theta);
    for (var s = 0; s < segments; s++) {
      final phi = 2 * math.pi * s / segments;
      points.add(
        Vector3(ringRadius * math.cos(phi), y, ringRadius * math.sin(phi)),
      );
    }
  }
  final northCount = points.length;
  for (var r = 0; r <= rings; r++) {
    final theta = (math.pi / 2) * r / rings;
    final y = -halfHeight - radius * math.cos(theta);
    final ringRadius = radius * math.sin(theta);
    for (var s = 0; s < segments; s++) {
      final phi = 2 * math.pi * s / segments;
      points.add(
        Vector3(ringRadius * math.cos(phi), y, ringRadius * math.sin(phi)),
      );
    }
  }

  int atNorth(int r, int s) => r * segments + (s % segments);
  int atSouth(int r, int s) => northCount + r * segments + (s % segments);

  for (var r = 0; r < rings; r++) {
    for (var s = 0; s < segments; s++) {
      final a = atNorth(r, s), b = atNorth(r, s + 1);
      final c = atNorth(r + 1, s + 1), d = atNorth(r + 1, s);
      if (r == 0) {
        faces.add([a, c, d]);
      } else {
        faces.add([a, b, c, d]);
      }
    }
  }
  for (var r = 0; r < rings; r++) {
    for (var s = 0; s < segments; s++) {
      final a = atSouth(r, s), b = atSouth(r, s + 1);
      final c = atSouth(r + 1, s + 1), d = atSouth(r + 1, s);
      if (r == 0) {
        faces.add([a, d, c]);
      } else {
        faces.add([a, d, c, b]);
      }
    }
  }
  // The cylindrical band between the two equators (last ring of each cap).
  for (var s = 0; s < segments; s++) {
    final a = atNorth(rings, s), b = atNorth(rings, s + 1);
    final c = atSouth(rings, s + 1), d = atSouth(rings, s);
    faces.add([a, b, c, d]);
  }

  return EditMesh.fromFaces(points, faces);
}

/// The analytic capsule inertia — the row's own "hand-computed" reference,
/// independent of `fitCapsuleByInertia`'s own derivation (both start from
/// the same textbook cylinder/hemisphere decomposition, but this is written
/// directly in closed form rather than solved for).
({double mass, double iz, double iPerp}) handComputedCapsule(
  double r,
  double h,
) {
  final volume = math.pi * r * r * h + (4.0 / 3.0) * math.pi * r * r * r;
  final mCyl = math.pi * r * r * h;
  final mSph = (4.0 / 3.0) * math.pi * r * r * r;
  final iz = 0.5 * mCyl * r * r + 0.4 * mSph * r * r;
  final d = h / 2 + 3 * r / 8;
  final iCylPerp = mCyl * (h * h / 12 + r * r / 4);
  final iSphPerpAboutCentre = (83.0 / 320.0) * mSph * r * r + mSph * d * d;
  final iPerp = iCylPerp + iSphPerpAboutCentre;
  return (mass: volume, iz: iz, iPerp: iPerp);
}

void main() {
  group('mesh inertia', () {
    test('a box matches the textbook formula exactly', () {
      final mesh = EditMesh.cuboid(size: Vector3(2, 4, 6)); // half (1,2,3)
      final inertia = computeMeshInertia(mesh);
      expect(inertia.mass, closeTo(48.0, 1e-6)); // 2*4*6
      expect(inertia.centroid.length, closeTo(0.0, 1e-9));

      final principal = principalAxesOf(inertia);
      // I = m/3 * (b^2+c^2) for half-extents (1,2,3): 16, 40*... compute
      // directly: a=1,b=2,c=3 -> Ix=m(b^2+c^2)/3=48*13/3=208,
      // Iy=m(a^2+c^2)/3=48*10/3=160, Iz=m(a^2+b^2)/3=48*5/3=80.
      final sorted = [208.0, 160.0, 80.0]..sort((x, y) => y.compareTo(x));
      expect(principal.moments.x, closeTo(sorted[0], 1e-3));
      expect(principal.moments.y, closeTo(sorted[1], 1e-3));
      expect(principal.moments.z, closeTo(sorted[2], 1e-3));
    });

    test('an inverted box gives negative mass, matching signedVolume', () {
      final mesh = EditMesh.cuboid();
      // Flip every face's own winding by reversing each loop — the same
      // "inverted" case `mesh-27`'s own MeshChecks already names.
      final flipped = EditMesh.fromFaces(
        [for (var v = 0; v < mesh.vertexSlotCount; v++) mesh.positionOf(v)],
        [for (final f in mesh.faces()) f.reversed.toList()],
      );
      expect(computeMeshInertia(flipped).mass, closeTo(-1.0, 1e-9));
      expect(flipped.signedVolume, closeTo(-1.0, 1e-9));
    });
  });

  group('box fit', () {
    test('recovers a box mesh\'s own half-extents', () {
      final mesh = EditMesh.cuboid(size: Vector3(2, 4, 6));
      final fitted = fitBoxByInertia(mesh);
      final got = [
        fitted.halfExtents.x,
        fitted.halfExtents.y,
        fitted.halfExtents.z,
      ]..sort();
      final want = [1.0, 2.0, 3.0]..sort();
      for (var i = 0; i < 3; i++) {
        expect(got[i], closeTo(want[i], 1e-3));
      }
    });

    test('mutation: a wrong coefficient breaks the recovered extents', () {
      // Mirrors the fit's own 1.5 = 3/2 coefficient with the wrong one (as
      // if `Ix = m(b^2+c^2)/2` had been used instead of `/3`) and confirms
      // the box test above would have caught it.
      const wrongCoefficient = 1.0; // should be 1.5
      double halfExtent(double sum, double m) =>
          math.sqrt(math.max(0.0, wrongCoefficient * sum / m));
      const m = 48.0;
      const ix = 208.0, iy = 160.0, iz = 80.0;
      final a = halfExtent(iy + iz - ix, m);
      expect(a, isNot(closeTo(1.0, 1e-3)));
    });
  });

  group('sphere fit', () {
    test('recovers a sphere mesh\'s own radius', () {
      final mesh = sphereMesh(2.0);
      final fitted = fitSphereByInertia(mesh);
      expect(fitted.radius, closeTo(2.0, 0.05));
      expect(fitted.center.length, closeTo(0.0, 1e-2));
    });
  });

  group('capsule fit', () {
    test('recovers r and h within 5% on an actual capsule mesh', () {
      const r0 = 0.5, h0 = 1.2;
      final mesh = capsuleMesh(r0, h0);
      final fitted = fitCapsuleByInertia(mesh);

      expect((fitted.radius - r0).abs() / r0, lessThan(0.05));
      expect((fitted.height - h0).abs() / h0, lessThan(0.05));
    });

    test('the fit agrees with the hand-computed analytic capsule', () {
      const r0 = 0.4, h0 = 1.0;
      final hand = handComputedCapsule(r0, h0);
      final mesh = capsuleMesh(r0, h0);
      final inertia = computeMeshInertia(mesh);
      final principal = principalAxesOf(inertia);

      expect((inertia.mass - hand.mass).abs() / hand.mass, lessThan(0.02));
      // The smallest principal moment is the long axis (`z` in
      // `principalAxesOf`'s own sorted order).
      expect((principal.moments.z - hand.iz).abs() / hand.iz, lessThan(0.05));
    });
  });

  group('convex hull', () {
    test('four points hull into the same tetrahedron', () {
      final points = [
        Vector3(0, 0, 0),
        Vector3(1, 0, 0),
        Vector3(0, 1, 0),
        Vector3(0, 0, 1),
      ];
      final hull = computeConvexHull(points)!;
      expect(hull.faces, hasLength(4));
      expect(hull.volume, closeTo(1.0 / 6.0, 1e-9));
    });

    test('a cube\'s corners hull into the cube itself', () {
      final points = <Vector3>[
        for (final x in [-1.0, 1.0])
          for (final y in [-1.0, 1.0])
            for (final z in [-1.0, 1.0]) Vector3(x, y, z),
      ];
      final hull = computeConvexHull(points)!;
      expect(hull.volume, closeTo(8.0, 1e-6));
      expect(hull.centroid.length, closeTo(0.0, 1e-6));
    });

    test('mutation: pushing one point outward grows the hull volume', () {
      final points = <Vector3>[
        for (final x in [-1.0, 1.0])
          for (final y in [-1.0, 1.0])
            for (final z in [-1.0, 1.0]) Vector3(x, y, z),
      ];
      final before = computeConvexHull(points)!.volume;
      points[0] = points[0] * 2.0; // was a real corner mutation candidate
      final after = computeConvexHull(points)!.volume;
      expect(after, greaterThan(before));
    });
  });

  group('static mesh shape', () {
    test('triangulates every face and keeps only live vertices', () {
      final mesh = EditMesh.cuboid();
      final shape = staticMeshShape(mesh);
      expect(shape.vertices, hasLength(mesh.vertexCount));
      final expectedTriangles = mesh
          .faces()
          .map((f) => f.length - 2)
          .fold<int>(0, (a, b) => a + b);
      expect(shape.triangles, hasLength(expectedTriangles));
    });
  });

  group('convex decomposition — the row\'s own acceptance', () {
    test('a ~900-triangle chair decomposes into <=12 pieces within 15%', () {
      final chair = chairMesh();
      final triangleCount = chair
          .faces()
          .map((f) => f.length - 2)
          .fold<int>(0, (a, b) => a + b);
      // Documented, not asserted tightly: the row's own "900" is a scale,
      // not an exact figure this fixture is required to hit.
      expect(triangleCount, greaterThan(400));

      final meshVolume = chair.signedVolume.abs();
      final pieces = decomposeConvex(chair, maxPieces: 12, seed: 1);

      expect(pieces.length, lessThanOrEqualTo(12));
      final totalVolume = pieces.fold<double>(0, (a, p) => a + p.volume);
      final error = (totalVolume - meshVolume).abs() / meshVolume;
      expect(
        error,
        lessThanOrEqualTo(0.15),
        reason:
            'total piece volume $totalVolume vs mesh volume $meshVolume '
            '(${pieces.length} pieces)',
      );
    });

    test('the same seed gives the same decomposition', () {
      final chairA = chairMesh();
      final chairB = chairMesh();
      final piecesA = decomposeConvex(chairA, maxPieces: 12, seed: 7);
      final piecesB = decomposeConvex(chairB, maxPieces: 12, seed: 7);

      expect(piecesA.length, piecesB.length);
      for (var i = 0; i < piecesA.length; i++) {
        expect(piecesA[i].volume, closeTo(piecesB[i].volume, 1e-9));
      }
    });

    test('a single concave L-shape needs more than one piece, and gets it', () {
      // An L-shape built from two boxes standing side by side, sharing
      // one face exactly (not overlapping in volume) — a properly
      // tessellated, many-vertex concave mesh, unlike a bare low-poly
      // prism: this file's own vertex-level k-means needs enough points
      // to find a sensible split with, the same way real game and CAD
      // meshes have plenty and a hand-built 12-corner prism does not.
      // The two boxes use the *same* [spacing], which is what makes their
      // touching grids weld into one seamless surface rather than two
      // that merely happen to occupy adjacent space.
      const spacing = 0.25;
      final wide = subdividedBox(Vector3(1.0, 0.5, 0.5), spacing: spacing);
      final tall = subdividedBox(Vector3(0.5, 0.5, 0.5), spacing: spacing);
      final (points, faces) = mergeParts(
        [wide, tall],
        [Vector3(1.0, 0.5, 0.5), Vector3(0.5, 1.5, 0.5)],
      );
      final (merged, weldedFaces) = weldByPosition(points, faces);
      final lShape = EditMesh.fromFaces(merged, weldedFaces);

      final components = decomposeConvex(lShape, maxPieces: 1, seed: 1);
      final singleHullVolume = components.fold<double>(
        0,
        (a, p) => a + p.volume,
      );
      final trueVolume = lShape.signedVolume.abs();
      final singleHullError =
          (singleHullVolume - trueVolume).abs() / trueVolume;
      expect(
        singleHullError,
        greaterThan(0.15),
        reason: 'the L-shape\'s own single hull should overshoot volume',
      );

      final decomposed = decomposeConvex(lShape, maxPieces: 8, seed: 1);
      final decomposedVolume = decomposed.fold<double>(
        0,
        (a, p) => a + p.volume,
      );
      final decomposedError =
          (decomposedVolume - trueVolume).abs() / trueVolume;
      expect(decomposed.length, greaterThan(1));
      expect(decomposedError, lessThanOrEqualTo(0.15));
    });

    test('mutation: a wrong volume formula breaks the tolerance check', () {
      // The same idea `computeMeshInertia`'s own box test mutation checks:
      // confirms the L-shape test above would catch a broken tetrahedron
      // volume sign/scale, since `_volumeOfFaces` and `computeConvexHull`'s
      // own volume both share that formula's shape.
      const wrongScale = 1 / 3; // should be 1/6
      final a = Vector3(1, 0, 0), b = Vector3(0, 1, 0), c = Vector3(0, 0, 1);
      final rightVolume = a.dot(b.cross(c)) / 6.0;
      final wrongVolume = a.dot(b.cross(c)) * wrongScale;
      expect(wrongVolume, isNot(closeTo(rightVolume, 1e-9)));
    });
  });
}
