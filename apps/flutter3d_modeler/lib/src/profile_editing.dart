/// A lathe profile authored as points and curve segments — `ui-13`'s own
/// `profile_editing.dart`, the "чистый Dart" half of the row: no Flutter
/// import here at all, so this is testable without a widget, a device or a
/// gesture.
///
/// **Why a curve rather than the polyline `AddLathe` takes today.** A
/// lathe's own profile is what an artist drags handles on, and a handle
/// belongs to a curve — a polyline has no tangent to drag. `LatheShape`
/// itself only ever wanted a flat list of points, which is what
/// [ProfileCurve.toPolyline] produces; the curve is what the editor keeps
/// and re-flattens after every edit, not what it hands the shape generator.
/// `object_commands.dart`'s own `AddLathe.profile` still stores that flat
/// list — moving it to a [ProfileCurve] is `lathe_dialog.dart`'s own row to
/// finish, along with the widget these types are for; this file is the
/// part of `ui-13` that needed no dialog to be correct.
library;

import 'package:vector_math/vector_math.dart';

/// One authored point on a profile, in the (radius, height) half-plane
/// [AddLathe.profile] is already drawn in.
final class ProfilePoint {
  const ProfilePoint(this.position);

  final Vector2 position;
}

/// How one point connects to the next — a straight line, or a Bezier curve
/// with one or two control points off the line between them.
///
/// **Sealed, not an enum with nullable control fields.** A [LineSegment]
/// has no control point to be null about, and a `switch` over this reads
/// what each shape actually needs rather than a comment saying which
/// fields a `line` leaves alone.
sealed class ProfileSegment {
  const ProfileSegment();
}

/// A straight line to the next point.
final class LineSegment extends ProfileSegment {
  const LineSegment();
}

/// A quadratic Bezier to the next point, pulled toward [control].
final class QuadraticSegment extends ProfileSegment {
  const QuadraticSegment(this.control);

  final Vector2 control;
}

/// A cubic Bezier to the next point, leaving the point before under
/// [control1]'s own pull and arriving at the point after under
/// [control2]'s.
final class CubicSegment extends ProfileSegment {
  const CubicSegment(this.control1, this.control2);

  final Vector2 control1;
  final Vector2 control2;
}

/// A profile: [points] and the [segments] joining each consecutive pair —
/// [points.length] - 1 of them, or [points.length] when [closed] joins the
/// last point back to the first the way a torus's profile does.
final class ProfileCurve {
  ProfileCurve({
    required List<ProfilePoint> points,
    required List<ProfileSegment> segments,
    this.closed = false,
  }) : points = List.unmodifiable(points),
       segments = List.unmodifiable(segments) {
    final wanted = points.length < 2
        ? 0
        : (closed ? points.length : points.length - 1);
    if (segments.length != wanted) {
      throw ArgumentError(
        'ProfileCurve has ${points.length} points and should have $wanted '
        'segments${closed ? ' (closed)' : ''}, not ${segments.length}.',
      );
    }
  }

  final List<ProfilePoint> points;
  final List<ProfileSegment> segments;
  final bool closed;

  /// [points], flattened through every curved [segments] entry into the
  /// polyline `AddLathe.profile` — and `LatheShape` under it — actually
  /// takes. A [LineSegment] contributes only its own endpoint; a Bezier
  /// segment is subdivided until every one of its own control points sits
  /// within [tolerance] of the chord it would otherwise be approximated
  /// by, the ordinary flatness test a curve renderer uses to decide when a
  /// straight line is close enough to stop splitting.
  List<Vector2> toPolyline({double tolerance = 0.01}) {
    if (points.isEmpty) return const <Vector2>[];
    final out = <Vector2>[points.first.position];
    final count = segments.length;
    for (var i = 0; i < count; i++) {
      final from = points[i].position;
      final to = points[(i + 1) % points.length].position;
      _flatten(segments[i], from, to, tolerance, out);
    }
    return out;
  }

  static void _flatten(
    ProfileSegment segment,
    Vector2 from,
    Vector2 to,
    double tolerance,
    List<Vector2> out,
  ) {
    switch (segment) {
      case LineSegment():
        out.add(to);
      case QuadraticSegment(:final control):
        _flattenQuadratic(from, control, to, tolerance, out);
      case CubicSegment(:final control1, :final control2):
        _flattenCubic(from, control1, control2, to, tolerance, out);
    }
  }

  /// Perpendicular distance from [point] to the infinite line through [a]
  /// and [b] — [a] and [b] coincident reads as the distance to that point,
  /// rather than dividing by a zero-length line.
  static double _distanceToLine(Vector2 point, Vector2 a, Vector2 b) {
    final line = b - a;
    final length = line.length;
    if (length < 1e-12) return (point - a).length;
    // |line × (point - a)| / |line|, the 2D cross product's magnitude.
    final toPoint = point - a;
    final cross = (line.x * toPoint.y - line.y * toPoint.x).abs();
    return cross / length;
  }

  static void _flattenQuadratic(
    Vector2 p0,
    Vector2 c,
    Vector2 p1,
    double tolerance,
    List<Vector2> out, {
    int depth = 0,
  }) {
    if (depth >= 24 || _distanceToLine(c, p0, p1) <= tolerance) {
      out.add(p1);
      return;
    }
    // De Casteljau split at t = 0.5.
    final p01 = (p0 + c) * 0.5;
    final p12 = (c + p1) * 0.5;
    final mid = (p01 + p12) * 0.5;
    _flattenQuadratic(p0, p01, mid, tolerance, out, depth: depth + 1);
    _flattenQuadratic(mid, p12, p1, tolerance, out, depth: depth + 1);
  }

