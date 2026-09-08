/// Where two shapes are inside each other, how deep, and which way out.
///
/// ## Exact, because nothing rotates
///
/// Stage one has no angular velocity, so a box is always axis-aligned and the
/// contact between two of them is not a search: it is the overlap on each of
/// three axes, and the way out is the axis with the least of it. The general
/// case — oriented boxes — needs fifteen separating axes and a clipped
/// manifold, and every one of those is a place for a stack to jitter.
///
/// ## One point, not a manifold
///
/// A real solver builds several contact points per pair so that a resting box
/// has a face to sit on rather than a pin to balance on. Without rotation there
/// is nothing to balance: a box with no angular velocity cannot tip, so one
/// point and one normal hold it exactly as still as four would. This is the
/// second thing stage one gets for free from the same decision.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'collision_shape.dart';
import 'tolerances.dart';

/// Two shapes, overlapping.
final class Contact {
  Contact();

  /// Points from A out of B — the direction A must move to separate.
  final Vector3 normal = Vector3.zero();

  /// How far they overlap along [normal].
  ///
  /// **Positive is penetration and negative is a gap**, which is what makes a
  /// stack stand. Reporting a contact only where shapes actually overlap looks
  /// right and is not: the position correction pushes a resting pile apart
  /// until it does not overlap, the next step finds no contact at all, every
  /// crate falls freely for one step, and the pile spends its life dropping a
  /// third of a metre a second and catching itself. Measured — that is exactly
  /// what the first version did, once every sixteen steps.
  double depth = 0.0;

  bool touching = false;

  /// How close counts as a contact. See [depth].
  double margin = 0.02;

  void _set(double nx, double ny, double nz, double depth) {
    if (depth <= -margin) return;
    normal.setValues(nx, ny, nz);
    this.depth = depth;
    touching = true;
  }
}

/// Fills [out] when the two shapes overlap, and clears it when they do not.
///
/// Anything that is not a box, a sphere or a field of ground is treated as its
/// bounding box, which is stated rather than hidden: stage one's dynamic bodies
/// are boxes and spheres, and a capsule in this system is something they are
/// pushed *by* rather than something that is pushed. A monster shoving a crate
/// does it with its bounds, and at these sizes the difference is millimetres.
///
/// **Ground is the exception, and it had to be.** A field of samples has a
/// bounding box the size of the map, so the fallback would have reported every
/// crate on the level as a hundred metres deep inside one solid and launched it
/// out of the side. That is not a smaller error of the same kind; it is the
/// difference between a crate that rests on a hill and a crate that is fired
/// off the edge of the world.
void contactBetween(
  CollisionShape a,
  Vector3 aAt,
  CollisionShape b,
  Vector3 bAt,
  Contact out, {
  double margin = 0.02,
}) {
  out.touching = false;
  out.margin = margin;

  if (a is CollisionHeightfield) {
    _groundBody(a, aAt, b, bAt, out, flip: true);
    return;
  }
  if (b is CollisionHeightfield) {
    _groundBody(b, bAt, a, aAt, out, flip: false);
    return;
  }
  if (a is CollisionSphere && b is CollisionSphere) {
    _sphereSphere(a, aAt, b, bAt, out);
    return;
  }
  if (a is CollisionSphere) {
    _sphereBox(a, aAt, b.boundsHalfExtents, bAt, out, flip: false);
    return;
  }
  if (b is CollisionSphere) {
    _sphereBox(b, bAt, a.boundsHalfExtents, aAt, out, flip: true);
    return;
  }
  _boxBox(a.boundsHalfExtents, aAt, b.boundsHalfExtents, bAt, out);
}

