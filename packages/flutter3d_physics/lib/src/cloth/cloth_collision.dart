import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import '../collision_shape.dart';

/// One [CollisionShape], positioned, for a cloth to push itself out of.
final class ClothObstacle {
  const ClothObstacle(this.shape, this.position);

  final CollisionShape shape;
  final Vector3 position;
}

/// Pushes [point] outside [obstacle] by [thickness].
///
/// The `Vector3` door onto [pushParticleOutside], kept for callers that hold
/// one point. The solver itself calls the other, which works on the doubles
/// the cloth keeps rather than rounding every particle through a `Vector3`'s
/// single-precision storage.
bool pushOutsideObstacle(
  Vector3 point,
  ClothObstacle obstacle,
  double thickness, {

  /// The widest reach among the particle's triangles, in metres; see
  /// [pushParticleOutside].
  double span = 0.0,
}) {
  _single[0] = point.x;
  _single[1] = point.y;
  _single[2] = point.z;
  final moved = pushParticleOutside(
    _single,
    0,
    obstacle,
    thickness,
    _push,
    span: span,
  );
  if (moved) point.setValues(_single[0], _single[1], _single[2]);
  return moved;
}

final Float64List _single = Float64List(3);
final Float64List _push = Float64List(3);

/// Pushes particle [i] of [xyz] outside [obstacle] by [thickness], writing the
/// push that was applied into [push]. Answers whether it moved.
///
/// **Each shape answers as itself.** This used to push every shape out through
/// its [CollisionShape.expandedPlanes], which is exact for a box and a wedge
/// and is the bounding cube for a sphere and a capsule — so a sheet dropped on
/// a ball draped over a box — and zero planes for a heightfield, where an
/// empty loop left the push at nought times infinity and every particle NaN.
/// A sphere and a capsule are now the nearest point on their surface, a
/// heightfield is the ground under the particle, and the `switch` over the
/// sealed shape is what makes a sixth shape a compile error here until
/// somebody decides how cloth meets it.
///
/// Only `+ - * /` and `sqrt` reach the result, so the answer is the same bits
/// on every platform.
///
/// **[span] keeps the sheet's triangles outside a round shape, not only its
/// particles.** A triangle whose corners all sit on a sphere of radius `T`
/// has its plane `sqrt(T² - ρ²)` from the centre, where `ρ` is the radius of
/// the circle through its corners, so a flat triangle between particles
/// pushed to `radius + thickness` sags back inside the ball by its
/// sagitta, `T - sqrt(T² - ρ²)`. A sheet of 0.09 m cells on a 0.2 m ball
/// reached 0.35 mm into it, and the ball's own facets showed through the
/// cloth. With [span] as the widest such reach among the particle's own
/// triangles (`ρ`, or half the longest edge of an obtuse one), a sphere and a
/// capsule push the particle far enough that the plane stays half a
/// thickness clear of the surface, and never closer than a whole thickness.
/// Zero keeps the old answer. Boxes, wedges and heightfields ignore it: a
/// triangle lying on one of their faces does not sag through it, though one
/// bent across a box's edge or over a bump can still cut the corner.
bool pushParticleOutside(
  Float64List xyz,
  int i,
  ClothObstacle obstacle,
  double thickness,
  Float64List push, {

  /// The widest reach among the particle's own triangles, in metres.
  double span = 0.0,
}) {
  final o = obstacle.position;
  final px = xyz[3 * i];
  final py = xyz[3 * i + 1];
  final pz = xyz[3 * i + 2];
  push[0] = 0.0;
  push[1] = 0.0;
  push[2] = 0.0;
  switch (obstacle.shape) {
    case CollisionSphere(:final radius):
      return _outOfBall(
        xyz,
        i,
        px - o.x,
        py - o.y,
        pz - o.z,
        _clearing(radius, thickness, span),
        push,
      );
    case final CollisionCapsule capsule:
      // Upright: the nearest point on its segment is one clamp in y, and
      // around that point the capsule is a sphere.
      final ly = py - o.y;
      final h = capsule.halfHeight;
      final cy = ly < -h ? -h : (ly > h ? h : ly);
      return _outOfBall(
        xyz,
        i,
        px - o.x,
        ly - cy,
        pz - o.z,
        _clearing(capsule.radius, thickness, span),
        push,
      );
    case final CollisionHeightfield field:
      // Straight up onto the drawn surface, and only from inside the field's
      // solid slab: a particle deeper than that is under the world, not in
      // the ground. Vertical rather than along the slope's normal, which is
      // what a cloth lying on terrain needs and a steep bank does not quite.
      //
      // Only over the field itself. `heightAt` answers past the edge with the
      // edge's height, which a body walking off the map wants; a cloth hanging
      // over the edge would catch on a ledge nobody can see.
      final half = field.boundsHalfExtents;
      if ((px - o.x).abs() > half.x || (pz - o.z).abs() > half.z) {
        return false;
      }
      final ground = field.heightAt(o, px, pz) + thickness;
      if (py >= ground || py < ground - thickness - field.thickness) {
        return false;
      }
      push[1] = ground - py;
      xyz[3 * i + 1] = ground;
      return true;
    case CollisionBox() || CollisionWedge() || CustomShape():
      final count = obstacle.shape.expandedPlanes(o, _noGrowth, _planes);
      if (count == 0) return false;
      // Inside when on the inward side of every plane; out along whichever
      // plane it is least far past, the shortest way out and the only one
      // that cannot send it through a second face it was also inside of.
      var best = double.infinity;
      var bx = 0.0, by = 0.0, bz = 0.0;
      for (var p = 0; p < count; p++) {
        final nx = _planes[4 * p];
        final ny = _planes[4 * p + 1];
        final nz = _planes[4 * p + 2];
        final signed = nx * px + ny * py + nz * pz - _planes[4 * p + 3];
        if (signed > thickness) return false;
        final margin = thickness - signed;
        if (margin < best) {
          best = margin;
          bx = nx;
          by = ny;
          bz = nz;
        }
      }
      push[0] = bx * best;
      push[1] = by * best;
      push[2] = bz * best;
      xyz[3 * i] = px + push[0];
      xyz[3 * i + 1] = py + push[1];
      xyz[3 * i + 2] = pz + push[2];
      return true;
  }
}

