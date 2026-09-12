import 'dart:typed_data';

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:vector_math/vector_math.dart';

/// One [CollisionShape], positioned, for a cloth to push itself out of.
final class ClothObstacle {
  const ClothObstacle(this.shape, this.position);

  final CollisionShape shape;
  final Vector3 position;
}

/// Pushes [point] outside every convex [obstacles] shape it has ended up
/// inside, by [thickness].
///
/// **A point against [CollisionShape.expandedPlanes], grown by nothing.**
/// The class's own doc comment already says growing by a mover's
/// half-extents turns "a box against this shape" into "a point against this
/// shape" — handing [Vector3.zero] for that growth is exactly a particle
/// with no size of its own asking the question. A particle is inside a
/// convex shape when it is on the inward side of every one of its planes;
/// pushed out along whichever plane it is least far past, since that is the
/// shortest way out and the only one that cannot send it through a second
/// face it was also inside of.
///
/// Deliberately narrow: every one of the five [CollisionShape] variants
/// answers [CollisionShape.expandedPlanes] as one convex solid (`partsIn`
/// exists for a shape that is not, and [CollisionHeightfield] is the one
/// that is not) — this function is correct for a box, a sphere, a capsule
/// and a wedge, and gives a heightfield's own bounding box rather than its
/// true, dented surface. Cloth resting on textured ground is out of this
/// package's own first pass; nothing in its own test suite asks for it.
bool pushOutsideObstacle(Vector3 point, ClothObstacle obstacle, double thickness) {
  final shape = obstacle.shape;
  final planeCount = shape.expandedPlaneCount;
  final planes = Float64List(planeCount * 4);
  shape.expandedPlanes(obstacle.position, Vector3.zero(), planes);

  var minMargin = double.infinity;
  var pushX = 0.0, pushY = 0.0, pushZ = 0.0;
  var inside = true;
  for (var p = 0; p < planeCount; p++) {
    final nx = planes[4 * p];
    final ny = planes[4 * p + 1];
    final nz = planes[4 * p + 2];
    final d = planes[4 * p + 3];
    final signedDistance = nx * point.x + ny * point.y + nz * point.z - d;
    if (signedDistance > thickness) {
      inside = false;
      break;
    }
    final margin = thickness - signedDistance;
    if (margin < minMargin) {
      minMargin = margin;
      pushX = nx;
      pushY = ny;
      pushZ = nz;
    }
  }

  if (!inside) return false;
  point.x += pushX * minMargin;
  point.y += pushY * minMargin;
  point.z += pushZ * minMargin;
  return true;
}
