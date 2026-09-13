/// The eight sculpting brushes over `SculptMesh`, and mirroring a stroke
/// across the X plane so a symmetric model stays symmetric while it is
/// worked on.
///
/// **One shape, eight meanings.** `SculptMesh.applyBrush` only knows "which
/// vertices, how far from centre" — every brush-specific idea (push along a
/// normal, average toward neighbours, drag rigidly) lives here, as a
/// `Vector3 Function(int, Vector3, double)` built once per stroke and handed
/// to `applyBrush`. Anything a brush needs that is not in that signature —
/// the touched set's average normal, a vertex's own normal, the drag brush's
/// previous centre — is computed once before the call and closed over,
/// rather than recomputed live per vertex: `applyBrush` mutates positions as
/// it goes, and a live `positionOf`/neighbour read partway through a stroke
/// would see some vertices already moved and others not, making the result
/// depend on iteration order. `smooth` matters most here (it reads
/// neighbours), so its neighbour averages are captured up front too.
///
/// **`draw` vs `inflate`.** The distinction sculpting tools conventionally
/// draw between these two is not stroke direction (a brush here never sees
/// one — `SculptMesh` doesn't track a mouse) but *which* normal a vertex
/// moves along: `draw` pushes every touched vertex along one shared
/// direction — the touched set's *average* normal — producing a flat-topped
/// bump the way a stamp would. `inflate` pushes each vertex along its *own*
/// normal, so a rounded patch puffs up like a balloon rather than rising as
/// a plane. Aliasing one to the other loses exactly this.
library;

import 'package:vector_math/vector_math.dart';

import 'sculpt_mesh.dart';

/// Which of the eight sculpting behaviours a [Brush] applies.
///
/// **A final class with named instances, not an enum.** This package is
/// published, and a ninth brush — this list has grown before, from six to
/// eight, over the course of writing `applyBrushStroke` — would be a breaking
/// change for every external `switch` written against an enum's closed set.
/// [BrushKind] instances compare and switch on the same way an enum's values
/// do; what changes is that adding [crossHatch] tomorrow compiles a caller's
/// existing `switch` instead of forcing them to handle a case they cannot
/// yet know about.
final class BrushKind {
  const BrushKind._(this._name);

  final String _name;

  static const BrushKind draw = BrushKind._('draw');
  static const BrushKind clay = BrushKind._('clay');
  static const BrushKind smooth = BrushKind._('smooth');
  static const BrushKind flatten = BrushKind._('flatten');
  static const BrushKind inflate = BrushKind._('inflate');
  static const BrushKind grab = BrushKind._('grab');
  static const BrushKind pinch = BrushKind._('pinch');
  static const BrushKind crease = BrushKind._('crease');

  @override
  String toString() => 'BrushKind.$_name';
}

/// The falloff curve shaping a linear `0..1` radial falloff before a brush
/// uses it, from softest to hardest edge.
///
/// A final class with named instances, for the same reason [BrushKind] is
/// one rather than an enum.
final class BrushFalloff {
  const BrushFalloff._(this._name);

  final String _name;

  static const BrushFalloff linear = BrushFalloff._('linear');
  static const BrushFalloff smooth = BrushFalloff._('smooth');
  static const BrushFalloff sharp = BrushFalloff._('sharp');

  @override
  String toString() => 'BrushFalloff.$_name';
}

/// Reshapes [t] (already `0` at the brush's edge, `1` at its centre) by
/// [falloff]'s curve.
double shapeFalloff(BrushFalloff falloff, double t) {
  final clamped = t.clamp(0.0, 1.0);
  return switch (falloff) {
    BrushFalloff.linear => clamped,
    BrushFalloff.smooth => clamped * clamped * (3 - 2 * clamped),
    BrushFalloff.sharp => clamped * clamped,
    _ => throw ArgumentError.value(falloff, 'falloff', 'not a known BrushFalloff'),
  };
}

/// A sculpting brush: what it does ([kind]), how far it reaches ([radius]),
/// how hard it pushes ([strength]) and how its influence tapers to the edge
/// ([falloff]).
class Brush {
  const Brush({
    required this.kind,
    required this.radius,
    required this.strength,
    this.falloff = BrushFalloff.smooth,
  });

  final BrushKind kind;
  final double radius;
  final double strength;
  final BrushFalloff falloff;
}

