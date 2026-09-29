import 'package:flame/camera.dart';
import 'package:flame/components.dart' show Vector2;

import '../transform/plane.dart';
import '../transform/projector.dart';

/// A Flame [Viewfinder] that maps the screen to the game's plane through the
/// 3D camera, so Flame's own events land where the player sees things.
///
/// **What Flame gets wrong under a perspective camera.** A `CameraComponent`
/// turns a point on the screen into a world point with its viewfinder's
/// affine transform: an offset, a zoom, a turn. A perspective 3D camera does
/// not draw the plane that way, so a tap on a craft reached Flame as a
/// point metres away from it, and a component's `TapCallbacks`, a
/// `camera.globalToLocal` in the game's own code, and Flame's hit test all
/// missed. Here a screen point becomes the point of [plane] under it, found
/// by [projector], and a plane point becomes where it is drawn. A point
/// that meets no plane, the sky, comes back as NaN and hits nothing.
///
/// **Events and conversions, not drawing.** Flame still draws its world
/// through the affine transform; a bridged game draws its world in 3D and
/// keeps Flame's drawing to the viewport, where this changes nothing.
///
///     camera = CameraComponent(
///       world: world,
///       viewfinder: ProjectedViewfinder(projector: projector, plane: plane),
///     );
class ProjectedViewfinder extends Viewfinder {
  ProjectedViewfinder({required this.projector, required this.plane});

  /// The plane the game plays on.
  final BridgePlane plane;

  /// Between the 3D camera and the screen.
  final BridgeProjector projector;

  @override
  Vector2 globalToLocal(Vector2 point, {Vector2? output}) {
    final onPlane = projector.onPlane(point, plane);
    final result = output ?? Vector2.zero();
    if (onPlane == null) {
      return result..setValues(double.nan, double.nan);
    }
    return result..setFrom(onPlane);
  }

  @override
  Vector2 localToGlobal(Vector2 point, {Vector2? output}) {
    final screen = projector.toScreen(plane.to3d(point));
    final result = output ?? Vector2.zero();
    if (screen == null) {
      return result..setValues(double.nan, double.nan);
    }
    return result..setFrom(screen);
  }
}
