import 'plugin_version.dart';

/// A plugin switched on, off or moved, at a step boundary.
///
/// **Written down so a replay makes the same change at the same step.** A
/// plugin switched on from the editor at step 300 changes every step after
/// it; a replay that installed it from the start, or never, is a different
/// run. The loop journals each change it applies and a run file carries the
/// journal.
///
/// [affectsSimulation] says whether any plugin involved touches the
/// simulation. A change that only touches the view is kept for the record
/// and needs no older reader to refuse the file.
///
/// **Not sealed**: a later minor may add a kind of change, so a `switch`
/// over these needs a default. The constructor is private, so the kinds are
/// this library's.
abstract base class PluginChange {
  const PluginChange._({required this.step, required this.affectsSimulation});

  /// The step the change took effect before: it was applied at the boundary
  /// where [step] steps had run.
  final int step;

  final bool affectsSimulation;

  /// The same change at another step — a run file counts from its own
  /// start, the loop from its own.
  PluginChange at(int step);

  Map<String, Object?> toJson();

  /// Reads a change back, or throws a [PluginFormatException] saying why not.
  static PluginChange fromJson(Map<String, Object?> json) {
    final step = json['step'];
    if (step is! int || step < 0) {
      throw PluginFormatException('a plugin change names no step', json);
    }
    final simulation = json['simulation'] == true;
    List<String> names(String key) => switch (json[key]) {
      final List<Object?> list when list.every((e) => e is String) =>
        List<String>.unmodifiable(list.cast<String>()),
      _ => throw PluginFormatException(
        '"$key" is not a list of plugin ids',
        json,
      ),
    };
    String plugin() => switch (json['plugin']) {
      final String id when id.isNotEmpty => id,
      _ => throw PluginFormatException('the change names no plugin', json),
    };
    return switch (json['kind']) {
      'enable' => PluginEnabled(
        step: step,
        plugin: plugin(),
        affectsSimulation: simulation,
      ),
      'disable' => PluginDisabled(
        step: step,
        plugin: plugin(),
        affectsSimulation: simulation,
      ),
      'order' => PluginsReordered(
        step: step,
        order: names('plugins'),
        affectsSimulation: simulation,
      ),
      'set' => PluginsSet(
        step: step,
        order: names('plugins'),
        enabled: names('enabled'),
        affectsSimulation: simulation,
      ),
      final kind => throw PluginFormatException(
        'a plugin change of kind "$kind" is not one this build knows',
        json,
      ),
    };
  }
}

/// [plugin] was switched on and installed.
final class PluginEnabled extends PluginChange {
  const PluginEnabled({
    required super.step,
    required this.plugin,
    required super.affectsSimulation,
  }) : super._();

  final String plugin;

  @override
  PluginEnabled at(int step) => PluginEnabled(
    step: step,
    plugin: plugin,
    affectsSimulation: affectsSimulation,
  );

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': 'enable',
    'step': step,
    'plugin': plugin,
    'simulation': affectsSimulation,
  };

  @override
  bool operator ==(Object other) =>
      other is PluginEnabled && other.step == step && other.plugin == plugin;

  @override
  int get hashCode => Object.hash('enable', step, plugin);

  @override
  String toString() => 'enable $plugin at step $step';
}

/// [plugin] was switched off and everything it registered withdrawn.
final class PluginDisabled extends PluginChange {
  const PluginDisabled({
    required super.step,
    required this.plugin,
    required super.affectsSimulation,
  }) : super._();

  final String plugin;

  @override
  PluginDisabled at(int step) => PluginDisabled(
    step: step,
    plugin: plugin,
    affectsSimulation: affectsSimulation,
  );

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': 'disable',
    'step': step,
    'plugin': plugin,
    'simulation': affectsSimulation,
  };

  @override
  bool operator ==(Object other) =>
      other is PluginDisabled && other.step == step && other.plugin == plugin;

  @override
  int get hashCode => Object.hash('disable', step, plugin);

  @override
  String toString() => 'disable $plugin at step $step';
}

/// The install order became [order]: what breaks ties between plugins'
/// systems and subscribers.
final class PluginsReordered extends PluginChange {
  const PluginsReordered({
    required super.step,
    required this.order,
    required super.affectsSimulation,
  }) : super._();

  final List<String> order;

  @override
  PluginsReordered at(int step) => PluginsReordered(
    step: step,
    order: order,
    affectsSimulation: affectsSimulation,
  );

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': 'order',
    'step': step,
    'plugins': order,
    'simulation': affectsSimulation,
  };

  @override
  String toString() => 'order ${order.join(', ')} at step $step';
}

/// The whole of the plugins' state: the order, and which are on.
///
/// What a recording that begins mid-run writes first, since the plugins
/// may have been switched since the engine started and a replay begins
/// from the engine's defaults.
final class PluginsSet extends PluginChange {
  const PluginsSet({
    required super.step,
    required this.order,
    required this.enabled,
    required super.affectsSimulation,
  }) : super._();

  final List<String> order;
  final List<String> enabled;

  @override
  PluginsSet at(int step) => PluginsSet(
    step: step,
    order: order,
    enabled: enabled,
    affectsSimulation: affectsSimulation,
  );

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': 'set',
    'step': step,
    'plugins': order,
    'enabled': enabled,
    'simulation': affectsSimulation,
  };

  @override
  String toString() =>
      'plugins ${order.join(', ')} with ${enabled.join(', ')} on at step '
      '$step';
}
