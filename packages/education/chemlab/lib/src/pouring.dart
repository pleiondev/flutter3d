import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:vector_math/vector_math.dart';

import 'optics.dart' show radiusAt;

/// Liquid in glass tipped too far for its surface to be a height over the
/// floor: half poured out of a tube, or lying along it.
///
/// **The surface is a plane, and where it stands follows from the volume.**
/// The liquid's surface is level in the world, so in the glass's own frame
/// it is the plane whose normal is the world's up seen from the glass, and
/// its height along that normal is whatever leaves the liquid's volume
/// under it. A vessel here is a surface of revolution, so cut across its
/// axis it is a disc, and a plane cuts a disc along a chord: the volume
/// under the plane is the sum, slice by slice, of circular segments, whose
/// area has a closed form. Liquid leaves the glass when that plane would
/// have to stand above the lowest point of the mouth: what is above it runs
/// out over the lip.

/// The area of the part of a disc of [radius] on the near side of a chord
/// [offset] from its centre: none at −radius, all of it at +radius.
double segmentArea(double radius, double offset) {
  if (radius <= 0.0) return 0.0;
  if (offset >= radius) return math.pi * radius * radius;
  if (offset <= -radius) return 0.0;
  return radius * radius * math.acos(-offset / radius) +
      offset * math.sqrt(radius * radius - offset * offset);
}

/// The volume inside [wall] — a profile from the middle of the floor up the
/// side, in the vessel's frame — below the plane `up · p = height`.
double volumeBelow(
  List<Vector2> wall,
  Vector3 up,
  double height, {
  int slices = 240,
}) {
  final floor = wall.first.y;
  final top = wall.map((p) => p.y).reduce(math.max);
  final across = math.sqrt(up.x * up.x + up.z * up.z);
  final dy = (top - floor) / slices;
  var volume = 0.0;
  // Upright, each slice is under the plane or not, and the one the plane
  // crosses counts for the part of it below: a slice at a time would make
  // the volume a staircase, and a little poured in would be lost in a step.
  final ceiling = across < 1e-9 ? height / up.y : double.infinity;
  for (var i = 0; i < slices; i++) {
    final y0 = floor + i * dy;
    final y = y0 + 0.5 * dy;
    final r = radiusAt(wall, y) ?? 0.0;
    if (across < 1e-9) {
      final below = ((ceiling - y0) / dy).clamp(0.0, 1.0);
      volume += math.pi * r * r * dy * below;
    } else {
      volume += segmentArea(r, (height - up.y * y) / across) * dy;
    }
  }
  return volume;
}

/// The volume inside [wall] up to [level], standing upright.
double volumeUpTo(List<Vector2> wall, double level) =>
    volumeBelow(wall, Vector3(0, 1, 0), level);

