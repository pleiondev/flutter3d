/// Bodies walking past each other instead of into each other.
///
/// ## Reciprocal velocity obstacles
///
/// Each neighbour rules out the velocities that would bring the two bodies
/// into contact within [Avoidance.timeHorizon] — a cone, cut off near its
/// apex by the horizon — and each body takes half the turning needed to
/// leave it, trusting the other to take the other half. Half of the cone is
/// a half-plane of allowed velocities; the velocity chosen is the one in
/// every half-plane, and within the body's top speed, nearest the one it
/// wanted. Where the half-planes leave nothing, it is the one that breaks
/// them least. This is ORCA, after van den Berg, Guy, Lin and Manocha, and
/// the three linear programs are theirs.
///
/// ## Walls are not here
///
/// The route keeps a body off walls and the controller slides it along
/// them; only other bodies, which move, need predicting.
///
/// ## The same on every machine
///
/// Arithmetic only — products, sums, square roots — in a fixed order over
/// neighbours given in a fixed order. Nothing is kept from one step to the
/// next.
library;

import 'dart:math' as math;

/// One body another steers round: where it is, how it moves, how wide it is,
/// all in plan.
typedef AvoidanceNeighbor = ({
  double x,
  double z,
  double vx,
  double vz,
  double radius,
});

/// A half-plane of allowed velocities: the side of the line through
/// [px], [pz] along [dx], [dz] that is on its left.
final class _Line {
  _Line(this.px, this.pz, this.dx, this.dz);

  /// A point on the line, a velocity's X in metres per second.
  double px;

  /// A point on the line, a velocity's Z in metres per second.
  double pz;

  /// The line's direction, X; unitless, of a unit vector.
  double dx;

  /// The line's direction, Z; unitless, of a unit vector.
  double dz;
}

const double _epsilon = 1e-5;

double _det(double ax, double az, double bx, double bz) => ax * bz - az * bx;

/// How a body picks a velocity that keeps it clear of its neighbours.
final class Avoidance {
  const Avoidance({
    this.timeHorizon = 1.5,
    this.neighborDistance = 5.0,
    this.maxNeighbors = 8,
  }) : assert(timeHorizon > 0.0, 'a horizon of nought sees nothing coming');

  /// How far ahead, in seconds, a contact counts. Longer turns sooner and
  /// wider; shorter lets bodies brush past.
  final double timeHorizon;

  /// Bodies further than this, centre to centre, are not looked at. In
  /// metres.
  final double neighborDistance;

  /// At most this many of the nearest are looked at.
  final int maxNeighbors;

  /// The velocity nearest `(prefX, prefZ)`, no faster than [maxSpeed], that
  /// meets none of [neighbors] within [timeHorizon], for a body of
  /// [radius] at `(x, z)` moving at `(vx, vz)`. [dt] is the step, for a body
  /// that already overlaps one: it is asked to be out by the next.
  (double, double) velocity({
    required double x,
    required double z,
    required double vx,
    required double vz,
    required double radius,
    required double maxSpeed,
    required double prefX,
    required double prefZ,
    required List<AvoidanceNeighbor> neighbors,
    required double dt,
  }) {
    final invHorizon = 1.0 / timeHorizon;
    final lines = <_Line>[
      for (final other in neighbors)
        _lineFor(x, z, vx, vz, radius, other, invHorizon, dt),
    ];
    final result = _Line(prefX, prefZ, 0.0, 0.0);
    final failed = _program2(lines, maxSpeed, prefX, prefZ, false, result);
    if (failed < lines.length) _program3(lines, failed, maxSpeed, result);
    return (result.px, result.pz);
  }

  static _Line _lineFor(
    double x,
    double z,
    double vx,
    double vz,
    double radius,
    AvoidanceNeighbor other,
    double invHorizon,
    double dt,
  ) {
    final rx = other.x - x;
    final rz = other.z - z;
    final relVx = vx - other.vx;
    final relVz = vz - other.vz;
    final distSq = rx * rx + rz * rz;
    final combined = radius + other.radius;
    final combinedSq = combined * combined;

    double dx;
    double dz;
    double ux;
    double uz;
    if (distSq > combinedSq) {
      // Apart: the cone's cut-off circle, or one of its legs.
      final wx = relVx - invHorizon * rx;
      final wz = relVz - invHorizon * rz;
      final wLengthSq = wx * wx + wz * wz;
      final dot1 = wx * rx + wz * rz;
      if (dot1 < 0.0 && dot1 * dot1 > combinedSq * wLengthSq) {
        final wLength = math.sqrt(wLengthSq);
        final unitX = wx / wLength;
        final unitZ = wz / wLength;
        dx = unitZ;
        dz = -unitX;
        final push = combined * invHorizon - wLength;
        ux = push * unitX;
        uz = push * unitZ;
      } else {
        final leg = math.sqrt(distSq - combinedSq);
        if (_det(rx, rz, wx, wz) > 0.0) {
          dx = (rx * leg - rz * combined) / distSq;
          dz = (rx * combined + rz * leg) / distSq;
        } else {
          dx = -(rx * leg + rz * combined) / distSq;
          dz = -(-rx * combined + rz * leg) / distSq;
        }
        final dot2 = relVx * dx + relVz * dz;
        ux = dot2 * dx - relVx;
        uz = dot2 * dz - relVz;
      }
    } else {
      // Already touching: out within the step.
      final invStep = 1.0 / dt;
      final wx = relVx - invStep * rx;
      final wz = relVz - invStep * rz;
      final wLength = math.sqrt(wx * wx + wz * wz);
      final unitX = wLength > 0.0 ? wx / wLength : 1.0;
      final unitZ = wLength > 0.0 ? wz / wLength : 0.0;
      dx = unitZ;
      dz = -unitX;
      final push = combined * invStep - wLength;
      ux = push * unitX;
      uz = push * unitZ;
    }
    return _Line(vx + 0.5 * ux, vz + 0.5 * uz, dx, dz);
  }

