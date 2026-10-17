import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

/// What a simulation stepped by hand publishes, heard on a [DirectBus] for a
/// test to take step by step.
final class HeardEvents {
  /// Listens to [sim] from now on: what it published before is not heard.
  HeardEvents(GameSimulation sim) {
    bus.onStep<GameEvent>('test.heard', (d) => _events.add(d.event));
    sim.publishTo(bus);
  }

  /// The bus [sim] publishes onto.
  final DirectBus bus = DirectBus();

  final List<GameEvent> _events = <GameEvent>[];

  /// Everything published since the last call, oldest first.
  List<GameEvent> take() {
    final taken = List<GameEvent>.of(_events);
    _events.clear();
    return taken;
  }
}
