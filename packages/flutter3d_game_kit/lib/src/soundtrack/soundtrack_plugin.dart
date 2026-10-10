import 'package:flutter3d_audio_core/flutter3d_audio_core.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

import 'cue_sheet.dart';

/// A [CueSheet] heard from the engine's bus, on the frame channel, and played.
///
/// **A view plugin.** Once a frame, after the frame's steps, every event is
/// handed to the sheet and what it makes of them is played through the scene
/// [scene] answers — asked each time, because a game swaps its silent scene
/// for the speakers' once they open. Nothing reaches the simulation.
///
/// **A rollback does not play a sound twice.** An event the frame channel
/// hands out again as [Delivered.resimulated] is a correction to something
/// already heard; this skips it unless [playCorrections] is set.
///
/// ```dart
/// final loop = EngineLoop(
///   input: input,
///   plugins: [genre, SoundtrackPlugin(cues, scene: () => audio.scene)],
/// );
/// ```
final class SoundtrackPlugin extends Flutter3dPlugin {
  SoundtrackPlugin(
    this.cues, {
    required this.scene,
    this.id = 'flutter3d_addon_soundtrack',
    this.playCorrections = false,
    this.bus,
  });

  /// The bus every cue plays on, or null for each sound's own — which is
  /// what a sheet heard before there were buses to choose did. Each cue is
  /// an `AudioEmitter` in [scene], so the mixer's snapshots and ducking
  /// reach it either way.
  final AudioBus? bus;

  /// What each event sounds like: the game's own sheet.
  final CueSheet cues;

  /// The scene to play through, asked once a frame.
  final AudioScene Function() scene;

  /// The plugin's id. Two sheets in one engine need two.
  final String id;

  /// Whether an event a rollback changed is played when it arrives again.
  final bool playCorrections;

  @override
  PluginManifest get manifest => PluginManifest(
    id: id,
    apiVersion: const PluginApiVersion(1, 0),
    touches: PluginTouches.view,
    description: 'Sounds for events, from a cue sheet.',
  );

  @override
  void install(PluginHost host) {
    host.events.onFrame<BusEvent>('$id.play', (Delivered<BusEvent> delivered) {
      if (delivered.resimulated && !playCorrections) return;
      final heard = cues.listen(<BusEvent>[delivered.event]);
      if (heard.isEmpty) return;
      final into = scene();
      for (final h in heard) {
        into.play(h.sound, h.at, bus: bus);
      }
    });
  }
}