/// A body against a field of ground, prism by prism.
///
/// **The deepest way in, not the nearest triangle.** A body standing where two
/// triangles meet is inside both of them, at two different depths, and the
/// contact that holds it up is the one that has to push furthest. Picking by
/// distance instead would have the solver alternate between the two on
/// successive steps, which is a crate that hums where it should sit still.
///
/// Seams are refused as ways out for the reason [CollisionShape.partSeams]
/// gives, and refusing them matters more here than anywhere else: a crate
/// resting on a hillside is a millimetre inside the ground and a hair's breadth
/// from the join, so the join is very often the nearest face — and a crate
/// pushed sideways along the hill every step is a crate that walks downhill on
/// its own.
void _groundBody(
  CollisionHeightfield field,
  Vector3 fieldAt,
  CollisionShape body,
  Vector3 bodyAt,
  Contact out, {
  required bool flip,
}) {
  final half = body.boundsHalfExtents;
  _probeMin.setValues(
    bodyAt.x - half.x - out.margin,
    bodyAt.y - half.y - out.margin,
    bodyAt.z - half.z - out.margin,
  );
  _probeMax.setValues(
    bodyAt.x + half.x + out.margin,
    bodyAt.y + half.y + out.margin,
    bodyAt.z + half.z + out.margin,
  );
  var count = field.partsIn(fieldAt, _probeMin, _probeMax, _probeParts);
  if (count > _probeParts.length) {
    // A body standing on more than sixteen cells of ground at once is a body
    // bigger than anything a game drops on a hill; when one turns up it gets
    // the triangles that fit rather than a longer buffer on the hot path.
    count = _probeParts.length;
  }

  var deepest = double.negativeInfinity;
  var found = false;
  for (var p = 0; p < count; p++) {
    final part = _probeParts[p];
    final planes = field.partPlanes(part, fieldAt, body, _probePlanes);
    final seams = field.partSeams(part);
    var shallowest = double.infinity;
    var through = -1;
    var gap = 0.0;
    var gapPlane = -1;

    for (var i = 0; i < planes; i++) {
      final base = i * 4;
      final depth =
          _probePlanes[base + 3] -
          (_probePlanes[base] * bodyAt.x +
              _probePlanes[base + 1] * bodyAt.y +
              _probePlanes[base + 2] * bodyAt.z);
      // How far outside this prism the face puts it, over *every* face: past a
      // seam is genuinely past this piece of the ground, even though a seam is
      // never a face a contact is reported on.
      if (-depth > gap) {
        gap = -depth;
        gapPlane = i;
      }
      if ((seams & (1 << i)) != 0) continue;
      if (through < 0 || depth < shallowest) {
        shallowest = depth;
        through = i;
      }
    }

    // Outside the prism: the face it is furthest outside is how far away it is,
    // and a gap inside the margin is still a contact — see [Contact.depth] for
    // why a resting pile needs one. Outside past a seam, though, is the next
    // triangle's business rather than this one's.
    if (gapPlane >= 0 && (seams & (1 << gapPlane)) != 0) continue;
    final depth = gapPlane >= 0 ? -gap : shallowest;
    final plane = gapPlane >= 0 ? gapPlane : through;
    if (plane < 0 || depth <= deepest) continue;
    deepest = depth;
    found = true;
    _probeNormal.setValues(
      _probePlanes[plane * 4],
      _probePlanes[plane * 4 + 1],
      _probePlanes[plane * 4 + 2],
    );
  }

  if (!found) return;
  _emit(out, _probeNormal.x, _probeNormal.y, _probeNormal.z, deepest, flip);
}

/// Scratch for [_groundBody], which is asked once per body per step and must
/// not allocate on the way.
final Vector3 _probeMin = Vector3.zero();
final Vector3 _probeMax = Vector3.zero();
final Vector3 _probeNormal = Vector3.zero();
final Int32List _probeParts = Int32List(32);
final Float64List _probePlanes = Float64List(20);