/// Scratch for the plane walk, allocated once: the widest convex shape here
/// (a box) has six planes, a wedge five.
final Float64List _planes = Float64List(4 * 8);
final Vector3 _noGrowth = Vector3.zero();

/// How far from a round shape's core a particle has to sit: at least
/// [radius] plus [thickness], as a particle always has, and far enough that
/// a triangle of circumradius [span] with its corners there keeps its plane
/// half a thickness clear of the surface. See [pushParticleOutside].
///
/// Half, not the whole: the thickness is there so a particle in contact does
/// not chatter in and out of it, and a plane has no contact to chatter. Held
/// to the whole of it, a sheet on a 0.2 m ball rested with its triangles a
/// centimetre off the ball and its corners two. [span] is held to the plane's
/// own radius, because a triangle as wide as the ball cannot wrap it anyway,
/// and a sheet stretched that far should not be thrown clear of it.
double _clearing(double radius, double thickness, double span) {
  final contact = radius + thickness;
  // Written so a NaN span falls through to the old answer as well.
  if (!(span > 0.0)) return contact;
  final plane = radius + 0.5 * thickness;
  final s = span < plane ? span : plane;
  final lifted = math.sqrt(plane * plane + s * s);
  return lifted > contact ? lifted : contact;
}

bool _outOfBall(
  Float64List xyz,
  int i,
  double dx,
  double dy,
  double dz,
  double reach,
  Float64List push,
) {
  final d2 = dx * dx + dy * dy + dz * dz;
  if (d2 >= reach * reach) return false;
  final d = math.sqrt(d2);
  // At the centre every direction is as short as any other; up, so the
  // answer is decided rather than divided by zero.
  final nx = d > 1e-12 ? dx / d : 0.0;
  final ny = d > 1e-12 ? dy / d : 1.0;
  final nz = d > 1e-12 ? dz / d : 0.0;
  final depth = reach - d;
  push[0] = nx * depth;
  push[1] = ny * depth;
  push[2] = nz * depth;
  xyz[3 * i] += push[0];
  xyz[3 * i + 1] += push[1];
  xyz[3 * i + 2] += push[2];
  return true;
}
