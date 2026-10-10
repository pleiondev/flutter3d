import 'package:flutter3d_demo_content/shooter_staging.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

/// What a staged crypt stepped by hand publishes, heard on a [DirectBus] for
/// a test to take step by step: the run's own events, and its monsters'
/// animation markers when their strides are an [ActorAnimations].
final class HeardEvents {
  HeardEvents._(Staged staged) {
    bus.onStep<GameEvent>('test.heard', (d) => _events.add(d.event));
    staged.sim.publishTo(bus);
    if (staged.actors.strides case final ActorAnimations animations) {
      animations.events = bus;
    }
  }

  static final Expando<HeardEvents> _of = Expando<HeardEvents>('heard');

  /// The one listening to [staged], made on the first call: what was
  /// published before that is not heard.
  static HeardEvents of(Staged staged) =>
      _of[staged.sim] ??= HeardEvents._(staged);

  /// The bus the run publishes onto.
  final DirectBus bus = DirectBus();

  final List<GameEvent> _events = <GameEvent>[];

  /// Everything published since the last call, oldest first.
  List<GameEvent> take() {
    final taken = List<GameEvent>.of(_events);
    _events.clear();
    return taken;
  }
}