/// [vertex]'s own normal: the area-weighted average of the face normals of
/// every triangle in [mesh] that uses it, from [mesh.triangles] and
/// [SculptMesh.positionOf] — the "local normal" several brushes need and
/// `SculptMesh` itself does not compute.
Vector3 vertexNormal(SculptMesh mesh, int vertex) => vertexNormals(mesh, <int>[vertex])[vertex]!;

/// [vertexNormal], for every vertex in [vertices] at once — one pass over
/// [mesh.triangles] rather than one per vertex.
Map<int, Vector3> vertexNormals(SculptMesh mesh, Iterable<int> vertices) {
  final wanted = vertices.toSet();
  final sums = <int, Vector3>{for (final v in wanted) v: Vector3.zero()};
  final triangles = mesh.triangles;
  for (var i = 0; i < triangles.length; i += 3) {
    final a = triangles[i], b = triangles[i + 1], c = triangles[i + 2];
    if (!wanted.contains(a) && !wanted.contains(b) && !wanted.contains(c)) {
      continue;
    }
    final pa = mesh.positionOf(a);
    final pb = mesh.positionOf(b);
    final pc = mesh.positionOf(c);
    final faceNormal = (pb - pa).cross(pc - pa);
    if (wanted.contains(a)) sums[a]!.add(faceNormal);
    if (wanted.contains(b)) sums[b]!.add(faceNormal);
    if (wanted.contains(c)) sums[c]!.add(faceNormal);
  }
  for (final normal in sums.values) {
    if (normal.length2 > 1e-12) normal.normalize();
  }
  return sums;
}

/// The average of [vertexNormals] over [vertices] — the shared direction
/// `draw`, `clay` and `flatten` use instead of each vertex's own normal.
Vector3 averageNormal(SculptMesh mesh, Iterable<int> vertices) {
  final normals = vertexNormals(mesh, vertices);
  final sum = Vector3.zero();
  for (final n in normals.values) {
    sum.add(n);
  }
  if (sum.length2 > 1e-12) sum.normalize();
  return sum;
}

/// [point] reflected across the plane `x = 0`.
Vector3 mirrorAcrossX(Vector3 point) => Vector3(-point.x, point.y, point.z);

/// Applies one stroke of [brush] to [mesh], centred at [center].
///
/// [previousCenter], when given, is where the brush centre was last frame —
/// `grab`'s drag vector is `center - previousCenter`; every other kind
/// ignores it.
///
/// When [symmetryX] is set, the same stroke is also applied mirrored across
/// `x = 0`: centred at [mirrorAcrossX] of [center] (and of [previousCenter],
/// for `grab`), which is what makes it symmetric rather than a second,
/// independent stroke — on a mesh that is itself symmetric about `x = 0`,
/// [SculptMesh.verticesWithinRadius] around the mirrored centre finds exactly
/// the mirror image of the vertices the primary stroke touched, and every
/// brush kind's own local geometry (a vertex's own normal, its neighbours,
/// the direction toward *that* centre) already comes out mirrored there —
/// except `grab`'s drag vector, which is a fixed direction rather than
/// something derived from local geometry, and is mirrored explicitly by
/// mirroring both centres: `mirrorAcrossX(center) - mirrorAcrossX(previous)`
/// negates the drag's X component and keeps its Y/Z, exactly what reflecting
/// a displacement vector (as opposed to a point) across `x = 0` does.
BrushResult applyBrushStroke(
  SculptMesh mesh,
  Brush brush, {
  required Vector3 center,
  Vector3? previousCenter,
  bool symmetryX = false,
}) {
  final primary = _applyOneSide(mesh, brush, center: center, previousCenter: previousCenter);
  if (!symmetryX) return primary;

  final mirroredCenter = mirrorAcrossX(center);
  final mirroredPrevious = previousCenter == null ? null : mirrorAcrossX(previousCenter);
  final mirrored = _applyOneSide(
    mesh,
    brush,
    center: mirroredCenter,
    previousCenter: mirroredPrevious,
  );

  return BrushResult(
    touchedVertices: <int>[...primary.touchedVertices, ...mirrored.touchedVertices],
    touchedChunks: <int>{...primary.touchedChunks, ...mirrored.touchedChunks}.toList(),
  );
}

