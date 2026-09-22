/// Collision shapes generated from a mesh: `mesh-80n`'s own gap.
///
/// **The engine already knows how to use a [collision shape][CollisionShape
/// note below]; nothing here generated one from a model.** This file closes
/// that: an approximate convex decomposition (a related algorithm to
/// V-HACD, not that paper's own one), and box, sphere and capsule fits by
/// the mesh's own inertia tensor rather than by its bounding box alone — a
/// bounding box answers "how big", inertia answers "how the mass is really
/// spread", which is the number a physics solver actually needs.
///
/// **Why this returns plain value types and not `flutter3d_physics`'s own
/// `CollisionShape`.** That type is `sealed`, and a sealed class in Dart can
/// only be extended from inside its own library — so a compound shape (this
/// file's own decomposition can produce more than one convex piece) is not a
/// case this package is allowed to add to it. [FittedBox], [FittedSphere]
/// and [FittedCapsule] carry exactly the numbers `CollisionBox`,
/// `CollisionSphere` and `CollisionCapsule` need to be constructed from —
/// position, orientation, dimensions — so a caller one layer up, that
/// already depends on both packages, does that construction in one line.
/// [ConvexPiece] and [staticMeshShape] are geometry only, for the same
/// reason.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'edit_mesh.dart';

// ---------------------------------------------------------------- inertia

/// Mass (this solid's own volume, at unit density — a caller scales by its
/// own material density), centroid, and inertia tensor about that centroid.
final class MeshInertia {
  const MeshInertia({
    required this.mass,
    required this.centroid,
    required this.tensor,
  });

  final double mass;
  final Vector3 centroid;

  /// The symmetric inertia tensor about [centroid]. `tensor.entry(0, 0)` is
  /// `Ixx`, `tensor.entry(0, 1)` is `-Ixy` (and so on) — the physics
  /// convention this is built in, off-diagonals already carrying their own
  /// sign, so a caller never re-derives it.
  final Matrix3 tensor;
}

/// The principal axes of a [MeshInertia]: the frame in which the tensor is
/// diagonal, moments sorted largest first.
final class PrincipalInertia {
  const PrincipalInertia({
    required this.moments,
    required this.axes,
    required this.mass,
    required this.centroid,
  });

  /// `I1 >= I2 >= I3`, the eigenvalues of the inertia tensor.
  final Vector3 moments;

  /// Columns are unit eigenvectors, in the same order as [moments] — the
  /// rotation from world axes to the body's own principal frame.
  final Matrix3 axes;

  final double mass;
  final Vector3 centroid;
}

