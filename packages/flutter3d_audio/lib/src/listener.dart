import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

/// Where the ears are.
///
/// Position and a basis rather than a matrix, because that is what the two
/// calculations need — a distance and a left-right dot product — and because a
/// game that has a yaw and no camera object should not have to build a matrix
/// to be heard from.
final class AudioListener {
  AudioListener({
    Vector3? position,
    Vector3? forward,
    Vector3? up,
  })  : position = position?.clone() ?? Vector3.zero(),
        forward = forward?.clone() ?? Vector3(0.0, 0.0, -1.0),
        up = up?.clone() ?? Vector3(0.0, 1.0, 0.0) {
    _refreshRight();
  }

  final Vector3 position;
  final Vector3 forward;
  final Vector3 up;

  /// Derived, and the only one the panning uses.
  Vector3 get right => _right;
  final Vector3 _right = Vector3(1.0, 0.0, 0.0);

  /// Points the listener the way a first-person camera looks.
  ///
  /// Yaw only. Pitch is deliberately ignored: tilting your head back does not
  /// swap left and right, and feeding pitch into a stereo pan makes a sound
  /// swing across the field when the player looks at the floor.
  void aimAt(Vector3 at, double yaw) {
    position.setFrom(at);
    forward.setValues(-math.sin(yaw), 0.0, -math.cos(yaw));
    up.setValues(0.0, 1.0, 0.0);
    _refreshRight();
  }

  void _refreshRight() {
    _right
      ..setFrom(forward)
      ..crossInto(up, _right);
    // A listener looking straight up has no right; keep the last good one
    // rather than dividing by zero and panning everything hard left.
    if (_right.length2 > 1e-12) _right.normalize();
  }
}