  static void _flattenCubic(
    Vector2 p0,
    Vector2 c1,
    Vector2 c2,
    Vector2 p1,
    double tolerance,
    List<Vector2> out, {
    int depth = 0,
  }) {
    final flat =
        _distanceToLine(c1, p0, p1) <= tolerance &&
        _distanceToLine(c2, p0, p1) <= tolerance;
    if (depth >= 24 || flat) {
      out.add(p1);
      return;
    }
    // De Casteljau split at t = 0.5.
    final p01 = (p0 + c1) * 0.5;
    final p12 = (c1 + c2) * 0.5;
    final p23 = (c2 + p1) * 0.5;
    final p012 = (p01 + p12) * 0.5;
    final p123 = (p12 + p23) * 0.5;
    final mid = (p012 + p123) * 0.5;
    _flattenCubic(p0, p01, p012, mid, tolerance, out, depth: depth + 1);
    _flattenCubic(mid, p123, p23, p1, tolerance, out, depth: depth + 1);
  }

  /// The index of whichever [points] entry sits closest to [at], when that
  /// distance is within [radius] — `ui-13`'s own "hit ⌀12" (a radius of 6,
  /// half the diameter the row names). Null when nothing on the profile is
  /// that close, so a tap in empty space adds a point instead of dragging
  /// one that was never under the finger.
  int? nearestPointWithin(Vector2 at, {double radius = 6}) {
    int? best;
    var bestDistance = double.infinity;
    for (var i = 0; i < points.length; i++) {
      final distance = (points[i].position - at).length;
      if (distance <= radius && distance < bestDistance) {
        best = i;
        bestDistance = distance;
      }
    }
    return best;
  }

  /// The index of whichever [segments] entry's own chord — the straight line
  /// between the two points it joins, regardless of what shape the segment
  /// actually draws — sits closest to [at], when that distance is within
  /// [radius]. `profile_editor.dart`'s own `Curve` chip: a drag that starts
  /// near a segment (not a point) is what bends a [LineSegment] into a
  /// [QuadraticSegment], the same [radius] as [nearestPointWithin] because a
  /// segment is picked with the same finger a point is.
  int? nearestSegmentWithin(Vector2 at, {double radius = 6}) {
    int? best;
    var bestDistance = double.infinity;
    for (var i = 0; i < segments.length; i++) {
      final from = points[i].position;
      final to = points[(i + 1) % points.length].position;
      final distance = _distanceToSegment(at, from, to);
      if (distance <= radius && distance < bestDistance) {
        best = i;
        bestDistance = distance;
      }
    }
    return best;
  }

  /// Perpendicular distance from [point] to the segment `a`–`b`, clamped to
  /// the segment itself — unlike [_distanceToLine], a point past either end
  /// reads as the distance to that end rather than to the infinite line
  /// through both.
  static double _distanceToSegment(Vector2 point, Vector2 a, Vector2 b) {
    final ab = b - a;
    final length2 = ab.length2;
    if (length2 < 1e-12) return (point - a).length;
    final t = ((point - a).dot(ab) / length2).clamp(0.0, 1.0);
    final projected = a + ab * t;
    return (point - projected).length;
  }

  /// A copy with the point at [index] moved to [to] — `Point` and `Axis`
  /// mode's own drag, the latter after [snappedToAxis] has already run.
  ProfileCurve withPointMoved(int index, Vector2 to) {
    final next = List<ProfilePoint>.of(points);
    next[index] = ProfilePoint(to);
    return ProfileCurve(points: next, segments: segments, closed: closed);
  }

  /// A copy with a new point at [at] appended, joined to whatever was
  /// previously last by a straight line — `Point` mode's own "an empty tap
  /// adds a point."
  ///
  /// Appending both a point and a [LineSegment] keeps a closed curve closed
  /// without extra bookkeeping: [segments] already reads its own last entry
  /// as "back to point zero" through the `% points.length` in [toPolyline],
  /// so appending reinterprets that entry as reaching the new point instead
  /// and the fresh segment becomes the new closing edge.
  ProfileCurve withPointAdded(Vector2 at) {
    final nextPoints = List<ProfilePoint>.of(points)..add(ProfilePoint(at));
    final nextSegments = List<ProfileSegment>.of(segments);
    if (points.isNotEmpty) nextSegments.add(const LineSegment());
    return ProfileCurve(
      points: nextPoints,
      segments: nextSegments,
      closed: closed,
    );
  }

  /// A copy with the segment at [index] replaced by [segment] — `Curve`
  /// mode's own drag, whether it is bending a straight edge for the first
  /// time or moving a handle that curve already had.
  ProfileCurve withSegment(int index, ProfileSegment segment) {
    final next = List<ProfileSegment>.of(segments);
    next[index] = segment;
    return ProfileCurve(points: points, segments: next, closed: closed);
  }
}

/// [position], pulled onto the axis of revolution (`x = 0`, the left edge of
/// the (radius, height) half-plane every profile is authored in) when it
/// already sits within [snapDistance] of it — `ui-13`'s own "привязка 40".
///
/// **Why the axis and not a grid.** A lathe seals its own seam where the
/// profile meets the axis it turns around; a point that lands at `x = 1e-6`
/// instead of exactly `0` leaves a hairline gap (or a sliver of
/// self-intersecting geometry) at every one of [AddLathe.segments] — a fault
/// invisible in the profile editor and obvious the moment the shape spins.
/// Snapping the one coordinate that seam actually depends on is cheaper and
/// more honest than snapping to an arbitrary grid this row never asked for.
Vector2 snappedToAxis(Vector2 position, {double snapDistance = 40}) =>
    position.x.abs() <= snapDistance ? Vector2(0, position.y) : position;