/// Computes [mesh]'s mass, centroid and inertia tensor by summing signed
/// tetrahedra from the world origin over every triangulated face — the same
/// decomposition [EditMesh.signedVolume] already sums for volume alone, kept
/// consistent with it deliberately (a mesh whose `signedVolume` is negative,
/// because its winding is inverted, produces a negative [MeshInertia.mass]
/// here too, rather than silently taking an absolute value that would hide
/// the same `mesh-27` `inverted` check this package already has).
///
/// A concave or open mesh still gets an answer — the tetrahedra decomposition
/// does not require convexity — but the closed-form integral this leans on
/// (a tetrahedron with one vertex at the origin) only equals the true solid
/// integral when the surface is closed, exactly the assumption
/// [EditMesh.signedVolume] already makes.
MeshInertia computeMeshInertia(EditMesh mesh) {
  var mass = 0.0;
  final firstMoment = Vector3.zero();
  // Second moments about the origin: xx, yy, zz, xy, xz, yz.
  var cxx = 0.0, cyy = 0.0, czz = 0.0, cxy = 0.0, cxz = 0.0, cyz = 0.0;

  for (final loop in mesh.faces()) {
    if (loop.length < 3) continue;
    final anchor = mesh.positionOf(loop[0]);
    for (var i = 1; i + 1 < loop.length; i++) {
      final a = anchor;
      final b = mesh.positionOf(loop[i]);
      final c = mesh.positionOf(loop[i + 1]);

      // Signed volume of the tetrahedron (origin, a, b, c).
      final vTet = a.dot(b.cross(c)) / 6.0;
      mass += vTet;
      firstMoment
        ..x += vTet * (a.x + b.x + c.x) / 4.0
        ..y += vTet * (a.y + b.y + c.y) / 4.0
        ..z += vTet * (a.z + b.z + c.z) / 4.0;

      // Second-moment tetrahedron integral, apex at the origin — see the
      // file doc for the simplex-integral derivation this closed form comes
      // from (Dirichlet integrals of u^a v^b w^c over the standard
      // 3-simplex).
      double pair(double p, double q, double r, double s, double t, double u) =>
          (p * q + r * s + t * u) / 10.0 +
          ((p * s + q * r) + (p * u + q * t) + (r * u + s * t)) / 20.0;
      cxx += vTet * pair(a.x, a.x, b.x, b.x, c.x, c.x);
      cyy += vTet * pair(a.y, a.y, b.y, b.y, c.y, c.y);
      czz += vTet * pair(a.z, a.z, b.z, b.z, c.z, c.z);
      cxy += vTet * pair(a.x, a.y, b.x, b.y, c.x, c.y);
      cxz += vTet * pair(a.x, a.z, b.x, b.z, c.x, c.z);
      cyz += vTet * pair(a.y, a.z, b.y, b.z, c.y, c.z);
    }
  }

  final centroid = mass.abs() > 1e-12 ? (firstMoment / mass) : Vector3.zero();

  // Shift the covariance from about the origin to about the centroid
  // (parallel axis theorem on the covariance form: C' = C - m * g outer g).
  final gx = centroid.x, gy = centroid.y, gz = centroid.z;
  cxx -= mass * gx * gx;
  cyy -= mass * gy * gy;
  czz -= mass * gz * gz;
  cxy -= mass * gx * gy;
  cxz -= mass * gx * gz;
  cyz -= mass * gy * gz;

  // Covariance -> inertia tensor: Ixx = Cyy+Czz, Ixy = -Cxy, and so on.
  final tensor = Matrix3.zero()
    ..setEntry(0, 0, cyy + czz)
    ..setEntry(1, 1, cxx + czz)
    ..setEntry(2, 2, cxx + cyy)
    ..setEntry(0, 1, -cxy)
    ..setEntry(1, 0, -cxy)
    ..setEntry(0, 2, -cxz)
    ..setEntry(2, 0, -cxz)
    ..setEntry(1, 2, -cyz)
    ..setEntry(2, 1, -cyz);

  return MeshInertia(mass: mass, centroid: centroid, tensor: tensor);
}

/// Diagonalises [inertia]'s own tensor by the classical Jacobi eigenvalue
/// algorithm — a symmetric 3x3 matrix is small enough that a handful of
/// sweeps converge to double precision, and unlike a general eigensolver it
/// never needs a shift strategy or a fallback for a repeated eigenvalue (a
/// perfectly round mesh's own sphere of equal moments included).
PrincipalInertia principalAxesOf(MeshInertia inertia) {
  // Work in a plain 3x3 array, double precision — `Matrix3`'s own storage is
  // `Float32List`, and a sweep of rotations on single precision drifts
  // enough to fail a 5%-tolerance test on a mesh with a near-degenerate
  // pair of moments.
  final a = List.generate(
    3,
    (r) => List.generate(3, (c) => inertia.tensor.entry(r, c)),
  );
  // Eigenvectors accumulate here, starting at the identity.
  final v = List.generate(
    3,
    (r) => List.generate(3, (c) => r == c ? 1.0 : 0.0),
  );

  for (var sweep = 0; sweep < 64; sweep++) {
    // Largest off-diagonal magnitude drives convergence and picks the next
    // rotation — Jacobi's own classical (not cyclic) sweep.
    var p = 0, q = 1;
    var largest = a[0][1].abs();
    for (final (r, c) in const [(0, 2), (1, 2)]) {
      if (a[r][c].abs() > largest) {
        largest = a[r][c].abs();
        p = r;
        q = c;
      }
    }
    if (largest < 1e-12) break;

    final app = a[p][p], aqq = a[q][q], apq = a[p][q];
    final theta = (aqq - app) / (2 * apq);
    final t =
        (theta >= 0 ? 1.0 : -1.0) /
        (theta.abs() + math.sqrt(theta * theta + 1));
    final c = 1 / math.sqrt(t * t + 1);
    final s = t * c;

    a[p][p] = app - t * apq;
    a[q][q] = aqq + t * apq;
    a[p][q] = 0;
    a[q][p] = 0;
    for (var i = 0; i < 3; i++) {
      if (i == p || i == q) continue;
      final aip = a[i][p], aiq = a[i][q];
      a[i][p] = a[p][i] = c * aip - s * aiq;
      a[i][q] = a[q][i] = s * aip + c * aiq;
    }
    for (var i = 0; i < 3; i++) {
      final vip = v[i][p], viq = v[i][q];
      v[i][p] = c * vip - s * viq;
      v[i][q] = s * vip + c * viq;
    }
  }

  final eigenvalues = <double>[a[0][0], a[1][1], a[2][2]];
  final order = <int>[0, 1, 2]
    ..sort((x, y) => eigenvalues[y].compareTo(eigenvalues[x]));

  final moments = Vector3(
    eigenvalues[order[0]],
    eigenvalues[order[1]],
    eigenvalues[order[2]],
  );
  final axes = Matrix3.columns(
    Vector3(v[0][order[0]], v[1][order[0]], v[2][order[0]]),
    Vector3(v[0][order[1]], v[1][order[1]], v[2][order[1]]),
    Vector3(v[0][order[2]], v[1][order[2]], v[2][order[2]]),
  );

  return PrincipalInertia(
    moments: moments,
    axes: axes,
    mass: inertia.mass,
    centroid: inertia.centroid,
  );
}

