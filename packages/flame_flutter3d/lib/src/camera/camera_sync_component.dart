/// [CameraSyncComponent] runs a [CameraSyncController] from Flame's own
/// game loop.
library;

import 'package:flame/components.dart';

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
/// **Order it after whatever moves the authoritative side.** Flame updates
/// components by ascending priority. A viewfinder that follows the player
/// is moved by the player's update, so with [SyncDirection.flameToScene]
/// this wants a priority above the player's; a flutter3d camera moved by a
/// physics step wants one above the step's.
final class CameraSyncComponent extends Component {
  CameraSyncComponent({required this.controller, super.priority});

  /// The controller advanced every [update].
  final CameraSyncController controller;

  @override
  void update(double dt) {
    super.update(dt);
    controller.advance(dt);
  }
}
