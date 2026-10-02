import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import '../portable_math.dart';

/// The inside of a vessel, in its own frame, as far as liquid in it cares:
/// how much it holds below any plane, and the edge of its mouth.
///
/// **A liquid at rest has a flat surface, so this is all there is to it.**
/// Its surface is a plane square to the gravity it feels; where that plane
/// stands follows from the volume, since the volume under it is the volume
/// of liquid; and liquid leaves over the mouth when the plane would have to
/// stand above the mouth's lowest point. So a shape answers one question —
/// the volume below the plane `up · p = height` — and names its [rim].
abstract interface class VesselShape {
  /// The volume inside below the plane `up · p = height`; [up] is a unit
  /// vector in the vessel's frame.
  double volumeBelow(Vector3 up, double height);

  /// The least and greatest `up · p` over the inside: below [low] the plane
  /// holds nothing, above [high] all of it.
  ({double low, double high}) span(Vector3 up);

  /// The edge of the mouth, as points round it; empty for a closed vessel,
  /// which nothing leaves.
  List<Vector3> get rim;

  /// Whether [point] is inside.
  bool contains(Vector3 point);
}

/// The questions a [VesselShape] answers through its volume.
extension VesselVolumes on VesselShape {
  /// The height along [up] at which the plane square to it leaves [volume]
  /// under it: where the surface of that much liquid stands.
  double surfaceFor(Vector3 up, double volume) {
    final (:low, :high) = span(up);
    var lo = low;
    var hi = high;
    for (var i = 0; i < 52; i++) {
      final mid = 0.5 * (lo + hi);
      if (volumeBelow(up, mid) < volume) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return 0.5 * (lo + hi);
  }

  /// The level [volume] stands at in the vessel upright.
  double levelFor(double volume) => surfaceFor(Vector3(0, 1, 0), volume);

  /// The volume upright up to [level].
  double volumeUpTo(double level) => volumeBelow(Vector3(0, 1, 0), level);

  /// The lowest point of the [rim] along [up], and its height: where liquid
  /// leaves first. Null for a closed vessel.
  ({Vector3 point, double height})? lip(Vector3 up) {
    if (rim.isEmpty) return null;
    var best = rim.first;
    var height = up.dot(best);
    for (final p in rim) {
      final h = up.dot(p);
      if (h < height) {
        height = h;
        best = p;
      }
    }
    return (point: best, height: height);
  }

  /// The most the vessel holds with [up] as it is before liquid runs over
  /// its lip; all of it, for a closed one.
  double holds(Vector3 up) {
    final edge = lip(up);
    return edge == null
        ? volumeBelow(up, span(up).high)
        : volumeBelow(up, edge.height);
  }

  /// The most the vessel holds upright.
  double get capacity => holds(Vector3(0, 1, 0));
}

/// A vessel whose inside is a surface of revolution about its Y axis — a
/// test tube, a beaker, a flask: a [wall] profile in the (radius, height)
/// plane, from the middle of the floor up the side to the mouth.
///
/// Cut across its axis it is a disc, and a plane cuts a disc along a chord,
/// so the volume below a plane is a sum of circular segments, slice by
/// slice. Upright it is exact: a straight piece of the profile sweeps a
/// frustum, πΔy(r₀² + r₀r₁ + r₁²)/3.
final class RevolvedVessel implements VesselShape {
  RevolvedVessel(List<Vector2> wall, {this.slices = 240, this.rimPoints = 48})
    : wall = List<Vector2>.unmodifiable(wall) {
    if (wall.length < 2) {
      throw ArgumentError('A wall needs at least two points.');
    }
  }

  final List<Vector2> wall;

  /// How many slices a tilted plane's volume is summed over.
  final int slices;

  /// How many points the [rim] has.
  final int rimPoints;

  late final double floor = wall.map((p) => p.y).reduce(math.min);
  late final double top = wall.map((p) => p.y).reduce(math.max);

  /// The radius of the inside at [height], or nought outside its height.
  double radiusAt(double height) {
    for (var i = 0; i + 1 < wall.length; i++) {
      final a = wall[i];
      final b = wall[i + 1];
      if ((b.y - a.y).abs() < 1e-12) continue;
      final lo = math.min(a.y, b.y);
      final hi = math.max(a.y, b.y);
      if (height < lo || height > hi) continue;
      return a.x + (b.x - a.x) * (height - a.y) / (b.y - a.y);
    }
    return 0.0;
  }

  @override
  bool contains(Vector3 point) {
    if (point.y < floor || point.y > top) return false;
    final r = radiusAt(point.y);
    return point.x * point.x + point.z * point.z < r * r;
  }

  /// The radius of the mouth: the profile's last point.
  double get mouthRadius => wall.last.x;

  @override
  late final List<Vector3> rim = List<Vector3>.unmodifiable([
    for (var i = 0; i < rimPoints; i++)
      Vector3(
        mouthRadius * Portable.cos(2.0 * math.pi * i / rimPoints),
        wall.last.y,
        mouthRadius * Portable.sin(2.0 * math.pi * i / rimPoints),
      ),
  ]);