// -------------------------------------------------------------- box / sphere

/// A box, positioned and oriented — the numbers `CollisionBox` needs.
final class FittedBox {
  const FittedBox({
    required this.center,
    required this.orientation,
    required this.halfExtents,
  });

  final Vector3 center;

  /// Columns are the box's own local x/y/z axes in world space.
  final Matrix3 orientation;
  final Vector3 halfExtents;
}

/// A sphere — trivially unoriented.
final class FittedSphere {
  const FittedSphere({required this.center, required this.radius});

  final Vector3 center;
  final double radius;
}

/// A capsule: a cylinder of [radius] and [height], capped by two hemispheres
/// of the same radius, centred at [center] and running along [axis].
final class FittedCapsule {
  const FittedCapsule({
    required this.center,
    required this.axis,
    required this.radius,
    required this.height,
  });

  final Vector3 center;

  /// Unit vector along the capsule's own long axis.
  final Vector3 axis;
  final double radius;

  /// The cylindrical section's own length — the hemispherical caps add
  /// [radius] beyond each end, so the capsule's total length is
  /// `height + 2 * radius`.
  final double height;
}

/// Fits an oriented box to [mesh] by its own inertia tensor.
///
/// A solid box with half-extents `(a, b, c)` and mass `m` has principal
/// moments `Ix = m(b²+c²)/3`, `Iy = m(a²+c²)/3`, `Iz = m(a²+b²)/3` — three
/// linear equations in `a², b², c²`, solved directly rather than iterated:
/// `a² = 3(Iy+Iz-Ix)/(2m)` and its two rotations. The box's own axes are the
/// mesh's principal axes; a mesh whose mass is concentrated off an axis
/// rotates the fitted box to match, which a plain bounding box never does.
FittedBox fitBoxByInertia(EditMesh mesh) {
  final principal = principalAxesOf(computeMeshInertia(mesh));
  final m = principal.mass.abs();
  final ix = principal.moments.x, iy = principal.moments.y;
  final iz = principal.moments.z;

  double halfExtent(double sum) => math.sqrt(math.max(0.0, 1.5 * sum / m));
  final a = halfExtent(iy + iz - ix);
  final b = halfExtent(ix + iz - iy);
  final c = halfExtent(ix + iy - iz);

  return FittedBox(
    center: principal.centroid,
    orientation: principal.axes,
    halfExtents: Vector3(a, b, c),
  );
}

/// Fits a sphere to [mesh] by its own inertia tensor: a solid sphere of
/// radius `r` and mass `m` has `I = (2/5)mr²` about any axis, so the fit
/// radius comes from the mean of the mesh's own three principal moments —
/// the single value that makes a sphere's *isotropic* inertia agree with an
/// anisotropic mesh as closely as one number can.
FittedSphere fitSphereByInertia(EditMesh mesh) {
  final principal = principalAxesOf(computeMeshInertia(mesh));
  final m = principal.mass.abs();
  final meanMoment =
      (principal.moments.x + principal.moments.y + principal.moments.z) / 3.0;
  final radius = math.sqrt(math.max(0.0, 2.5 * meanMoment / m));
  return FittedSphere(center: principal.centroid, radius: radius);
}

