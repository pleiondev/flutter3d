/// A named set of plugins an application takes whole and adjusts:
/// [PluginGroup].
library;

import 'manifest.dart';

/// Plugins that go together, in the order they install, at most one per id,
/// taken whole and adjusted where an application needs it to differ:
///
/// ```dart
/// Flutter3dView(
///   plugins: StandardPlugins()
///       .set(BloomAddon(threshold: 1.2))
///       .without<FogAddon>()
///       .add(TrailsPlugin()),
/// )
/// ```
///
/// * [set] puts a configured plugin in place of the member with its id, or
///   at the end when the group has none;
/// * [add] puts one more at the end, and refuses an id the group has;
/// * [without] takes out every member of a type, [withoutId] the member
///   with an id (data plugins share one type and differ by id).
///
/// **A group a release changes does not break the application that adjusts
/// it.** A member that a later minor release drops is not an error to
/// [set] (it is added) or to [without] (nothing is taken out).
///
/// **Immutable.** Each adjustment answers a new group and leaves this one as
/// it was; [plugins] is unmodifiable.
///
/// **One engine's.** A plugin keeps state, so a group is built for the
/// engine that installs it: a group of its own is a class whose constructor
/// makes the plugins (`StandardPlugins()`), and two engines each call it.
/// The project's `lib/plugins.g.dart` is one too, generated from its
/// dependencies' markers and its pubspec's `flutter3d_plugins:` `with:`,
/// `without:` and `set:`.
base class PluginGroup {
  /// A group of [plugins], in order. Throws an [ArgumentError] when two
  /// have one id.
  PluginGroup(Iterable<Flutter3dPlugin> plugins)
    : plugins = List<Flutter3dPlugin>.unmodifiable(plugins) {
    final seen = <String>{};
    for (final plugin in this.plugins) {
      if (!seen.add(plugin.manifest.id)) {
        throw ArgumentError.value(
          plugin.manifest.id,
          'plugins',
          'is the id of two plugins of one group; a group holds one plugin '
              'per id (set replaces one)',
        );
      }
    }
  }

  /// The members, in the order they install.
  final List<Flutter3dPlugin> plugins;

  /// This group with [plugin] in place of the member with its id, or with
  /// [plugin] at the end when no member has it.
  PluginGroup set(Flutter3dPlugin plugin) {
    final id = plugin.manifest.id;
    final at = plugins.indexWhere((Flutter3dPlugin p) => p.manifest.id == id);
    return at < 0
        ? PluginGroup(<Flutter3dPlugin>[...plugins, plugin])
        : PluginGroup(<Flutter3dPlugin>[
            ...plugins.take(at),
            plugin,
            ...plugins.skip(at + 1),
          ]);
  }

  /// This group with [plugin] at the end. Throws an [ArgumentError] when a
  /// member has its id: [set] is the word for a replacement.
  PluginGroup add(Flutter3dPlugin plugin) =>
      PluginGroup(<Flutter3dPlugin>[...plugins, plugin]);

  /// This group without its members of type [T]. A group with none is
  /// answered as it is.
  PluginGroup without<T extends Flutter3dPlugin>() =>
      PluginGroup(<Flutter3dPlugin>[
        for (final p in plugins)
          if (p is! T) p,
      ]);

  /// This group without the member whose manifest id is [id]. A group with
  /// none is answered as it is.
  PluginGroup withoutId(String id) => PluginGroup(<Flutter3dPlugin>[
    for (final p in plugins)
      if (p.manifest.id != id) p,
  ]);

  @override
  String toString() =>
      'PluginGroup(${plugins.map((Flutter3dPlugin p) => p.manifest.id).join(', ')})';
}
