import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

/// Where the ears are.
///
/// Position and a basis rather than a matrix, because that is what the two
/// calculations need — a distance and a left-right dot product — and because a
/// game that has a yaw and no camera object should not have to build a matrix
/// to be heard from.
final class AudioListener {
  AudioListener({Vector3? position, Vector3? forward, Vector3? up})
    : position = position?.clone() ?? Vector3.zero(),
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

  /// Points the listener along a direction, whatever produced it.
  ///
  /// [aimAt] takes a yaw and reads it as a first-person camera's: forward is
  /// `(-sin, 0, -cos)`, which is one game's convention baked into the audio
  /// package. A third-person camera whose forward is `(sin, 0, cos)` has to
  /// pass `yaw + pi` and hope, which is how a listener ends up mirrored and
  /// every sound is panned to the wrong ear.
  ///
  /// So a caller that already has a direction hands it over instead of
  /// re-encoding it as an angle for this to decode again.
  void aimAlong(Vector3 at, Vector3 direction) {
    position.setFrom(at);
    forward.setFrom(direction);
    forward.y = 0.0;
    if (forward.length2 < 1e-8) {
      forward.setValues(0.0, 0.0, -1.0);
    } else {
      forward.normalize();
    }
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