/// Fits a capsule to [mesh] by its own inertia tensor, along the mesh's own
/// longest principal axis (`moments.z`, the smallest moment — an elongated
/// body carries the least inertia about its own long axis, the same reason
/// a spinning pencil is easiest to spin end over end).
///
/// **The closed form.** With unit density (`m` = mesh volume) split between
/// a cylinder of radius `r`, height `h` and two hemispherical caps of the
/// same `r` (so `m = πr²h + (4/3)πr³`), the moment about the long axis is
/// `Iz = πr²h·(r²/2) + (4/3)πr³·(2/5)r²`. Substituting `h` from the mass
/// equation collapses this to one equation in `r` alone:
/// `Iz = (m/2)r² - (2π/15)r⁵` — solved by bisection, then `h` read back off
/// the mass equation. `r` and `h` fully determine the capsule; the
/// perpendicular moment is not a second fitting constraint (that would
/// over-determine two unknowns with three equations) but it is what the
/// tests in `collision_shapes_test.dart` check the *result* against, on a
/// mesh built as an actual capsule of known dimensions.
FittedCapsule fitCapsuleByInertia(EditMesh mesh) {
  final principal = principalAxesOf(computeMeshInertia(mesh));
  final m = principal.mass.abs();
  // The long axis carries the smallest moment.
  final axis = principal.axes.getColumn(2);
  final izTarget = principal.moments.z;

  double residual(double r) =>
      (m / 2) * r * r - (2 * math.pi / 15) * math.pow(r, 5) - izTarget;

  // `residual` is not monotonic over all r >= 0 — its derivative
  // `r(m - (2π/3)r³)` turns negative once `r³ > 3m/(2π)`, past which growing
  // `r` further makes the quintic term dominate and `residual` fall back
  // toward -∞. That is not a physically reachable radius here: `r_max =
  // cbrt(3m/(4π))` is the point where the cylinder's own height hits zero
  // (the whole capsule is one sphere), beyond which "cylinder height" would
  // have to go negative. `residual` is monotonically increasing on
  // `[0, r_max]` (the sign-change point of its derivative lies strictly
  // beyond `r_max`, since `3m/(2π) > 3m/(4π)`), so bracketing bisection
  // there to begin with — rather than growing `hi` unbounded and risking a
  // bracket that straddles the *second*, unphysical root — is what makes
  // this solve correct rather than merely convergent to *some* root.
  final rMax = math.pow(3 * m / (4 * math.pi), 1 / 3).toDouble();
  var lo = 0.0;
  var hi = rMax;
  var r = hi;
  for (var i = 0; i < 80; i++) {
    final mid = (lo + hi) / 2;
    if (residual(mid) < 0) {
      lo = mid;
    } else {
      hi = mid;
    }
    r = mid;
  }

  final cylinderVolume = m - (4.0 / 3.0) * math.pi * r * r * r;
  final h = cylinderVolume > 0 ? cylinderVolume / (math.pi * r * r) : 0.0;

  return FittedCapsule(
    center: principal.centroid,
    axis: axis,
    radius: r,
    height: h,
  );
}

// ---------------------------------------------------------------- static

/// The exact triangle soup of [mesh], for a static (non-moving) body: no
/// approximation is needed when nothing ever has to sweep this shape
/// through space, only test a moving body against it — the row's own "сам
/// меш" case. Deliberately not wrapped in a `CollisionShape`: a static
/// triangle mesh is not one of that sealed type's five cases, and building
/// the narrow-phase that would test against raw triangles is a caller's own
/// job, one layer up, not this generator's.
final class StaticMeshShape {
  const StaticMeshShape({required this.vertices, required this.triangles});

  /// Every vertex position, in mesh order.
  final List<Vector3> vertices;

  /// Vertex index triples — [mesh]'s own faces, already fan-triangulated,
  /// so a caller never has to handle an n-gon.
  final List<(int, int, int)> triangles;
}

/// Triangulates every face of [mesh] by the same origin-vertex fan every
/// other reader in this file uses, and returns it as plain triangle soup.
StaticMeshShape staticMeshShape(EditMesh mesh) {
  final vertices = <Vector3>[
    for (var v = 0; v < mesh.vertexSlotCount; v++)
      if (mesh.isVertexAlive(v)) mesh.positionOf(v),
  ];
  // Re-index alive vertices densely, since `vertices` above skips gaps.
  final remap = <int, int>{};
  var next = 0;
  for (var v = 0; v < mesh.vertexSlotCount; v++) {
    if (mesh.isVertexAlive(v)) remap[v] = next++;
  }

  final triangles = <(int, int, int)>[];
  for (final loop in mesh.faces()) {
    if (loop.length < 3) continue;
    final anchor = remap[loop[0]]!;
    for (var i = 1; i + 1 < loop.length; i++) {
      triangles.add((anchor, remap[loop[i]]!, remap[loop[i + 1]]!));
    }
  }
  return StaticMeshShape(vertices: vertices, triangles: triangles);
}

