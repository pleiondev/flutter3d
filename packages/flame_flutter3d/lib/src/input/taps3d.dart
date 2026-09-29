import 'package:flame/components.dart';
import 'package:flame/events.dart';

import '../host/has_flutter3d.dart';
import '../transform/object3d_component.dart';
import '../transform/projector.dart';

/// A bridged component that hears a tap on what it draws in 3D.
///
/// **Flame's own taps land in the wrong place under a perspective camera.**
/// `TapCallbacks` asks a component whether a point is inside it in Flame's
/// coordinates, which are the plane the game plays on. Seen through a
/// perspective 3D camera, the thing that plane position draws is somewhere
/// else on the screen, larger when near and smaller when far, and a tap on
/// the tanker the player can see missed the tanker Flame thinks is there.
/// This asks instead whether the tap falls on the screen rectangle the
/// component's node covers, through the game's [BridgeProjector]; a
/// [Taps3dComponent] in the game hands the tap to the nearest such
/// component under it.
mixin Tap3dCallbacks on Object3dComponent {
  /// The tap at [screen], in logical pixels from the top left, fell on
  /// this component and on nothing nearer.
  void onTap3d(Vector2 screen) {}

  /// Whether [screen] falls on what this component draws, as [projector]
  /// sees it: the screen rectangle round its node and everything under it.
  /// Override for a tighter shape.
  bool hitAt3d(Vector2 screen, BridgeProjector projector) {
    final box = node.subtreeBounds;
    if (box == null) return false;
    final bounds = projector.boundsOf(box);
    return bounds != null &&
        screen.x >= bounds.left &&
        screen.x <= bounds.right &&
        screen.y >= bounds.top &&
        screen.y <= bounds.bottom;
  }
}

/// Covers the game's canvas and hands every tap to the nearest
/// [Tap3dCallbacks] component whose drawing it falls on. Add one to a
/// [HasFlutter3d] game.
///
/// **Nearest to the camera, and one.** Two craft overlapping on the screen
/// are one in front of the other; the tap is for the one in front, and the
/// one behind hears nothing, as a finger on glass would have it. A tap on
/// nothing bridged goes on to whatever else in Flame is under it.
class Taps3dComponent extends PositionComponent
    with TapCallbacks, HasGameReference<HasFlutter3d> {
  Taps3dComponent({super.priority});

  @override
  bool containsLocalPoint(Vector2 point) => true;

  @override
  void onTapDown(TapDownEvent event) {
    final hit = nearestAt(event.canvasPosition);
    if (hit == null) {
      event.continuePropagation = true;
      return;
    }
    hit.onTap3d(event.canvasPosition);
  }

  /// The nearest [Tap3dCallbacks] component drawn under [screen], or null.
  Tap3dCallbacks? nearestAt(Vector2 screen) {
    final eye = game.camera3d.readWorldPosition();
    Tap3dCallbacks? nearest;
    var nearestDistance = double.infinity;
    for (final candidate in game.descendants().whereType<Tap3dCallbacks>()) {
      if (!shownInFlame(candidate)) continue;
      if (!candidate.hitAt3d(screen, game.projector)) continue;
      final box = candidate.node.subtreeBounds!;
      final distance = eye.distanceTo(box.center);
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = candidate;
      }
    }
    return nearest;
  }
}
