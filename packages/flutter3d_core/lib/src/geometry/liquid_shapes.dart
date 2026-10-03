import 'dart:math' as math;

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:vector_math/vector_math.dart';

import 'mesh_builder.dart';
import 'mesh_data.dart';
import 'vertex_layout.dart';

/// One layer of a liquid, and the mesh that draws it, in its vessel's frame.
typedef LiquidLayerMesh = ({LiquidLayer layer, MeshData mesh});

/// The meshes that draw a [LiquidBody], one per layer, bottom first, in the
/// vessel's own frame — put them on a node that moves with the vessel.
///
/// **Each layer is the inside of the vessel between two planes**: its
/// boundary with the layer under it, and its top. The vessel's inside —
/// the lathe of a [RevolvedVessel]'s wall, or a [MeshVessel]'s triangles —
/// is cut by both, a triangle at a time (Sutherland and Hodgman), and the
/// cuts are closed with flat caps, so it works for any shape tipped any way.
/// A cap is laid as rings from its outline to its middle where the outline
/// is star-shaped about its middle, as a round vessel's always is, the rings
/// closer together near the wall where the meniscus curls; any other is
/// ear-clipped and subdivided.
///
/// **The top is the liquid's own surface**: every point on the top plane —
/// the cap and the wall's upper edge both — is lifted by how far the surface
/// stands off its plane there ([LiquidBody.surfaceAt]): the waves, and the
/// meniscus climbing the glass, with no seam between them.
List<LiquidLayerMesh> liquidMeshes(
  LiquidBody body, {
  int segments = 48,
  int rows = 48,
  int rings = 12,
}) {
  final up = body.up;
  final inside = _inside(body.shape, segments, rows);
  final layers = body.layers;
  final tops = body.layerTops();
  final out = <LiquidLayerMesh>[];
  for (var i = 0; i < layers.length; i++) {
    if (layers[i].volume <= 0.0) continue;
    final lower = i == 0 ? double.negativeInfinity : tops[i - 1];
    final upper = i == layers.length - 1 ? body.height : tops[i];
    final top = i == layers.length - 1;
    final mesh = _layer(
      body: body,
      inside: inside,
      up: up,
      lower: lower,
      upper: upper,
      surface: top,
      rings: rings,
    );
    out.add((layer: layers[i], mesh: mesh));
  }
  return out;
}

/// A point of a triangle: where, and its normal.
typedef _P = ({Vector3 p, Vector3 n});

/// The inside of [shape] as triangles, wound outwards; made once a shape
/// and kept, since a liquid is drawn again every frame it moves.
List<List<_P>> _inside(VesselShape shape, int segments, int rows) {
  final kept = _insides[shape];
  if (kept != null && kept.segments == segments && kept.rows == rows) {
    return kept.triangles;
  }
  final triangles = _insideOf(shape, segments, rows);
  _insides[shape] = (segments: segments, rows: rows, triangles: triangles);
  return triangles;
}

final Expando<({int segments, int rows, List<List<_P>> triangles})> _insides =
    Expando();