// ------------------------------------------------------------- convex hull

/// A convex polytope: [points] on its own surface, [faces] as outward-wound
/// triangle index triples into [points], with its own [volume] and
/// [centroid] already computed (both integrate the same way
/// [computeMeshInertia] does, over this hull's own triangulated faces).
final class ConvexHull {
  const ConvexHull({
    required this.points,
    required this.faces,
    required this.volume,
    required this.centroid,
  });

  final List<Vector3> points;
  final List<(int, int, int)> faces;
  final double volume;
  final Vector3 centroid;
}

/// The convex hull of [points], by incremental construction — Preparata &
/// Hong's own algorithm: start from a tetrahedron, then fold each remaining
/// point in by deleting every face it can see and re-triangulating the hole
/// with a fan from the new point ("horizon stitching"). At the piece counts
/// this file calls it with (tens to a few hundred points, from one cluster
/// of a decomposition), the naive O(n²) visibility test per point is fast
/// enough that a spatial index would only add a place for a bug to hide.
///
/// Returns `null` for fewer than 4 points or a degenerate (coplanar)
/// input — a caller falls back to something else rather than receiving an
/// empty hull.
ConvexHull? computeConvexHull(List<Vector3> points) {
  if (points.length < 4) return null;

  // Seed tetrahedron: the two points farthest apart, the point farthest
  // from that line, then the point farthest from that plane. Deterministic
  // (a scan, not a random pick), and the four points found are exactly the
  // seed a correct incremental hull needs — no ambiguity from nearly-equal
  // candidates, since ties break on index order.
  var (ia, ib) = (0, 1);
  var best = points[0].distanceToSquared(points[1]);
  for (var i = 0; i < points.length; i++) {
    for (var j = i + 1; j < points.length; j++) {
      final d = points[i].distanceToSquared(points[j]);
      if (d > best) {
        best = d;
        ia = i;
        ib = j;
      }
    }
  }
  var ic = -1;
  var bestDist = -1.0;
  final ab = points[ib] - points[ia];
  for (var i = 0; i < points.length; i++) {
    if (i == ia || i == ib) continue;
    final toPoint = points[i] - points[ia];
    final cross = ab.cross(toPoint);
    final d = cross.length2;
    if (d > bestDist) {
      bestDist = d;
      ic = i;
    }
  }
  if (ic < 0 || bestDist < 1e-18) return null;

  final normal = ab.cross(points[ic] - points[ia]);
  var id = -1;
  var bestPlane = -1.0;
  for (var i = 0; i < points.length; i++) {
    if (i == ia || i == ib || i == ic) continue;
    final d = (points[i] - points[ia]).dot(normal).abs();
    if (d > bestPlane) {
      bestPlane = d;
      id = i;
    }
  }
  if (id < 0 || bestPlane < 1e-18) return null;

  // Faces as outward-wound triples. Orientation is fixed once here by
  // checking `id` against the seed plane, and preserved from then on by
  // construction (a horizon edge's replacement face always winds the same
  // way the edge's own two hull faces already agreed it should).
  final faces = <List<int>>[];
  void addFace(int p, int q, int r, Vector3 outwardHint) {
    final n = (points[q] - points[p]).cross(points[r] - points[p]);
    if (n.dot(outwardHint) < 0) {
      faces.add([p, r, q]);
    } else {
      faces.add([p, q, r]);
    }
  }

  final centroidSeed =
      (points[ia] + points[ib] + points[ic] + points[id]) / 4.0;
  Vector3 outwardFrom(int p, int q, int r) {
    final c = (points[p] + points[q] + points[r]) / 3.0;
    return c - centroidSeed;
  }

  addFace(ia, ib, ic, outwardFrom(ia, ib, ic));
  addFace(ia, ib, id, outwardFrom(ia, ib, id));
  addFace(ia, ic, id, outwardFrom(ia, ic, id));
  addFace(ib, ic, id, outwardFrom(ib, ic, id));

  final used = <int>{ia, ib, ic, id};

  for (var i = 0; i < points.length; i++) {
    if (used.contains(i)) continue;
    final p = points[i];

    // Which faces this point sees (is on the positive side of).
    final visible = <int>[];
    for (var f = 0; f < faces.length; f++) {
      final face = faces[f];
      final a = points[face[0]], b = points[face[1]], c = points[face[2]];
      final n = (b - a).cross(c - a);
      if (n.dot(p - a) > 1e-9) visible.add(f);
    }
    if (visible.isEmpty) continue; // Already inside the current hull.

    // Horizon: edges of visible faces not shared with another visible face.
    final edgeCount = <(int, int), int>{};
    for (final f in visible) {
      final face = faces[f];
      for (var e = 0; e < 3; e++) {
        final u = face[e], v = face[(e + 1) % 3];
        final key = u < v ? (u, v) : (v, u);
        edgeCount[key] = (edgeCount[key] ?? 0) + 1;
      }
    }
    final horizon = <(int, int)>[];
    for (final f in visible) {
      final face = faces[f];
      for (var e = 0; e < 3; e++) {
        final u = face[e], v = face[(e + 1) % 3];
        final key = u < v ? (u, v) : (v, u);
        if (edgeCount[key] == 1) horizon.add((u, v));
      }
    }

    final visibleSet = visible.toSet();
    final kept = <List<int>>[
      for (var f = 0; f < faces.length; f++)
        if (!visibleSet.contains(f)) faces[f],
    ];
    faces
      ..clear()
      ..addAll(kept);

    for (final (u, v) in horizon) {
      addFace(u, v, i, outwardFrom(u, v, i));
    }
    used.add(i);
  }

  // Volume and centroid, by the same origin-tetrahedron sum
  // `computeMeshInertia` uses (the hull is closed and convex by
  // construction, so it holds without the open-mesh caveat there).
  var volume = 0.0;
  final firstMoment = Vector3.zero();
  for (final face in faces) {
    final a = points[face[0]], b = points[face[1]], c = points[face[2]];
    final vTet = a.dot(b.cross(c)) / 6.0;
    volume += vTet;
    firstMoment
      ..x += vTet * (a.x + b.x + c.x) / 4.0
      ..y += vTet * (a.y + b.y + c.y) / 4.0
      ..z += vTet * (a.z + b.z + c.z) / 4.0;
  }
  final centroid = volume.abs() > 1e-12 ? firstMoment / volume : centroidSeed;

  return ConvexHull(
    points: points,
    faces: [for (final f in faces) (f[0], f[1], f[2])],
    volume: volume.abs(),
    centroid: centroid,
  );
}

