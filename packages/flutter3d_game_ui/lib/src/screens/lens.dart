import 'package:flutter3d_core/flutter3d_core.dart' show PerspectiveProjection;
import 'package:flutter3d_foundation/flutter3d_foundation.dart' show Portable;

/// The lens a game is played through: one base projection, and the only
/// operations that may change it.
///
/// **Why this is a value and not two numbers on the camera.** A game that
/// widens its view for speed rebuilds the camera's projection every frame,
/// so something has to say what it widens *from*. In the game this came from,
/// that something was a second, bare `PerspectiveProjection()` beside the
/// camera, and the field of view and far plane the game was written with
/// were overwritten on the first frame and never seen again. One base and
/// operations that move only the field of view leave no second base to
/// disagree with the first.
///
/// **The field of view by aspect.** [base] is drawn as written on a screen at
/// least [designAspect] wide. On a narrower one, a handset held upright or a
/// square window, the vertical field of view is opened until the horizontal
/// one is what it was at [designAspect], so the ledge or the corner the
/// player was shown on a wide screen is still on a tall one. With no
/// [designAspect] the lens ignores the screen.
final class Lens {
  const Lens(this.base, {this.designAspect});

  /// What the camera is built with, and what a widened view returns to.
  final PerspectiveProjection base;

  /// The narrowest width over height [base] is drawn at unchanged, or null
  /// to draw it unchanged at every aspect. A unitless ratio.
  final double? designAspect;

  /// [base] opened up by [extraFovY] radians, for speed.
  ///
  /// Only the field of view moves. A widening that also reset the far plane
  /// would be the same fault in a smaller place.
  PerspectiveProjection widened(double extraFovY) =>
      base.copyWith(fovY: base.fovY + extraFovY);

  /// The vertical field of view at [aspect], width over height.
  ///
  /// Out of `Portable`'s arithmetic rather than the platform's: a lens is the
  /// view, not the run, but a replay drawn on two machines should frame the
  /// same picture.
  double fovYAt(double aspect) {
    final design = designAspect;
    if (design == null || aspect <= 0.0 || aspect >= design) {
      return base.fovY;
    }
    final halfWidth = Portable.tan(base.fovY / 2.0) * design;
    return 2.0 * Portable.atan(halfWidth / aspect);
  }

  /// [base] for a screen of [aspect], opened by [extraFovY] radians.
  PerspectiveProjection at(double aspect, {double extraFovY = 0.0}) =>
      base.copyWith(fovY: fovYAt(aspect) + extraFovY);
}
