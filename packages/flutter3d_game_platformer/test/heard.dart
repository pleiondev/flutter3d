import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

/// What a run stepped by hand publishes, for a test to take step by step: a
/// [DirectBus], and the events it has carried since the last [take].
final class Heard {
  Heard() {
    bus.onStep<GameEvent>(
      'test.heard',
      (Delivered<GameEvent> delivered) => _events.add(delivered.event),
    );
  }

  /// The bus to hand the run: `sim.publishTo(heard.bus)`, or a runner's
  /// `events`.
  final DirectBus bus = DirectBus();

  final List<GameEvent> _events = <GameEvent>[];

  /// Everything published since the last call, oldest first; empties the
  /// list.
  List<GameEvent> take() {
    final taken = List<GameEvent>.of(_events);
    _events.clear();
    return taken;
  }
}