// ---------------------------------------------------------- decomposition

/// One piece of a [decomposeConvex] result.
final class ConvexPiece {
  const ConvexPiece({required this.hull});

  final ConvexHull hull;
  double get volume => hull.volume;
  Vector3 get centroid => hull.centroid;
}

/// Approximate convex decomposition of [mesh]: a related algorithm to
/// V-HACD, not that paper's own one.
///
/// **Two stages, not one.** A single clustering pass over the whole mesh
/// — the first version of this function did exactly that — lets k-means
/// place two spatially close but topologically disjoint parts (a chair
/// leg's own top and the seat sitting just above it) in the same cluster;
/// their combined convex hull then bridges the empty air between them and
/// wildly overshoots volume, which no amount of retrying a *global* k finds
/// its way out of. So this decomposes by **topology first**: [mesh]'s own
/// connected components (union-find over faces sharing a vertex — a chair's
/// four legs, seat and back are already four... six disjoint components,
/// with nothing in the algorithm having to discover that) each get their
/// own convex-hull attempt, and only a component whose own hull volume
/// still overshoots its own true volume — a genuinely concave part — pays
/// for k-means clustering, applied *within* that one component alone, `k`
/// rising until its own share of [toleranceFraction] is met or the shared
/// [maxPieces] budget runs out.
///
/// Deterministic for a fixed [seed]: cluster initialisation uses
/// `Random(seed)`'s own farthest-point sampling, and Dart's seeded `Random`
/// is itself deterministic run to run; components are processed in a fixed
/// order (by their lowest vertex index) so the same mesh always splits its
/// piece budget the same way.
///
/// [maxPieces] is a floor as much as a cap when [mesh] already has more
/// disconnected components than the budget allows: one hull per component is
/// never skipped (that is exactly the bridging-empty-air failure the two-stage
/// split exists to avoid), so a mesh of 20 disjoint islands and `maxPieces:
/// 12` returns 20 single-hull pieces rather than merging islands down to 12
/// and eating the volume error that would cost.
List<ConvexPiece> decomposeConvex(
  EditMesh mesh, {
  int maxPieces = 12,
  int seed = 0,
  double toleranceFraction = 0.15,
}) {
  final faceLoops = mesh.faces();
  final components = _connectedComponents(faceLoops);

  // Each component's own true volume, tetrahedra-from-origin over only its
  // own faces — the same sum `computeMeshInertia`'s mass uses, scoped down.
  final componentVolume = <double>[
    for (final component in components) _volumeOfFaces(mesh, component),
  ];

  // Cheapest attempt per component first: its own single hull. A component
  // that is already convex (every box in a chair) settles here at k=1 and
  // never touches k-means at all.
  final piecesPerComponent = List.generate(components.length, (i) {
    final points = _uniqueVertexPositions(mesh, components[i]);
    final hull = computeConvexHull(points);
    return hull == null ? const <ConvexPiece>[] : [ConvexPiece(hull: hull)];
  });

  bool withinTolerance(int i) {
    final total = piecesPerComponent[i].fold<double>(0, (a, p) => a + p.volume);
    final trueVolume = componentVolume[i].abs();
    if (trueVolume < 1e-12) return true;
    return (total - trueVolume).abs() / trueVolume <= toleranceFraction;
  }

  var totalPieces = piecesPerComponent.fold<int>(0, (a, p) => a + p.length);

  // The next `k` each component will try — distinct from
  // `piecesPerComponent[i].length` (its last *successful* piece count) once
  // a `k` fails to hull cleanly (a cluster left with too few points to hull,
  // most likely) and this advances past it anyway. Capped at the
  // component's own unique vertex count, past which no k-means split can
  // possibly produce four-point-or-more clusters everywhere.
  final componentVertexCounts = [
    for (final component in components)
      <int>{for (final loop in component) ...loop}.length,
  ];
  final nextKToTry = [
    for (var i = 0; i < components.length; i++)
      piecesPerComponent[i].length + 1,
  ];

  // Components that still miss their own tolerance grow their own `k`, one
  // step at a time, cheapest (smallest next k) first — so a budget of, say,
  // 12 pieces across two concave components splits by how much each one
  // still needs, not by whichever happened to run first. A `k` that fails
  // to hull cleanly does not stall the component (or, as an earlier version
  // of this loop did, the whole function): it moves on to `k + 1` and the
  // outer loop keeps going, bounded either by [maxPieces] or by every
  // component running out of vertices to split further.
  while (totalPieces < maxPieces) {
    var choice = -1;
    var choiceK = 1 << 30;
    for (var i = 0; i < components.length; i++) {
      if (withinTolerance(i)) continue;
      if (nextKToTry[i] > componentVertexCounts[i]) continue;
      if (nextKToTry[i] < choiceK) {
        choiceK = nextKToTry[i];
        choice = i;
      }
    }
    if (choice < 0) break;

    final k = nextKToTry[choice];
    nextKToTry[choice] = k + 1;

    // Clusters the component's own unique VERTEX positions directly, not
    // face centroids by way of a per-face assignment. A face-centroid
    // cluster hands every point of a face to whichever single cluster the
    // face's own average lands in — and a face spanning the *entire*
    // cross-section (an end cap on a low-poly prism, say) then drags every
    // one of its own corners into one cluster regardless of the other
    // faces, no matter how many more of those there are. Clustering
    // vertices themselves has no such single point of failure: each corner
    // lands wherever it geometrically belongs.
    final vertexIds = <int>{for (final loop in components[choice]) ...loop};
    final vertexList = vertexIds.toList();
    final vertexPositions = [for (final v in vertexList) mesh.positionOf(v)];
    final clusters = _kMeansClusters(vertexPositions, k, seed);
    final piecePoints = List.generate(k, (_) => <Vector3>[]);
    for (var i = 0; i < vertexList.length; i++) {
      piecePoints[clusters[i]].add(vertexPositions[i]);
    }

    final attempt = <ConvexPiece>[];
    var ok = true;
    for (final points in piecePoints) {
      if (points.length < 4) {
        ok = false;
        break;
      }
      final hull = computeConvexHull(points);
      if (hull == null) {
        ok = false;
        break;
      }
      attempt.add(ConvexPiece(hull: hull));
    }
    if (!ok) continue; // This k didn't hull cleanly; k + 1 is queued above.

    totalPieces += attempt.length - piecesPerComponent[choice].length;
    piecesPerComponent[choice] = attempt;
  }

  return [for (final pieces in piecesPerComponent) ...pieces];
}

