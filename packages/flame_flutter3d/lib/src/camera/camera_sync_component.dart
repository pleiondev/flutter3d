/// [CameraSyncComponent] runs a [CameraSyncController] from Flame's own
/// game loop.
library;

import 'package:flame/components.dart';

import '../host/bridge_priority.dart';
import '../transform/object3d_component.dart' show SyncDirection;
import 'camera_sync_controller.dart';

/// Calls [controller]'s [CameraSyncController.advance] once a frame, as a
/// Flame component.
///
/// **The one-line wrapper [CameraSyncController]'s doc leaves to the
/// caller, written once.** The controller stays a plain class, testable
/// without a game, and a host that already ticks it from
/// `Flutter3dFlameWidget.onTick` keeps doing that. This is for a game that
/// would rather order the sync among its components.
///
/// **Ordered after whatever moves the authoritative side, by default.**
/// Flame updates components by ascending priority. Flowing Flame to the
/// scene, the viewfinder is moved by Flame's own camera, following its
/// target after everything else, so this runs after that camera
/// ([BridgePriority.afterFlameCamera]); synced before it, the 3D camera
/// trailed `camera.follow()` by a frame. Flowing the scene to Flame, it runs
/// after the craft and before Flame's camera reads the viewfinder
/// ([BridgePriority.camera]).
final class CameraSyncComponent extends Component {
  CameraSyncComponent({required this.controller, int? priority})
    : super(
        priority:
            priority ??
            switch (controller.direction) {
              SyncDirection.flameToScene => BridgePriority.afterFlameCamera,
              SyncDirection.sceneToFlame => BridgePriority.camera,
            },
      );

  /// The controller advanced every [update].
  final CameraSyncController controller;

  @override
  void update(double dt) {
    super.update(dt);
    controller.advance(dt);
  }
}