BrushResult _applyOneSide(
  SculptMesh mesh,
  Brush brush, {
  required Vector3 center,
  required Vector3? previousCenter,
}) {
  switch (brush.kind) {
    case BrushKind.draw:
      final touched = mesh.verticesWithinRadius(center, brush.radius);
      final normal = averageNormal(mesh, touched);
      return mesh.applyBrush(
        center: center,
        radius: brush.radius,
        displace: (vertex, position, falloff) =>
            position + normal * (brush.strength * shapeFalloff(brush.falloff, falloff)),
      );

    case BrushKind.inflate:
      final touched = mesh.verticesWithinRadius(center, brush.radius);
      final normals = vertexNormals(mesh, touched);
      return mesh.applyBrush(
        center: center,
        radius: brush.radius,
        displace: (vertex, position, falloff) =>
            position +
            normals[vertex]! * (brush.strength * shapeFalloff(brush.falloff, falloff)),
      );

    case BrushKind.clay:
      final touched = mesh.verticesWithinRadius(center, brush.radius);
      final normal = averageNormal(mesh, touched);
      // The clamp plane: a fixed "clay level" above the brush centre along
      // the shared normal. A vertex below it is built up toward it; a
      // vertex already above it is pulled back down — buildup that clamps,
      // rather than `draw`'s unbounded push.
      final targetHeight = center.dot(normal) + brush.strength * brush.radius;
      return mesh.applyBrush(
        center: center,
        radius: brush.radius,
        displace: (vertex, position, falloff) {
          final shaped = shapeFalloff(brush.falloff, falloff);
          final height = position.dot(normal);
          final delta = (targetHeight - height) * shaped;
          return position + normal * delta;
        },
      );

    case BrushKind.smooth:
      final touched = mesh.verticesWithinRadius(center, brush.radius);
      final original = <int, Vector3>{};
      for (final vertex in touched) {
        original[vertex] = mesh.positionOf(vertex);
        for (final neighbor in mesh.neighborsOf(vertex)) {
          original.putIfAbsent(neighbor, () => mesh.positionOf(neighbor));
        }
      }
      return mesh.applyBrush(
        center: center,
        radius: brush.radius,
        displace: (vertex, position, falloff) {
          final neighbors = mesh.neighborsOf(vertex);
          if (neighbors.isEmpty) return position;
          final shaped = shapeFalloff(brush.falloff, falloff);
          final average = Vector3.zero();
          for (final neighbor in neighbors) {
            average.add(original[neighbor] ?? mesh.positionOf(neighbor));
          }
          average.scale(1 / neighbors.length);
          final base = original[vertex] ?? position;
          return base + (average - base) * (brush.strength * shaped);
        },
      );

    case BrushKind.flatten:
      final touched = mesh.verticesWithinRadius(center, brush.radius);
      final normal = averageNormal(mesh, touched);
      final planeHeight = center.dot(normal);
      return mesh.applyBrush(
        center: center,
        radius: brush.radius,
        displace: (vertex, position, falloff) {
          final shaped = shapeFalloff(brush.falloff, falloff);
          final aboveplane = position.dot(normal) - planeHeight;
          return position - normal * (aboveplane * brush.strength * shaped);
        },
      );

    case BrushKind.grab:
      final drag = previousCenter == null ? Vector3.zero() : center - previousCenter;
      return mesh.applyBrush(
        center: center,
        radius: brush.radius,
        displace: (vertex, position, falloff) =>
            position + drag * shapeFalloff(brush.falloff, falloff),
      );

    case BrushKind.pinch:
      final touched = mesh.verticesWithinRadius(center, brush.radius);
      final normals = vertexNormals(mesh, touched);
      return mesh.applyBrush(
        center: center,
        radius: brush.radius,
        displace: (vertex, position, falloff) {
          final shaped = shapeFalloff(brush.falloff, falloff);
          final normal = normals[vertex]!;
          final toward = center - position;
          final tangent = toward - normal * toward.dot(normal);
          return position + tangent * (brush.strength * shaped);
        },
      );

    case BrushKind.crease:
      final touched = mesh.verticesWithinRadius(center, brush.radius);
      final normals = vertexNormals(mesh, touched);
      return mesh.applyBrush(
        center: center,
        radius: brush.radius,
        displace: (vertex, position, falloff) {
          final shaped = shapeFalloff(brush.falloff, falloff);
          final normal = normals[vertex]!;
          final toward = center - position;
          final tangent = toward - normal * toward.dot(normal);
          final pinch = tangent * (brush.strength * shaped);
          final fold = normal * (-brush.strength * shaped * brush.radius * 0.25);
          return position + pinch + fold;
        },
      );

    default:
      throw ArgumentError.value(brush.kind, 'brush.kind', 'not a known BrushKind');
  }
}
