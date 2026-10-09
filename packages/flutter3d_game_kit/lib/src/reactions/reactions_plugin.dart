import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

import 'reaction.dart';
import 'reaction_table.dart';

/// A [ReactionTable] heard from the engine's bus, on the frame channel.
///
/// **A view plugin.** It subscribes to every event once a frame, after the
/// frame's steps, and writes what the table makes of them into one pending
/// [Reaction] the game takes with [drain] and performs: bursts into its
/// particles, jolts onto its camera, the flash into its HUD. Nothing it does
/// reaches the simulation, so switching it off is not written into a replay.
///
/// **A rollback shows nothing twice.** The frame channel hands out a step run
/// again only when it differs from what was shown; such an event is
/// [Delivered.resimulated], and this skips it unless [showCorrections] is
/// set — sparks for a hit the rollback took back are already on screen, and a
/// second burst would be wrong both ways.
///
/// ```dart
/// final reactions = ReactionsPlugin(table);
/// final loop = EngineLoop(input: input, plugins: [genre, reactions]);
/// // every frame:
/// reactions.take()
///   ..showIn(particles)
///   ..feel(camera.rig);
/// ```
final class ReactionsPlugin extends Flutter3dPlugin {
  ReactionsPlugin(
    this.table, {
    this.id = 'flutter3d_addon_reactions',
    this.showCorrections = false,
  });

  /// What each event looks like: the game's own table.
  final ReactionTable table;

  /// The plugin's id. Two tables in one engine need two.
  final String id;

  /// Whether an event a rollback changed is shown when it arrives again.
  final bool showCorrections;

  final ReactionBuilder _pending = ReactionBuilder();

  @override
  PluginManifest get manifest => PluginManifest(
    id: id,
    apiVersion: const PluginApiVersion(1, 0),
    touches: PluginTouches.view,
    description: 'Bursts, camera jolts, haptics and flashes for events.',
  );

  @override
  void install(PluginHost host) {
    host.events.onFrame<BusEvent>('$id.react', (Delivered<BusEvent> delivered) {
      if (delivered.resimulated && !showCorrections) return;
      table.decide(<BusEvent>[delivered.event], _pending);
    });
  }

  @override
  void uninstall(PluginHost host) => _pending.clear();

  /// Everything decided since the last call, and nothing pending after it.
  Reaction drain() {
    final reaction = _pending.build();
    _pending.clear();
    return reaction;
  }
}