List<List<_P>> _insideOf(VesselShape shape, int segments, int rows) {
  final out = <List<_P>>[];
  switch (shape) {
    case RevolvedVessel(:final wall):
      final along = <double>[0.0];
      for (var i = 1; i < wall.length; i++) {
        along.add(along.last + (wall[i] - wall[i - 1]).length);
      }
      final profile = <({Vector2 p, Vector2 n})>[];
      var segment = 1;
      for (var k = 0; k <= rows; k++) {
        final d = along.last * k / rows;
        while (segment < wall.length - 1 && along[segment] < d) {
          segment++;
        }
        final a = wall[segment - 1];
        final b = wall[segment];
        final span = along[segment] - along[segment - 1];
        final t = span > 0.0 ? (d - along[segment - 1]) / span : 0.0;
        final run = b - a;
        profile.add((
          p: a + run * t,
          n: run.length2 > 0.0
              ? Vector2(run.y, -run.x).normalized()
              : Vector2(0, -1),
        ));
      }
      _P at(int column, int row) {
        final angle = 2.0 * math.pi * column / segments;
        final c = math.cos(angle);
        final s = math.sin(angle);
        final (:p, :n) = profile[row];
        return (
          p: Vector3(p.x * c, p.y, p.x * s),
          n: Vector3(n.x * c, n.y, n.x * s),
        );
      }

      for (var i = 0; i < segments; i++) {
        for (var j = 0; j < rows; j++) {
          final a = at(i, j);
          final b = at(i + 1, j);
          final c = at(i + 1, j + 1);
          final d = at(i, j + 1);
          if (profile[j].p.x > 0.0) out.add([a, d, b]);
          if (profile[j + 1].p.x > 0.0) out.add([b, d, c]);
        }
      }
    case MeshVessel(:final positions, :final indices):
      for (var t = 0; t < indices.length; t += 3) {
        final a = positions[indices[t]];
        final b = positions[indices[t + 1]];
        final c = positions[indices[t + 2]];
        final n = (b - a).cross(c - a)..normalize();
        out.add([(p: a, n: n), (p: b, n: n), (p: c, n: n)]);
      }
    default:
      break;
  }
  return out;
}

MeshData _layer({
  required LiquidBody body,
  required List<List<_P>> inside,
  required Vector3 up,
  required double lower,
  required double upper,
  required bool surface,
  required int rings,
}) {
  final builder = MeshBuilder(VertexLayout.standard);
  final topCut = <List<Vector3>>[];
  final bottomCut = <List<Vector3>>[];
  // How far the surface stands off the top plane over a point on it.
  double lift(Vector3 p) => surface ? body.surfaceAt(p) - upper : 0.0;
  // Lifted along up, a point on a wall that leans is lifted off it: kept a
  // hair inside the glass instead.
  Vector3 within(Vector3 p) {
    final shape = body.shape;
    if (shape is! RevolvedVessel) return p;
    final at = shape.wallDistance(p);
    if (at == null || at.distance < -1e-5) return p;
    return p - at.normal * (at.distance + 1e-5);
  }

  List<_P> clip(
    List<_P> polygon,
    double h,
    bool keepBelow,
    List<List<Vector3>> cut,
  ) {
    final kept = <_P>[];
    final crossings = <Vector3>[];
    for (var k = 0; k < polygon.length; k++) {
      final a = polygon[k];
      final b = polygon[(k + 1) % polygon.length];
      final sa = (up.dot(a.p) - h) * (keepBelow ? 1.0 : -1.0);
      final sb = (up.dot(b.p) - h) * (keepBelow ? 1.0 : -1.0);
      if (sa <= 0.0) kept.add(a);
      if ((sa < 0.0) != (sb < 0.0)) {
        final t = sa / (sa - sb);
        final p = a.p + (b.p - a.p) * t;
        kept.add((p: p, n: (a.n + (b.n - a.n) * t)..normalize()));
        crossings.add(p);
      }
    }
    if (crossings.length == 2) cut.add(crossings);
    return kept;
  }

  for (final triangle in inside) {
    var polygon = clip(triangle, upper, true, topCut);
    if (lower.isFinite && polygon.length >= 3) {
      polygon = clip(polygon, lower, false, bottomCut);
    }
    if (polygon.length < 3) continue;
    // The wall's upper edge rides the surface.
    final lifted = [
      for (final v in polygon)
        // Within a micrometre: the cut's own points are single precision,
        // four nanometres out at six centimetres, and a test tighter than
        // that left the wall's edge behind the cap it should meet.
        (up.dot(v.p) - upper).abs() < 1e-6
            ? (p: within(v.p + up * lift(v.p)), n: v.n)
            : v,
    ];
    final first = builder.addVertex(position: lifted[0].p, normal: lifted[0].n);
    var previous = builder.addVertex(
      position: lifted[1].p,
      normal: lifted[1].n,
    );
    for (var k = 2; k < lifted.length; k++) {
      final next = builder.addVertex(
        position: lifted[k].p,
        normal: lifted[k].n,
      );
      builder.addTriangle(first, previous, next);
      previous = next;
    }
  }
  _cap(
    builder,
    topCut,
    up,
    surface ? lift : null,
    body,
    upper,
    rings,
    within: within,
  );
  if (lower.isFinite) {
    _cap(builder, bottomCut, -up, null, body, lower, 1);
  }
  return builder.build();
}