  @override
  ({double low, double high}) span(Vector3 up) {
    final across = math.sqrt(up.x * up.x + up.z * up.z);
    var lo = double.infinity;
    var hi = -double.infinity;
    for (final p in wall) {
      lo = math.min(lo, up.y * p.y - across * p.x);
      hi = math.max(hi, up.y * p.y + across * p.x);
    }
    return (low: lo, high: hi);
  }

  @override
  double volumeBelow(Vector3 up, double height) {
    final across = math.sqrt(up.x * up.x + up.z * up.z);
    if (across < 1e-9) {
      return up.y > 0.0
          ? _upright(height / up.y)
          : _upright(top) - _upright(height / up.y);
    }
    final dy = (top - floor) / slices;
    var volume = 0.0;
    for (var i = 0; i < slices; i++) {
      final y = floor + (i + 0.5) * dy;
      volume += circularSegment(radiusAt(y), (height - up.y * y) / across) * dy;
    }
    return volume;
  }

  /// The volume up to [level] standing upright: frustum by frustum.
  double _upright(double level) {
    var volume = 0.0;
    for (var i = 0; i + 1 < wall.length; i++) {
      final a = wall[i];
      final b = wall[i + 1];
      if (b.y <= a.y) continue;
      final hi = math.min(b.y, level);
      if (hi <= a.y) break;
      final r1 = a.x + (b.x - a.x) * (hi - a.y) / (b.y - a.y);
      volume += math.pi * (hi - a.y) * (a.x * a.x + a.x * r1 + r1 * r1) / 3.0;
    }
    return volume;
  }
}

/// The area of the part of a disc of [radius] on the near side of a chord
/// [offset] from its centre: none at −radius, half at nought, all at +radius.
double circularSegment(double radius, double offset) {
  if (radius <= 0.0) return 0.0;
  if (offset >= radius) return math.pi * radius * radius;
  if (offset <= -radius) return 0.0;
  return radius * radius * Portable.acos(-offset / radius) +
      offset * math.sqrt(radius * radius - offset * offset);
}

/// A vessel whose inside is any closed triangle mesh: its cavity, closed
/// across the mouth, with the triangles wound counter-clockwise seen from
/// outside the cavity, and the [rim] of the mouth given as points.
///
/// **The volume below a plane is a surface sum** (Gauss): the region below
/// is bounded by the part of the mesh below the plane and by the plane's own
/// cut through it. Summing the signed tetrahedra from a point to every face
/// of that boundary gives its volume; put the point on the plane, and every
/// tetrahedron on the cut is flat and adds nothing. So each triangle is cut
/// to the part below the plane and summed against a point on it, and the cut
/// itself — which for a vessel that is not convex may be several outlines —
/// never has to be found.
final class MeshVessel implements VesselShape {
  MeshVessel({
    required List<Vector3> positions,
    required List<int> indices,
    List<Vector3> rim = const [],
  }) : positions = List<Vector3>.unmodifiable(positions),
       indices = List<int>.unmodifiable(indices),
       rim = List<Vector3>.unmodifiable(rim) {
    if (indices.length % 3 != 0) {
      throw ArgumentError('Indices come in threes.');
    }
  }

  final List<Vector3> positions;
  final List<int> indices;

  @override
  final List<Vector3> rim;

  /// Inside when a ray from [point] crosses the surface an odd number of
  /// times; along a skewed direction, so it does not run along an edge.
  @override
  bool contains(Vector3 point) {
    final ray = Vector3(0.5773, 0.5774, 0.5772)..normalize();
    var crossings = 0;
    for (var t = 0; t < indices.length; t += 3) {
      final a = positions[indices[t]];
      final e1 = positions[indices[t + 1]] - a;
      final e2 = positions[indices[t + 2]] - a;
      final p = ray.cross(e2);
      final det = e1.dot(p);
      if (det.abs() < 1e-12) continue;
      final inv = 1.0 / det;
      final s = point - a;
      final u = s.dot(p) * inv;
      if (u < 0.0 || u > 1.0) continue;
      final q = s.cross(e1);
      final v = ray.dot(q) * inv;
      if (v < 0.0 || u + v > 1.0) continue;
      if (e2.dot(q) * inv > 0.0) crossings++;
    }
    return crossings.isOdd;
  }

  @override
  ({double low, double high}) span(Vector3 up) {
    var lo = double.infinity;
    var hi = -double.infinity;
    for (final p in positions) {
      final h = up.dot(p);
      lo = math.min(lo, h);
      hi = math.max(hi, h);
    }
    return (low: lo, high: hi);
  }

  @override
  double volumeBelow(Vector3 up, double height) {
    final origin = up * height;
    var six = 0.0;
    final kept = <Vector3>[];
    for (var t = 0; t < indices.length; t += 3) {
      kept.clear();
      for (var k = 0; k < 3; k++) {
        final a = positions[indices[t + k]];
        final b = positions[indices[t + (k + 1) % 3]];
        final sa = up.dot(a) - height;
        final sb = up.dot(b) - height;
        if (sa <= 0.0) kept.add(a);
        if ((sa < 0.0) != (sb < 0.0)) {
          kept.add(a + (b - a) * (sa / (sa - sb)));
        }
      }
      for (var k = 1; k + 1 < kept.length; k++) {
        final a = kept[0] - origin;
        final b = kept[k] - origin;
        final c = kept[k + 1] - origin;
        six += a.dot(b.cross(c));
      }
    }
    return six / 6.0;
  }
}
