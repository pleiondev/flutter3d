import 'package:flutter3d/flutter3d.dart' show PerspectiveProjection;

/// The lens this game is played through.
///
/// **Sixty degrees, not the engine's forty-five**, and a far plane of 220 m
/// rather than a kilometre. The levels are 120 by 260 metres: a kilometre of
/// depth range is spent on nothing while the near end pays for it in precision,
/// and a narrow lens in a third-person platformer hides the ledge you are
/// aiming at just as you commit to the jump.
///
/// **Why this is a class and not two numbers on the camera.** The camera's
/// projection is rebuilt every frame to fold in the speed widening, so
/// something has to say what it widens *from*. For the whole life of the game
/// that something was a second, bare `PerspectiveProjection()` living beside
/// the camera — so both numbers above were overwritten on the first frame and
/// never seen again. Nothing looked wrong in a way anybody could name; the game
/// simply looked worse than it was written to.
///
/// One base and one operation, so there is no second base to disagree with the
/// first. That is the fix; the numbers were never the problem.
abstract final class Lens {
  /// What the camera is built with, and what a widened view returns to.
  static const PerspectiveProjection base =
      PerspectiveProjection(fovYRadians: 1.05, far: 220.0);

  /// The base opened up by [extraFov] radians, for speed.
  ///
  /// Only the field of view moves. A widening that also reset the far plane
  /// would be the same bug in a smaller place.
  static PerspectiveProjection widened(double extraFov) =>
      base.copyWith(fovYRadians: base.fovYRadians + extraFov);
}
