import 'dart:math' as math;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

/// A ray, and what it hits.
///
/// **Against the brushes rather than against the collision world**, which is
/// the one decision here worth writing down. Every brush is a box and the
/// physics can already sweep against those, so pointing at the world and asking
/// it looks like the obvious answer — but a brush with `solid: false` never
/// reaches the collision world at all. Those are the mouldings, the painted
/// alcoves, the lip of a step: exactly the decoration somebody opens an editor
/// to move, and it would have been the one thing they could not click on.
abstract final class Picking {
  /// Which brush [from] pointing [along] hits first, or null.
  ///
  /// Ties go to the nearer one; a ray that starts inside a brush hits it at
  /// nought, which is how clicking while stood inside a wall selects the wall.
  static int? brushAt(List<Brush> brushes, Vector3 from, Vector3 along) {
    int? best;
    var nearest = double.infinity;
    for (var index = 0; index < brushes.length; index++) {
      final distance = _hit(brushes[index], from, along);
      if (distance == null || distance >= nearest) continue;
      nearest = distance;
      best = index;
    }
    return best;
  }

  /// How far along [along] the ray enters [brush], or null if it never does.
  ///
  /// The slab test: clip the ray against each pair of parallel faces in turn
  /// and see whether anything is left. A ramp is treated as its whole box,
  /// deliberately — the half a wedge does not fill is still the space somebody
  /// is pointing at when they point at it, and an editor where a ramp can only
  /// be clicked on its lower half would be an editor that feels broken.
  static double? _hit(Brush brush, Vector3 from, Vector3 along) {
    final min = brush.min;
    final max = brush.max;
    var enter = 0.0;
    var leave = double.infinity;

    for (var axis = 0; axis < 3; axis++) {
      final direction = along[axis];
      final origin = from[axis];
      if (direction.abs() < 1e-9) {
        // Parallel to this pair of faces: either it is between them for the
        // whole ray or it never touches the box at all.
        if (origin < min[axis] || origin > max[axis]) return null;
        continue;
      }
      final one = (min[axis] - origin) / direction;
      final other = (max[axis] - origin) / direction;
      enter = math.max(enter, math.min(one, other));
      leave = math.min(leave, math.max(one, other));
      if (enter > leave) return null;
    }
    return enter;
  }

  /// The direction a click at [at] points, given a camera.
  ///
  /// [forward], [right] and [up] are the camera's own axes, [fovY] its vertical
  /// field of view in radians, and [size] the viewport in pixels. Returns a
  /// unit vector in world space.
  ///
  /// Screen coordinates have y downwards and the world has it upwards, which is
  /// the sign nobody gets right first time: a picker that misses this selects
  /// the brush above whatever was clicked, and only above — so it looks like an
  /// aim problem rather than a flipped axis.
  static Vector3 through(
    Vector2 at, {
    required Vector2 size,
    required Vector3 forward,
    required Vector3 right,
    required Vector3 up,
    required double fovY,
  }) {
    final halfHeight = math.tan(fovY / 2.0);
    final halfWidth = halfHeight * (size.x / size.y);
    final x = (at.x / size.x) * 2.0 - 1.0;
    final y = 1.0 - (at.y / size.y) * 2.0;
    return Vector3(
      forward.x + right.x * x * halfWidth + up.x * y * halfHeight,
      forward.y + right.y * x * halfWidth + up.y * y * halfHeight,
      forward.z + right.z * x * halfWidth + up.z * y * halfHeight,
    )..normalize();
  }
}