/// The level an upright vessel with inside [wall] is filled to by [volume].
double levelFor(List<Vector2> wall, double volume) {
  var lo = wall.first.y;
  var hi = wall.map((p) => p.y).reduce(math.max);
  for (var i = 0; i < 40; i++) {
    final mid = 0.5 * (lo + hi);
    if (volumeUpTo(wall, mid) < volume) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return 0.5 * (lo + hi);
}

/// The height along [up] at which the plane leaves [volume] under it.
double surfaceFor(List<Vector2> wall, Vector3 up, double volume) {
  // The plane's range over the vessel: every point of the profile, swept.
  var lo = double.infinity;
  var hi = -double.infinity;
  final across = math.sqrt(up.x * up.x + up.z * up.z);
  for (final p in wall) {
    lo = math.min(lo, up.y * p.y - across * p.x);
    hi = math.max(hi, up.y * p.y + across * p.x);
  }
  for (var i = 0; i < 40; i++) {
    final mid = 0.5 * (lo + hi);
    if (volumeBelow(wall, up, mid) < volume) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return 0.5 * (lo + hi);
}

/// The liquid inside [wall] below the plane `up · p = height`, as a mesh: the
/// inside of the glass swept as a lathe and cut by the plane, and the flat
/// surface the cut leaves, facing up.
///
/// A triangle the plane crosses is cut to the part below it (Sutherland and
/// Hodgman, one plane), which keeps its winding; the points where its edges
/// cross the plane are the surface's outline, which is convex for the round
/// glass here and is closed with a fan round its middle.
MeshData cutLiquid({
  required List<Vector2> wall,
  required Vector3 up,
  required double height,
  int segments = 48,
  int rows = 40,
}) {
  // The wall resampled evenly along its length, with the normal of the
  // stretch each row lies on.
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
          : Vector2(0.0, -1.0),
    ));
  }

  final builder = MeshBuilder(VertexLayout.standard);
  final outline = <Vector3>[];
  double side(Vector3 p) => up.dot(p) - height;

  void emit(List<({Vector3 p, Vector3 n})> polygon) {
    if (polygon.length < 3) return;
    final first = builder.addVertex(
      position: polygon[0].p,
      normal: polygon[0].n,
    );
    var previous = builder.addVertex(
      position: polygon[1].p,
      normal: polygon[1].n,
    );
    for (var i = 2; i < polygon.length; i++) {
      final next = builder.addVertex(
        position: polygon[i].p,
        normal: polygon[i].n,
      );
      builder.addTriangle(first, previous, next);
      previous = next;
    }
  }

  void triangle(List<({Vector3 p, Vector3 n})> corners) {
    final kept = <({Vector3 p, Vector3 n})>[];
    for (var i = 0; i < 3; i++) {
      final a = corners[i];
      final b = corners[(i + 1) % 3];
      final sa = side(a.p);
      final sb = side(b.p);
      if (sa <= 0.0) kept.add(a);
      if ((sa < 0.0) != (sb < 0.0)) {
        final t = sa / (sa - sb);
        final p = a.p + (b.p - a.p) * t;
        kept.add((p: p, n: (a.n + (b.n - a.n) * t)..normalize()));
        outline.add(p);
      }
    }
    emit(kept);
  }

  ({Vector3 p, Vector3 n}) at(int column, int row) {
    final angle = 2.0 * math.pi * column / segments;
    final c = math.cos(angle);
    final s = math.sin(angle);
    final (:p, :n) = profile[row];
    return (
      p: Vector3(p.x * c, p.y, p.x * s),
      n: Vector3(n.x * c, n.y, n.x * s),
    );
  }

  // The lathe's winding (a, d, b) and (b, d, c), so faces look out.
  for (var i = 0; i < segments; i++) {
    for (var j = 0; j < rows; j++) {
      final a = at(i, j);
      final b = at(i + 1, j);
      final c = at(i + 1, j + 1);
      final d = at(i, j + 1);
      if (profile[j].p.x > 0.0) triangle([a, d, b]);
      if (profile[j + 1].p.x > 0.0) triangle([b, d, c]);
    }
  }

  // The surface: the outline round its middle, in order of angle about up,
  // counter-clockwise seen from above, so the fan faces up.
  if (outline.length >= 3) {
    final middle =
        outline.fold(Vector3.zero(), (sum, p) => sum + p) /
        outline.length.toDouble();
    final helper = up.x.abs() < 0.9 ? Vector3(1, 0, 0) : Vector3(0, 0, 1);
    final e1 = up.cross(helper)..normalize();
    final e2 = up.cross(e1);
    double angle(Vector3 p) {
      final d = p - middle;
      return math.atan2(d.dot(e1), d.dot(e2));
    }

    final ordered = [...outline]..sort((a, b) => angle(a).compareTo(angle(b)));
    final normal = up.normalized();
    final centre = builder.addVertex(position: middle, normal: normal);
    final ring = [
      for (final p in ordered) builder.addVertex(position: p, normal: normal),
    ];
    for (var i = 0; i < ring.length; i++) {
      final a = ring[i];
      final b = ring[(i + 1) % ring.length];
      // Whichever order faces up.
      final pa = ordered[i] - middle;
      final pb = ordered[(i + 1) % ring.length] - middle;
      if (pa.cross(pb).dot(up) >= 0.0) {
        builder.addTriangle(centre, a, b);
      } else {
        builder.addTriangle(centre, b, a);
      }
    }
  }
  return builder.build();
}

/// A stream of liquid falling from [lip] to the height [floor]: thrown out
/// at [speed] along [out], horizontal, and falling freely, so it curves
/// down and narrows as it speeds up. [flow] is how much passes a second; a
/// steady stream carries the same flow at every height, so its section is
/// the flow over its speed there, and its radius goes as one over the root
/// of the speed.
MeshData stream({
  required Vector3 lip,
  required Vector3 out,
  required double floor,
  required double flow,
  double speed = 0.5,
  int sides = 14,
  int rows = 24,
}) {
  const g = 9.81;
  final fall = math.max(lip.y - floor, 1e-3);
  final duration = math.sqrt(2.0 * fall / g);
  final r0 = math.sqrt(flow / (math.pi * speed));
  final builder = MeshBuilder(VertexLayout.standard);
  for (var k = 0; k <= rows; k++) {
    final t = duration * k / rows;
    final centre = lip + out * (speed * t) - Vector3(0, 0.5 * g * t * t, 0);
    final velocity = out * speed - Vector3(0, g * t, 0);
    final v = velocity.length;
    final r = r0 * math.sqrt(speed / v);
    final axis = velocity / v;
    final helper = axis.x.abs() < 0.9 ? Vector3(1, 0, 0) : Vector3(0, 0, 1);
    final e1 = axis.cross(helper)..normalize();
    final e2 = axis.cross(e1);
    for (var i = 0; i <= sides; i++) {
      final a = 2.0 * math.pi * i / sides;
      final n = e1 * math.cos(a) + e2 * math.sin(a);
      builder.addVertex(position: centre + n * r, normal: n);
    }
  }
  final columns = sides + 1;
  for (var k = 0; k < rows; k++) {
    for (var i = 0; i < sides; i++) {
      final a = k * columns + i;
      final b = a + 1;
      final c = a + columns + 1;
      final d = a + columns;
      // Drawn from both sides: its material is double-sided, so which way
      // these wind does not matter.
      builder
        ..addTriangle(a, b, c)
        ..addTriangle(a, c, d);
    }
  }
  return builder.build();
}