/// Closes a cut whose [segments] lie on a plane facing [normal]: lifted by
/// [lift] where the surface stands off it.
void _cap(
  MeshBuilder builder,
  List<List<Vector3>> segments,
  Vector3 normal,
  double Function(Vector3)? lift,
  LiquidBody body,
  double height,
  int rings, {
  Vector3 Function(Vector3)? within,
}) {
  if (segments.length < 3) return;
  final loops = _loops(segments);
  final helper = normal.x.abs() < 0.9 ? Vector3(1, 0, 0) : Vector3(0, 0, 1);
  final e1 = normal.cross(helper)..normalize();
  final e2 = normal.cross(e1);
  Vector3 raise(Vector3 p) {
    final up = lift == null ? p : p + normal * lift(p);
    return within == null ? up : within(up);
  }

  Vector3 shade(Vector3 p) {
    if (lift == null) return normal;
    // The surface's slope, by central differences in the plane.
    final eps = 1e-4;
    final dx = (lift(p + e1 * eps) - lift(p - e1 * eps)) / (2 * eps);
    final dy = (lift(p + e2 * eps) - lift(p - e2 * eps)) / (2 * eps);
    return (normal - e1 * dx - e2 * dy)..normalize();
  }

  for (final loop in loops) {
    if (loop.length < 3) continue;
    final middle =
        loop.fold(Vector3.zero(), (s, p) => s + p) / loop.length.toDouble();
    double angle(Vector3 p) {
      final d = p - middle;
      return math.atan2(d.dot(e2), d.dot(e1));
    }

    // Counter-clockwise seen from the side the cap faces.
    var ordered = loop;
    if (_signedArea(loop, e1, e2) < 0.0) ordered = loop.reversed.toList();
    if (_starShaped(ordered, angle)) {
      // Rings from the outline in to the middle, closer near the outline.
      // Raised first, then shaded from their neighbours on the grid: the
      // surface asked once a point rather than five times for its slope.
      final n = ordered.length;
      final raised = [
        for (var j = 0; j <= rings; j++)
          [
            for (final p in ordered)
              raise(
                middle + (p - middle) * ((1.0 - j / rings) * (1.0 - j / rings)),
              ),
          ],
      ];
      Vector3 gridNormal(int j, int k) {
        if (lift == null) return normal;
        // At the middle every ring point is the same: the ring outside it.
        final row = math.min(j, rings - 1);
        final along = raised[row][(k + 1) % n] - raised[row][(k - 1 + n) % n];
        final across =
            raised[math.max(row - 1, 0)][k] -
            raised[math.min(row + 1, rings)][k];
        final m = along.cross(across);
        if (m.length2 < 1e-30) return normal;
        m.normalize();
        return m.dot(normal) < 0.0 ? -m : m;
      }

      final grid = [
        for (var j = 0; j <= rings; j++)
          [
            for (var k = 0; k < n; k++)
              builder.addVertex(
                position: raised[j][k],
                normal: gridNormal(j, k),
              ),
          ],
      ];
      for (var j = 0; j < rings; j++) {
        for (var k = 0; k < n; k++) {
          final a = grid[j][k];
          final b = grid[j][(k + 1) % n];
          final c = grid[j + 1][(k + 1) % n];
          final d = grid[j + 1][k];
          builder
            ..addTriangle(a, b, c)
            ..addTriangle(a, c, d);
        }
      }
    } else {
      for (final t in _earClip(ordered, e1, e2)) {
        // Each ear split in four twice, so waves have points to show on.
        for (final small in _subdivide(t, 2)) {
          final ia = builder.addVertex(
            position: raise(small[0]),
            normal: shade(small[0]),
          );
          final ib = builder.addVertex(
            position: raise(small[1]),
            normal: shade(small[1]),
          );
          final ic = builder.addVertex(
            position: raise(small[2]),
            normal: shade(small[2]),
          );
          builder.addTriangle(ia, ib, ic);
        }
      }
    }
  }
}

