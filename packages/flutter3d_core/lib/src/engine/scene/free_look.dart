import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'orbit_controller.dart';

/// Looking around from where the camera stands, and walking it there.
///
/// **A second camera beside [OrbitController], not a mode inside it.** An
/// orbit turns about a point somebody chose; this turns about the camera's
/// own position and then walks it, which is a different motion with a
/// different feel and a different unit — metres a second rather than radians
/// a pixel. `ux-04` asked for it as "RMB held is free-look with WASD", and
/// the reason it is its own piece rather than another branch in the gesture
/// classifier is that a classifier says *what a gesture means*; nothing in
/// one can say how fast a camera walks or what happens when the key is let
/// go.
///
/// **It drives the orbit's own state rather than keeping a pose of its own,
/// and that is the whole trick.** An orbit is a target, two angles and a
/// distance; the eye is wherever those put it. Turning the head is then the
/// same two angles with the *eye* held still instead of the target, and
/// walking is the target sliding — the eye follows it. So there is no handover
/// to write and no drift to reconcile: the moment the right button comes up
/// the orbit is already consistent, orbiting whatever point is [distance]
/// ahead of where the person is now standing, which is the point they were
/// just looking at.
///
/// Holds no Flutter types and no clock; a caller hands [walk] the seconds
/// that passed, which is what makes it steppable by hand in a test.
final class FreeLook {
  FreeLook(this.orbit);

  /// The camera this moves. Both cameras drive the same state on purpose —
  /// see this class's own doc comment.
  final OrbitController orbit;

  /// How fast the keys walk, in scene units a second.
  ///
  /// A scene is in metres by `ImportUnit`'s own convention, so this is about
  /// a brisk walk. Slow enough to place a camera inside a room, fast enough
  /// to cross one.
  double metresPerSecond = 2.5;

  /// The multiplier [walk] applies while a precision modifier is held.
  double slowFactor = 0.25;

  /// The multiplier for the other one, held to cross a large scene.
  double fastFactor = 4.0;

  /// Turns the head, in pixels of pointer travel.
  ///
  /// Takes the same numbers and the same signs [OrbitController.rotate] does,
  /// so a gesture layer that has already decided "this is a look of dx, dy"
  /// hands them over unchanged: the angles move identically, and only what
  /// stays still is different.
  void look(double deltaYaw, double deltaPitch) {
    if (deltaYaw == 0.0 && deltaPitch == 0.0) return;
    final Vector3 eye = _eye();
    orbit.rotate(deltaYaw, deltaPitch);
    // The eye is where it was; the target is [distance] along the new view
    // direction from it. `rotate` has already clamped the pitch, so the
    // offset read back here is the clamped one rather than what was asked
    // for — a look that ran into the pole stops turning instead of sliding
    // the camera sideways along the last legal circle.
    final Vector3 offset = _offset();
    orbit.target.setValues(
      eye.x - offset.x,
      eye.y - offset.y,
      eye.z - offset.z,
    );
    orbit.apply();
  }

  /// Walks the camera for [seconds], along its own axes.
  ///
  /// [forward], [right] and [up] are each −1, 0 or 1 in the usual case — the
  /// keys that are down — but any value is taken, so a gamepad stick can hand
  /// in its own magnitude. Diagonals are normalised, because a camera that
  /// crossed a room faster on the diagonal than straight ahead is one people
  /// learn to hold two keys on.
  ///
  /// [up] is the world's up rather than the camera's, which is the choice a
  /// person notices: rising while looking at the floor should lift the camera
  /// off the floor, not push it into it.
  void walk({
    double forward = 0.0,
    double right = 0.0,
    double up = 0.0,
    required double seconds,
    bool slow = false,
    bool fast = false,
  }) {
    if (seconds <= 0.0) return;
    final double length = math.sqrt(
      forward * forward + right * right + up * up,
    );
    if (length < 1e-9) return;

    final double speed =
        metresPerSecond * (slow ? slowFactor : 1.0) * (fast ? fastFactor : 1.0);
    final double step = speed * seconds / length;

    final Vector3 ahead = _offset()..normalize();
    // The offset points from the target to the eye, so the view direction is
    // its opposite.
    final double sinYaw = math.sin(orbit.yaw);
    final double cosYaw = math.cos(orbit.yaw);
    orbit.target
      ..addScaled(ahead, -forward * step)
      // The same screen-right vector `OrbitController.pan` uses, so "right"
      // means the same direction to both cameras.
      ..addScaled(Vector3(cosYaw, 0.0, -sinYaw), right * step)
      ..addScaled(Vector3(0.0, 1.0, 0.0), up * step);
    orbit.apply();
  }

  /// Where the camera stands right now, from the orbit's own three numbers.
  Vector3 _eye() => orbit.target + _offset();

  /// The vector from the target to the eye — `OrbitController.apply`'s own,
  /// which is why the two agree to the last bit.
  Vector3 _offset() {
    final double cosPitch = math.cos(orbit.pitch);
    return Vector3(
      math.sin(orbit.yaw) * cosPitch,
      math.sin(orbit.pitch),
      math.cos(orbit.yaw) * cosPitch,
    )..scale(orbit.distance);
  }
}