void _sphereSphere(
  CollisionSphere a,
  Vector3 aAt,
  CollisionSphere b,
  Vector3 bAt,
  Contact out,
) {
  final dx = aAt.x - bAt.x;
  final dy = aAt.y - bAt.y;
  final dz = aAt.z - bAt.z;
  final reach = a.radius + b.radius;
  final within = reach + out.margin;
  final squared = dx * dx + dy * dy + dz * dz;
  if (squared >= within * within) return;

  final distance = math.sqrt(squared);
  if (distance < Nearly.still) {
    // Exactly concentric, which has no direction of its own. Up is chosen
    // because a stack of two crates spawned at the same place should come
    // apart vertically rather than shoot sideways.
    out._set(0.0, 1.0, 0.0, reach);
    return;
  }
  out._set(dx / distance, dy / distance, dz / distance, reach - distance);
}

void _sphereBox(
  CollisionSphere sphere,
  Vector3 sphereAt,
  Vector3 half,
  Vector3 boxAt,
  Contact out, {
  required bool flip,
}) {
  final cx = (sphereAt.x - boxAt.x).clamp(-half.x, half.x);
  final cy = (sphereAt.y - boxAt.y).clamp(-half.y, half.y);
  final cz = (sphereAt.z - boxAt.z).clamp(-half.z, half.z);

  var dx = sphereAt.x - (boxAt.x + cx);
  var dy = sphereAt.y - (boxAt.y + cy);
  var dz = sphereAt.z - (boxAt.z + cz);
  final squared = dx * dx + dy * dy + dz * dz;

  if (squared > Nearly.parallel) {
    final reach = sphere.radius + out.margin;
    if (squared >= reach * reach) return;
    final distance = math.sqrt(squared);
    dx /= distance;
    dy /= distance;
    dz /= distance;
    _emit(out, dx, dy, dz, sphere.radius - distance, flip);
    return;
  }

  // The centre is inside the box: the nearest face is the way out, and the
  // depth is the whole radius plus how far in the centre is.
  final ox = half.x - (sphereAt.x - boxAt.x).abs();
  final oy = half.y - (sphereAt.y - boxAt.y).abs();
  final oz = half.z - (sphereAt.z - boxAt.z).abs();
  if (ox <= oy && ox <= oz) {
    final sign = sphereAt.x >= boxAt.x ? 1.0 : -1.0;
    _emit(out, sign, 0.0, 0.0, ox + sphere.radius, flip);
  } else if (oy <= oz) {
    final sign = sphereAt.y >= boxAt.y ? 1.0 : -1.0;
    _emit(out, 0.0, sign, 0.0, oy + sphere.radius, flip);
  } else {
    final sign = sphereAt.z >= boxAt.z ? 1.0 : -1.0;
    _emit(out, 0.0, 0.0, sign, oz + sphere.radius, flip);
  }
}

void _boxBox(
  Vector3 aHalf,
  Vector3 aAt,
  Vector3 bHalf,
  Vector3 bAt,
  Contact out,
) {
  final margin = out.margin;
  final ox = (aHalf.x + bHalf.x) - (aAt.x - bAt.x).abs();
  if (ox <= -margin) return;
  final oy = (aHalf.y + bHalf.y) - (aAt.y - bAt.y).abs();
  if (oy <= -margin) return;
  final oz = (aHalf.z + bHalf.z) - (aAt.z - bAt.z).abs();
  if (oz <= -margin) return;

  // The axis of least overlap is the shortest way out, and with no rotation it
  // is also the right way out: a crate resting on a floor overlaps it by a
  // millimetre vertically and by metres horizontally, and vertical is the
  // answer.
  if (ox <= oy && ox <= oz) {
    out._set(aAt.x >= bAt.x ? 1.0 : -1.0, 0.0, 0.0, ox);
  } else if (oy <= oz) {
    out._set(0.0, aAt.y >= bAt.y ? 1.0 : -1.0, 0.0, oy);
  } else {
    out._set(0.0, 0.0, aAt.z >= bAt.z ? 1.0 : -1.0, oz);
  }
}

void _emit(
  Contact out,
  double nx,
  double ny,
  double nz,
  double depth,
  bool flip,
) {
  if (flip) {
    out._set(-nx, -ny, -nz, depth);
  } else {
    out._set(nx, ny, nz, depth);
  }
}
