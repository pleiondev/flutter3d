import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

import 'audio_scene.dart';
import 'listener.dart';
import 'mix_snapshot.dart';

/// The audio model in the engine loop: the mix worked out once a frame, in
/// the loop's `audio` phase.
///
/// **A view plugin.** It reads the scene's nodes through the listener and
/// the emitters that follow them and touches nothing of the simulation, so
/// a replay, a rollback and a server never run it twice or at all. The
/// sounds a step decided to make reach it the way they always did — a
/// `SoundtrackPlugin` playing a cue sheet off the frame channel, which is
/// delivered before the frame's phases, or a game's own system earlier in
/// this phase — and this mixes whatever is in the scene by then.
///
/// **Real seconds, not simulated ones.** Snapshots blend and ducks move by
/// the frame's wall-clock seconds, so a "paused" snapshot blends in while
/// the simulation is stopped, and velocities are measured over the same
/// seconds the nodes were seen to move in.
///
/// ```dart
/// final listener = AudioListener()..follow(() => camera.worldMatrix);
/// final loop = EngineLoop(
///   input: input,
///   plugins: [genre, AudioPlugin(scene: () => speakers.scene, listener: listener)],
/// );
/// ```
///
/// The camera phase runs after this one, so a listener following the camera
/// hears from where the camera was placed the frame before. A game whose
/// camera moves fast enough for that to be heard passes [phase] as
/// `LoopPhase.render`.
final class AudioPlugin extends Flutter3dPlugin {
  AudioPlugin({
    required this.scene,
    required this.listener,
    this.id = 'flutter3d_audio',
    this.phase = LoopPhase.audio,
    Iterable<DuckRule> ducking = const <DuckRule>[],
  }) : ducking = List<DuckRule>.unmodifiable(ducking),
       assert(phase.kind == PhaseKind.frame, 'the mix runs once a frame');

  /// The scene to mix, asked once a frame, because a game swaps its silent
  /// scene for the speakers' once they open.
  final AudioScene Function() scene;

  /// Where the ears are: placed by hand, or following a node.
  final AudioListener listener;

  /// The plugin's id. Two mixes in one engine need two.
  final String id;

  /// The frame phase the mix runs in: `audio` unless a game says otherwise.
  final LoopPhase phase;

  /// Ducking rules added to the mixer of each scene this mixes, once.
  final List<DuckRule> ducking;

  AudioScene? _ducked;

  @override
  PluginManifest get manifest => PluginManifest(
    id: id,
    apiVersion: const PluginApiVersion(1, 0),
    touches: PluginTouches.view,
    description: 'The audio mix, worked out once a frame.',
  );

  @override
  void install(PluginHost host) {
    host.loop.addSystem('$id.mix', phase, (LoopContext context) {
      final into = scene();
      if (!identical(into, _ducked)) {
        uninstall(host);
        for (final rule in ducking) {
          into.mixer.addDucking(rule);
        }
        _ducked = into;
      }
      into.update(listener, dt: context.realDt);
    });
  }

  /// Takes this plugin's ducking rules back out of the mixer it put them in,
  /// so switching it off and on again does not duck twice.
  @override
  void uninstall(PluginHost host) {
    final ducked = _ducked;
    if (ducked != null) {
      for (final rule in ducking) {
        ducked.mixer.removeDucking(rule);
      }
    }
    _ducked = null;
  }
}
