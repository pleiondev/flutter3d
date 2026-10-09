/// The engine's [SimulationQueryRegistry]: the questions a view asks by name.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

import 'simulation_handle.dart';

/// The questions a simulation answers by name, for `SimulationHandle.ask`.
///
/// Owned by `EngineLoop` (`loop.queries`) and handed to plugins as
/// `host.registry<SimulationQueryRegistry>()`. Answered by `LocalSimulation`
/// between two steps; a handle for a simulation in another isolate sends the
/// name and the arguments across and runs the same answer there, which is
/// why an answer is registered where the world is and never sent with the
/// question.
final class SimQueries extends SimulationQueryRegistry {
  /// An empty registry.
  SimQueries() : _scope = null, _answers = <(String, SimulationAnswer)>[];

  SimQueries._scoped(SimQueries of, PluginScope scope)
    : _scope = scope,
      _answers = of._answers;

  final PluginScope? _scope;
  final List<(String, SimulationAnswer)> _answers;

  @override
  Registration add(String name, SimulationAnswer answer) {
    if (answerFor(name) != null) {
      throw ArgumentError.value(
        name,
        'name',
        'a question named "$name" is already answered; a name is unique in '
            'one engine, so prefix it with the plugin id',
      );
    }
    final entry = (name, answer);
    _answers.add(entry);
    final registration = Registration(() => _answers.remove(entry));
    _scope?.track(registration);
    return registration;
  }

  @override
  SimulationAnswer? answerFor(String name) {
    for (final (registered, answer) in _answers) {
      if (registered == name) return answer;
    }
    return null;
  }

  @override
  List<String> get names => <String>[for (final (name, _) in _answers) name];

  @override
  SimulationQueryRegistry forPlugin(PluginScope scope) =>
      SimQueries._scoped(this, scope);
}
