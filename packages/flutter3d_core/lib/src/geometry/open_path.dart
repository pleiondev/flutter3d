/// A path through space measured in metres along it, and a road laid on it.
library;

import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'mesh_builder.dart';
import 'mesh_data.dart';
import 'vertex_layout.dart';

/// A path through [points], measured by distance along it: where it is at
/// [s] metres, which way it runs there, and which way is right.
///
/// **A road is not a list of points.** A racing game asks "where is the car
/// eighty metres on" and "which way is the road pointing there", and a
/// list of points answers neither without the arithmetic every such game
/// wrote for itself: which segment, how far into it, and a heading that
/// does not snap at every corner. Distances are cumulative lengths of the
/// straight pieces between [points]; smooth the points first (a
/// `CatmullRom` sampled finely) for a smooth road.
///
/// Right is the tangent crossed with [up], so a path over flat ground has
/// its right on the ground. Beyond either end the path goes straight on.
final class OpenPath {
  OpenPath(List<Vector3> points, {Vector3? up})
    : points = List<Vector3>.unmodifiable(
        points.map((p) => p.clone()).toList(),
      ),
      up = (up ?? Vector3(0.0, 1.0, 0.0)).normalized(),
      _at = Float64List(points.length) {
    if (points.length < 2) {
      throw ArgumentError('A path needs two points; ${points.length} given.');
    }
    for (var i = 1; i < points.length; i++) {
      _at[i] = _at[i - 1] + points[i].distanceTo(points[i - 1]);
    }
    if (!(length > 0.0)) {
      throw ArgumentError('A path whose points are all in one place.');
    }
  }

  final List<Vector3> points;

  /// What right is taken against.
  final Vector3 up;

  /// The distance along the path at each point.
  final Float64List _at;

  /// How long the path is, in metres.
  double get length => _at[_at.length - 1];

  /// The index of the segment holding [s]: the last point at or before it.
  int _segment(double s) {
    if (s <= 0.0) return 0;
    if (s >= length) return points.length - 2;
    var lo = 0;
    var hi = points.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (_at[mid] <= s) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// Where the path is [s] metres along it, into [out] if given.
  Vector3 pointAt(double s, [Vector3? out]) {
    final i = _segment(s);
    final a = points[i];
    final b = points[i + 1];
    final span = _at[i + 1] - _at[i];
    final t = span <= 0.0 ? 0.0 : (s - _at[i]) / span;
    final result = out ?? Vector3.zero();
    Vector3.mix(a, b, t, result);
    return result;
  }

  /// Which way the path runs at [s], a unit vector, into [out] if given.
  ///
  /// Blended between segments near a point, so a heading read every frame
  /// turns through a corner rather than snapping at it.
  Vector3 tangentAt(double s, [Vector3? out]) {
    final i = _segment(s);
    final result = out ?? Vector3.zero();
    result
      ..setFrom(points[i + 1])
      ..sub(points[i]);
    final span = _at[i + 1] - _at[i];
    final t = span <= 0.0 ? 0.0 : ((s - _at[i]) / span).clamp(0.0, 1.0);
    // Past the middle of a segment, lean towards the next one's direction;
    // before it, towards the last one's.
    if (t > 0.5 && i + 2 < points.length) {
      final next = points[i + 2] - points[i + 1];
      result
        ..normalize()
        ..scale(1.5 - t)
        ..add(next.normalized()..scale(t - 0.5));
    } else if (t < 0.5 && i > 0) {
      final last = points[i] - points[i - 1];
      result
        ..normalize()
        ..scale(0.5 + t)
        ..add(last.normalized()..scale(0.5 - t));
    }
    return result..normalize();
  }

  /// Which way is right of the path at [s], a unit vector on the plane
  /// square to [up], into [out] if given.
  Vector3 rightAt(double s, [Vector3? out]) {
    final result = tangentAt(s, out);
    return result
      ..setFrom(result.cross(up))
      ..normalize();
  }
}

/// The strip of road [width] metres across laid along [path] from [from] to
/// [to] metres, cut every [step] metres: a flat mesh facing [OpenPath.up],
/// with texture `u` across the road and `v` along it in metres, so a
/// repeating texture tiles at the same size on every piece.
///
/// **For a road built piece by piece.** A game streaming its track ahead
/// asks for the next hundred metres as they come into view and lets go of
/// the last hundred; pieces cut at the same distances meet edge to edge.
MeshData ribbon(
  OpenPath path, {
  required double from,
  required double to,
  required double width,
  double step = 2.0,
}) {
  if (!(to > from)) throw ArgumentError('A ribbon from $from to $to.');
  if (!(step > 0.0)) throw ArgumentError('A step of $step.');
  final builder = MeshBuilder(VertexLayout.standard);
  final cuts = ((to - from) / step).ceil();
  final at = Vector3.zero();
  final right = Vector3.zero();
  final normal = path.up;
  for (var i = 0; i <= cuts; i++) {
    final s = i == cuts ? to : from + i * step;
    path
      ..pointAt(s, at)
      ..rightAt(s, right);
    for (final side in <double>[-0.5, 0.5]) {
      builder.addVertex(
        position: at + right * (side * width),
        normal: normal,
        texcoord: Vector2(side + 0.5, s),
      );
    }
    if (i > 0) {
      final a = (i - 1) * 2;
      // Wound to face up: left-back, right-back, right-front, left-front.
      builder.addQuad(a, a + 1, a + 3, a + 2);
    }
  }
  return builder.build();
}
