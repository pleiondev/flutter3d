import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

/// What a camera shows this frame: where it is, what it looks at, and how
/// wide.
///
/// **Two points and two numbers, not a matrix.** That is what every camera in
/// the engine already answered with, and what a renderer's camera node takes:
/// `setPositionFrom(shot.eye)`, `lookAt(shot.target)`, a projection made from
/// [fovY]. A matrix would be one more thing to take apart before anybody could
/// blend it.
///
/// Mutable and reused: a director writes into one shot every frame rather than
/// handing out a new one, and a caller that keeps a shot copies it with
/// [setFrom].
final class CameraShot {
  /// A shot at [eye] looking at [target], [fovY] radians wide.
  CameraShot({Vector3? eye, Vector3? target, this.fovY = 1.0, this.roll = 0.0})
    : eye = eye ?? Vector3.zero(),
      target = target ?? Vector3(0.0, 0.0, -1.0);

  /// Where the camera is.
  final Vector3 eye;

  /// What it looks at.
  final Vector3 target;

  /// The vertical field of view, in radians.
  double fovY;

  /// The turn about the line of sight, in radians, for a camera that leans
  /// into a corner. Nought is level; most cameras never change it, and a
  /// renderer that has no roll may ignore it.
  double roll;

  /// Copies [other] into this shot.
  void setFrom(CameraShot other) {
    eye.setFrom(other.eye);
    target.setFrom(other.target);
    fovY = other.fovY;
    roll = other.roll;
  }

  /// Writes the shot [weight] of the way from [from] to [to] into this one.
  ///
  /// **The eye moves in a straight line; the view turns rather than slides.**
  /// Lerping the two targets would aim the camera, halfway through a blend
  /// between two shots looking in opposite directions, at a point between
  /// them that neither of them was looking at — a swing through the floor or
  /// the sky. Here the direction is blended and the distance to the target
  /// separately, so the view sweeps from one heading to the other.
  ///
  /// Safe with this shot being [from] or [to].
  void blend(CameraShot from, CameraShot to, double weight) {
    final w = weight.clamp(0.0, 1.0);
    final fromDir = from.target - from.eye;
    final toDir = to.target - to.eye;
    final fromReach = fromDir.length;
    final toReach = toDir.length;
    if (fromReach > 1e-9) fromDir.scale(1.0 / fromReach);
    if (toReach > 1e-9) toDir.scale(1.0 / toReach);

    final dir = Vector3(
      fromDir.x + (toDir.x - fromDir.x) * w,
      fromDir.y + (toDir.y - fromDir.y) * w,
      fromDir.z + (toDir.z - fromDir.z) * w,
    );
    // Exactly opposite directions cancel halfway: take the destination's
    // rather than looking along nothing.
    if (dir.length2 < 1e-12) dir.setFrom(toDir);
    dir.normalize();
    final reach = fromReach + (toReach - fromReach) * w;

    final fovNow = from.fovY + (to.fovY - from.fovY) * w;
    final rollNow = from.roll + (to.roll - from.roll) * w;
    eye.setValues(
      from.eye.x + (to.eye.x - from.eye.x) * w,
      from.eye.y + (to.eye.y - from.eye.y) * w,
      from.eye.z + (to.eye.z - from.eye.z) * w,
    );
    target
      ..setFrom(eye)
      ..addScaled(dir, math.max(reach, 1e-3));
    fovY = fovNow;
    roll = rollNow;
  }

  @override
  String toString() =>
      'CameraShot(eye: $eye, target: $target, fov: ${fovY.toStringAsFixed(3)})';
}