/// Union-find over faces sharing a vertex, grouped into connected pieces —
/// each returned list is one component's own faces, as the same vertex-loop
/// lists [EditMesh.faces] returns.
List<List<List<int>>> _connectedComponents(List<List<int>> faceLoops) {
  final parent = <int, int>{};
  int find(int x) {
    var root = x;
    while (parent[root] != root) {
      root = parent[root]!;
    }
    var cur = x;
    while (parent[cur] != root) {
      final next = parent[cur]!;
      parent[cur] = root;
      cur = next;
    }
    return root;
  }

  void union(int a, int b) {
    final ra = find(a), rb = find(b);
    if (ra != rb) parent[ra] = rb;
  }

  for (final loop in faceLoops) {
    for (final v in loop) {
      parent.putIfAbsent(v, () => v);
    }
    for (var i = 1; i < loop.length; i++) {
      union(loop[0], loop[i]);
    }
  }

  final byRoot = <int, List<List<int>>>{};
  for (final loop in faceLoops) {
    if (loop.isEmpty) continue;
    final root = find(loop[0]);
    (byRoot[root] ??= <List<int>>[]).add(loop);
  }

  // A fixed, mesh-derived order (by the component's own lowest vertex
  // index) — not map insertion order, which `LinkedHashMap`'s own iteration
  // happens to preserve today but is not a contract this function should
  // lean on.
  final roots = byRoot.keys.toList()..sort();
  return [for (final r in roots) byRoot[r]!];
}