  /// The best point on line [i] that the lines before it allow, inside the
  /// circle of [radius]; false when there is none.
  static bool _program1(
    List<_Line> lines,
    int i,
    double radius,
    double optX,
    double optZ,
    bool directionOpt,
    _Line result,
  ) {
    final line = lines[i];
    final dot = line.px * line.dx + line.pz * line.dz;
    final discriminant =
        dot * dot + radius * radius - (line.px * line.px + line.pz * line.pz);
    if (discriminant < 0.0) return false;
    final root = math.sqrt(discriminant);
    var tLeft = -dot - root;
    var tRight = -dot + root;

    for (var j = 0; j < i; j++) {
      final other = lines[j];
      final denominator = _det(line.dx, line.dz, other.dx, other.dz);
      final numerator = _det(
        other.dx,
        other.dz,
        line.px - other.px,
        line.pz - other.pz,
      );
      if (denominator.abs() <= _epsilon) {
        if (numerator < 0.0) return false;
        continue;
      }
      final t = numerator / denominator;
      if (denominator >= 0.0) {
        tRight = math.min(tRight, t);
      } else {
        tLeft = math.max(tLeft, t);
      }
      if (tLeft > tRight) return false;
    }

    final double t;
    if (directionOpt) {
      t = optX * line.dx + optZ * line.dz > 0.0 ? tRight : tLeft;
    } else {
      final along = line.dx * (optX - line.px) + line.dz * (optZ - line.pz);
      t = along < tLeft ? tLeft : (along > tRight ? tRight : along);
    }
    result
      ..px = line.px + t * line.dx
      ..pz = line.pz + t * line.dz;
    return true;
  }

  /// The point nearest the optimum in every half-plane and the circle, into
  /// [result]; the index of the first line that could not be met, or the
  /// count of lines when all were.
  static int _program2(
    List<_Line> lines,
    double radius,
    double optX,
    double optZ,
    bool directionOpt,
    _Line result,
  ) {
    if (directionOpt) {
      result
        ..px = optX * radius
        ..pz = optZ * radius;
    } else if (optX * optX + optZ * optZ > radius * radius) {
      final length = math.sqrt(optX * optX + optZ * optZ);
      result
        ..px = optX / length * radius
        ..pz = optZ / length * radius;
    } else {
      result
        ..px = optX
        ..pz = optZ;
    }
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (_det(line.dx, line.dz, line.px - result.px, line.pz - result.pz) >
          0.0) {
        final keepX = result.px;
        final keepZ = result.pz;
        if (!_program1(lines, i, radius, optX, optZ, directionOpt, result)) {
          result
            ..px = keepX
            ..pz = keepZ;
          return i;
        }
      }
    }
    return lines.length;
  }

  /// When the half-planes leave nothing: the point that breaks the worst of
  /// them least, from line [begin] on.
  static void _program3(
    List<_Line> lines,
    int begin,
    double radius,
    _Line result,
  ) {
    var distance = 0.0;
    for (var i = begin; i < lines.length; i++) {
      final line = lines[i];
      if (_det(line.dx, line.dz, line.px - result.px, line.pz - result.pz) <=
          distance) {
        continue;
      }
      final projected = <_Line>[];
      for (var j = 0; j < i; j++) {
        final other = lines[j];
        final determinant = _det(line.dx, line.dz, other.dx, other.dz);
        double px;
        double pz;
        if (determinant.abs() <= _epsilon) {
          if (line.dx * other.dx + line.dz * other.dz > 0.0) continue;
          px = 0.5 * (line.px + other.px);
          pz = 0.5 * (line.pz + other.pz);
        } else {
          final t =
              _det(other.dx, other.dz, line.px - other.px, line.pz - other.pz) /
              determinant;
          px = line.px + t * line.dx;
          pz = line.pz + t * line.dz;
        }
        final ddx = other.dx - line.dx;
        final ddz = other.dz - line.dz;
        final length = math.sqrt(ddx * ddx + ddz * ddz);
        projected.add(_Line(px, pz, ddx / length, ddz / length));
      }
      final keepX = result.px;
      final keepZ = result.pz;
      if (_program2(projected, radius, -line.dz, line.dx, true, result) <
          projected.length) {
        result
          ..px = keepX
          ..pz = keepZ;
      }
      distance = _det(
        line.dx,
        line.dz,
        line.px - result.px,
        line.pz - result.pz,
      );
    }
  }
}
