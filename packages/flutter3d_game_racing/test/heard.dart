import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

/// What a race stepped by hand published, for a test to take step by step.
///
/// Subscribes on a [DirectBus] the race publishes onto from the moment this
/// is made, so nothing the race says before the first [take] is missed.
final class Heard {
  Heard(RacingSimulation simulation) {
    bus.onStep<GameEvent>('test.heard', (d) => _events.add(d.event));
    simulation.publishTo(bus);
  }

  final DirectBus bus = DirectBus();
  final List<GameEvent> _events = <GameEvent>[];

  /// Everything published since the last call, oldest first.
  List<GameEvent> take() {
    final taken = List<GameEvent>.of(_events);
    _events.clear();
    return taken;
  }

  /// Forgets everything published so far.
  void clear() => _events.clear();
}