double _volumeOfFaces(EditMesh mesh, List<List<int>> faceLoops) {
  var total = 0.0;
  for (final loop in faceLoops) {
    if (loop.length < 3) continue;
    final anchor = mesh.positionOf(loop[0]);
    for (var i = 1; i + 1 < loop.length; i++) {
      final b = mesh.positionOf(loop[i]);
      final c = mesh.positionOf(loop[i + 1]);
      total += anchor.dot(b.cross(c)) / 6.0;
    }
  }
  return total;
}

List<Vector3> _uniqueVertexPositions(EditMesh mesh, List<List<int>> faceLoops) {
  final ids = <int>{};
  for (final loop in faceLoops) {
    ids.addAll(loop);
  }
  return [for (final id in ids) mesh.positionOf(id)];
}

/// Deterministic k-means: farthest-point sampling from a seeded `Random`
/// picks the `k` starting centres (so a fixed [seed] gives a fixed answer,
/// but different seeds do not all collapse onto the same nearly-degenerate
/// start the way "pick k random points" sometimes does), then Lloyd's own
/// iteration to convergence or a fixed cap.
List<int> _kMeansClusters(List<Vector3> points, int k, int seed) {
  if (k <= 1 || points.length <= k) {
    return List.filled(points.length, 0);
  }
  final random = math.Random(seed);
  final centres = <Vector3>[points[random.nextInt(points.length)]];
  while (centres.length < k) {
    var farthest = points[0];
    var farthestDist = -1.0;
    for (final p in points) {
      var nearest = double.infinity;
      for (final c in centres) {
        final d = p.distanceToSquared(c);
        if (d < nearest) nearest = d;
      }
      if (nearest > farthestDist) {
        farthestDist = nearest;
        farthest = p;
      }
    }
    centres.add(farthest);
  }

  final assignment = List.filled(points.length, 0);
  for (var iter = 0; iter < 25; iter++) {
    var changed = false;
    for (var i = 0; i < points.length; i++) {
      var best = 0;
      var bestDist = points[i].distanceToSquared(centres[0]);
      for (var c = 1; c < centres.length; c++) {
        final d = points[i].distanceToSquared(centres[c]);
        if (d < bestDist) {
          bestDist = d;
          best = c;
        }
      }
      if (assignment[i] != best) {
        assignment[i] = best;
        changed = true;
      }
    }
    if (!changed) break;

    final sums = List.generate(k, (_) => Vector3.zero());
    final counts = List.filled(k, 0);
    for (var i = 0; i < points.length; i++) {
      sums[assignment[i]].add(points[i]);
      counts[assignment[i]]++;
    }
    for (var c = 0; c < k; c++) {
      if (counts[c] > 0) centres[c] = sums[c] / counts[c].toDouble();
    }
  }
  return assignment;
}