/// The cut's segments chained into closed outlines.
List<List<Vector3>> _loops(List<List<Vector3>> segments) {
  final left = [...segments];
  final loops = <List<Vector3>>[];
  const tolerance = 1e-9;
  bool same(Vector3 a, Vector3 b) =>
      (a - b).length2 < tolerance * tolerance + 1e-14;
  while (left.isNotEmpty) {
    final first = left.removeLast();
    final loop = <Vector3>[first[0], first[1]];
    var grew = true;
    while (grew) {
      grew = false;
      for (var i = 0; i < left.length; i++) {
        final s = left[i];
        if (same(s[0], loop.last)) {
          loop.add(s[1]);
        } else if (same(s[1], loop.last)) {
          loop.add(s[0]);
        } else {
          continue;
        }
        left.removeAt(i);
        grew = true;
        break;
      }
    }
    if (same(loop.first, loop.last)) loop.removeLast();
    loops.add(loop);
  }
  return loops;
}

double _signedArea(List<Vector3> loop, Vector3 e1, Vector3 e2) {
  var area = 0.0;
  for (var i = 0; i < loop.length; i++) {
    final a = loop[i];
    final b = loop[(i + 1) % loop.length];
    area += a.dot(e1) * b.dot(e2) - b.dot(e1) * a.dot(e2);
  }
  return 0.5 * area;
}

/// Whether the outline's angle about its middle only ever increases: then
/// every ray from the middle meets it once.
bool _starShaped(List<Vector3> loop, double Function(Vector3) angle) {
  var turned = 0.0;
  for (var i = 0; i < loop.length; i++) {
    var d = angle(loop[(i + 1) % loop.length]) - angle(loop[i]);
    if (d <= -math.pi) d += 2 * math.pi;
    if (d > math.pi) d -= 2 * math.pi;
    if (d <= 0.0) return false;
    turned += d;
  }
  return (turned - 2 * math.pi).abs() < 1e-6;
}

/// Ear clipping of a counter-clockwise outline.
List<List<Vector3>> _earClip(List<Vector3> loop, Vector3 e1, Vector3 e2) {
  final points = [...loop];
  final out = <List<Vector3>>[];
  double cross(Vector3 o, Vector3 a, Vector3 b) =>
      (a - o).dot(e1) * (b - o).dot(e2) - (a - o).dot(e2) * (b - o).dot(e1);
  bool insideTriangle(Vector3 p, Vector3 a, Vector3 b, Vector3 c) =>
      cross(a, b, p) >= 0 && cross(b, c, p) >= 0 && cross(c, a, p) >= 0;
  var guard = 0;
  while (points.length > 3 && guard++ < 10000) {
    var clipped = false;
    for (var i = 0; i < points.length; i++) {
      final a = points[(i - 1 + points.length) % points.length];
      final b = points[i];
      final c = points[(i + 1) % points.length];
      if (cross(a, b, c) <= 0) continue;
      var ear = true;
      for (final p in points) {
        if (identical(p, a) || identical(p, b) || identical(p, c)) continue;
        if (insideTriangle(p, a, b, c)) {
          ear = false;
          break;
        }
      }
      if (!ear) continue;
      out.add([a, b, c]);
      points.removeAt(i);
      clipped = true;
      break;
    }
    if (!clipped) break;
  }
  if (points.length == 3) out.add(points);
  return out;
}

/// [t] split in four, [times] over.
List<List<Vector3>> _subdivide(List<Vector3> t, int times) {
  if (times == 0) return [t];
  final ab = (t[0] + t[1]) * 0.5;
  final bc = (t[1] + t[2]) * 0.5;
  final ca = (t[2] + t[0]) * 0.5;
  return [
    for (final small in [
      [t[0], ab, ca],
      [ab, t[1], bc],
      [ca, bc, t[2]],
      [ab, bc, ca],
    ])
      ..._subdivide(small, times - 1),
  ];
}

