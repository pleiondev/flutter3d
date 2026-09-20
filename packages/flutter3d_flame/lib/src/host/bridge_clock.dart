import 'package:flame/components.dart';
import 'package:flame/game.dart';

/// The one place a bridged game's frame steps flutter3d's own systems,
/// riding Flame's own game loop rather than a second ticker.
///
/// **Why not a `Ticker` of its own.** Flame's `GameWidget` already runs one,
/// synced to vsync, and `FlameGame.update(dt)` fires from it every frame.
/// A second ticker driving flutter3d's side would need its own
/// synchronization with the first to avoid the two drifting apart — the
/// exact class of bug two clocks always risk. Adding this as an ordinary
/// [Component] to the same [FlameGame] instead means there is only ever one
/// clock in a bridged game, and it is the one Flame already owns.
///
/// [Flutter3dFlameWidget] adds one of these to the [FlameGame] it hosts and
/// calls [onTick] with every frame's own `dt`, after every other component's
/// `update` has run — which is what registering it last, the way
/// [Flutter3dFlameWidget] does, guarantees.
final class BridgeClock extends Component {
  BridgeClock({required this.onTick});

  /// Called once a frame with the frame's own delta, in seconds — Flame's
  /// own `dt`, not a second measurement of it.
  final void Function(double dt) onTick;

  @override
  void update(double dt) {
    super.update(dt);
    onTick(dt);
  }
}
