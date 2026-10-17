/// The worlds besides the loop's own whose published components the view
/// reads.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

import '../ecs/ecs_world.dart';

/// The worlds besides `EngineLoop.world` whose published components go into
/// `PublishedState`.
///
/// **Why there is more than one world.** A genre's run is staged per level,
/// in a world of its own: its tapes' checkpoints are digests of that world,
/// and two runs can be built side by side — an edit of the level made while
/// the old one still plays. So the run's actors do not move into the loop's
/// world; the genre adds the run's world here instead (`GenrePlugin` does it
/// when its simulation is set), and the view reads them from the same
/// published state as everything else.
///
/// **One owner per component.** Entities are numbered per world, so the same
/// published component id coming from two worlds would put two entities
/// under one handle; building the state refuses it, naming the component.
///
/// Owned by `EngineLoop` (`loop.publishedWorlds`) and handed to plugins as
/// `host.registry<PublishedWorlds>()`.
final class PublishedWorlds extends PluginRegistry {
  /// No world but the loop's.
  PublishedWorlds() : _scope = null, _worlds = <EcsWorld>[];

  PublishedWorlds._scoped(PublishedWorlds of, PluginScope scope)
    : _scope = scope,
      _worlds = of._worlds;

  final PluginScope? _scope;
  final List<EcsWorld> _worlds;

  /// The worlds added, in the order they were added.
  List<EcsWorld> get worlds => List<EcsWorld>.unmodifiable(_worlds);

  /// Publishes [world]'s published components beside the loop's, until the
  /// registration is cancelled.
  Registration add(EcsWorld world) {
    _worlds.add(world);
    final registration = Registration(() => _worlds.remove(world));
    _scope?.track(registration);
    return registration;
  }

  @override
  PublishedWorlds forPlugin(PluginScope scope) =>
      PublishedWorlds._scoped(this, scope);
}