/// The mesh of a [Jet]'s stream, in the world: each run swept as a tube of
/// elliptical section, [sides] round. Draw it double-sided.
MeshData jetMesh(Jet jet, {int sides = 14}) {
  final builder = MeshBuilder(VertexLayout.standard);
  for (final run in jet.runs) {
    final base = builder.vertexCount;
    for (final s in run) {
      final e1 = (s.across - s.direction * s.across.dot(s.direction))
        ..normalize();
      final e2 = s.direction.cross(e1);
      for (var i = 0; i <= sides; i++) {
        final a = 2.0 * math.pi * i / sides;
        final c = math.cos(a);
        final si = math.sin(a);
        final n =
            (e1 * (c / math.max(s.wide, 1e-9)) +
                  e2 * (si / math.max(s.thick, 1e-9)))
              ..normalize();
        builder.addVertex(
          position: s.position + e1 * (s.wide * c) + e2 * (s.thick * si),
          normal: n,
        );
      }
    }
    final columns = sides + 1;
    for (var k = 0; k + 1 < run.length; k++) {
      for (var i = 0; i < sides; i++) {
        final a = base + k * columns + i;
        builder
          ..addTriangle(a, a + 1, a + columns + 1)
          ..addTriangle(a, a + columns + 1, a + columns);
      }
    }
  }
  return builder.build();
}

/// Particles drawn as small spheres of [radius] round [positions], in the
/// world: an icosahedron split once, forty-two points, round enough at the
/// size of a drop that its outline does not show its faces as the twelve
/// points of a bare icosahedron did.
///
/// [radii], when given, is one radius a sphere, in place of [radius].
MeshData particleMesh(
  List<Vector3> positions,
  double radius, {
  List<double>? radii,
}) {
  final (points, faces) = _sphere;
  final builder = MeshBuilder(VertexLayout.standard);
  for (var i = 0; i < positions.length; i++) {
    final centre = positions[i];
    final r = radii?[i] ?? radius;
    final base = builder.vertexCount;
    for (final v in points) {
      builder.addVertex(position: centre + v * r, normal: v);
    }
    for (final f in faces) {
      builder.addTriangle(base + f.$1, base + f.$2, base + f.$3);
    }
  }
  return builder.build();
}

/// A unit icosahedron split once: each face into four, the new points
/// pushed out onto the sphere.
final (List<Vector3>, List<(int, int, int)>) _sphere = () {
  const t = 1.618033988749895;
  final points = [
    Vector3(-1, t, 0),
    Vector3(1, t, 0),
    Vector3(-1, -t, 0),
    Vector3(1, -t, 0),
    Vector3(0, -1, t),
    Vector3(0, 1, t),
    Vector3(0, -1, -t),
    Vector3(0, 1, -t),
    Vector3(t, 0, -1),
    Vector3(t, 0, 1),
    Vector3(-t, 0, -1),
    Vector3(-t, 0, 1),
  ].map((v) => v.normalized()).toList();
  const faces = <(int, int, int)>[
    (0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), //
    (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6), (7, 1, 8), //
    (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9), //
    (4, 9, 5), (2, 4, 11), (6, 2, 10), (8, 6, 7), (9, 8, 1),
  ];
  final middles = <(int, int), int>{};
  int middle(int a, int b) => middles.putIfAbsent(a < b ? (a, b) : (b, a), () {
    points.add((points[a] + points[b])..normalize());
    return points.length - 1;
  });
  final split = [
    for (final (a, b, c) in faces)
      ...() {
        final ab = middle(a, b), bc = middle(b, c), ca = middle(c, a);
        return [(a, ab, ca), (b, bc, ab), (c, ca, bc), (ab, bc, ca)];
      }(),
  ];
  return (points, split);
}();
