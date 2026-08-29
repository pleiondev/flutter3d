import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_soloud/flutter_soloud.dart';

import 'backend.dart';

/// Plays through SoLoud, flat.
///
/// Flat on purpose. SoLoud has a 3D layer, and it is not usable from here:
/// applying a moved source or a turned listener requires `update3dAudio()`,
/// which flutter_soloud exposes neither directly nor by way of any call that
/// makes it — its `set3dSourcePosition` passes straight through to a SoLoud
/// method that only marks the source dirty. A source set once at `play3d`
/// therefore never moves again, which in a first-person game means the whole
/// feature. So [AudioScene] does the geometry and this asks for a voice with a
/// volume and a pan, both of which take effect immediately.
///
/// If a later flutter_soloud exposes the call, the right change is a second
/// backend rather than an edit here — the interface exists for exactly that.
/// Where a backend says what it could not do.
///
/// Declared here rather than imported from `flutter3d_game`, which is where
/// the identical typedef lives: this package knows nothing about a game and
/// must not start. Dart's function types are structural, so an application
/// passing that one to this is the same type — the duplication costs a line
/// and buys a dependency not taken.
typedef IssueSink = void Function(String issue);

final class SoLoudBackend implements AudioBackend {
  SoLoudBackend({SoLoud? soloud, IssueSink? onIssue})
    : _soloud = soloud ?? SoLoud.instance,
      onIssue = onIssue ?? _printIssue;

  final SoLoud _soloud;

  /// Where this says what it could not play.
  ///
  /// **It said it to `debugPrint` and nowhere else**, which in a release build
  /// is nowhere at all: a sound that will not decode is silent for the rest of
  /// the session and the only record of it was a console line stripped out of
  /// the build a player runs. Every storage path in `flutter3d_ui` threads one
  /// of these; audio was the layer that did not.
  final IssueSink onIssue;

  static void _printIssue(String issue) =>
      debugPrint('flutter3d_audio: $issue');

  final Map<String, AudioSource> _sources = <String, AudioSource>{};

  /// Assets [preload] was asked for and could not decode.
  ///
  /// Kept so a caller can say which sounds a level is missing rather than
  /// discovering it by silence. Empty on a healthy load.
  List<String> get failedAssets => List<String>.unmodifiable(_failed);
  final List<String> _failed = <String>[];

  /// Boots the audio engine. Safe to call twice.
  ///
  /// Named for the engine rather than for a voice, because [start] on the
  /// interface begins a sound and two meanings of one word in one class is how
  /// somebody eventually calls the wrong one.
  Future<void> open() async {
    if (_soloud.isInitialized) return;
    // The web module races the app. flutter_soloud's two script tags are
    // loaded with `defer`, the wasm behind them initialises after `main` is
    // already running, and an `init` called in that gap throws reading
    // `_isInited` off a module that is not there yet — which every demo on
    // the site did, on every load, and it looked exactly like a game with no
    // sound. The gap measured under a second on the deployed demos, so a
    // patient loop covers it; a genuinely broken engine still surfaces,
    // because the last attempt rethrows into the caller's own
    // fallback-to-silence.
    const attempts = 20;
    for (var attempt = 1; ; attempt++) {
      try {
        await _soloud.init();
        return;
      } catch (_) {
        if (attempt == attempts) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
  }

  /// Frees the sources and shuts the engine down.
  ///
  /// **`deinit` is the half this was missing.** Dropping the sources leaves
  /// the audio device open for the life of the process, and [open] returns
  /// early when `isInitialized` — so a second backend after a hot restart
  /// attached to an engine nobody had re-initialised and played nothing, which
  /// looks exactly like a game with no sound.
  Future<void> dispose() async {
    _sources.clear();
    _failed.clear();
    await _soloud.disposeAllSources();
    if (_soloud.isInitialized) _soloud.deinit();
  }

  @override
  Future<void> preload(String asset) async {
    if (_sources.containsKey(asset)) return;
    try {
      _sources[asset] = await _soloud.loadAsset(asset);
    } catch (error) {
      // A missing sound leaves the game silent in one place rather than
      // stopping it. Losing a footstep should not cost the play-test — but it
      // is worth saying out loud, because silence is what a sound that works
      // and a sound that failed to decode look like from the outside.
      _failed.add(asset);
      onIssue('could not load "$asset": $error');
    }
  }

  @override
  VoiceId? start(
    String asset, {
    required double gain,
    required double pan,
    required double rate,
    required bool loop,
  }) {
    final source = _sources[asset];
    if (source == null) return null;
    try {
      final handle = _soloud.play(
        source,
        volume: gain,
        pan: pan,
        looping: loop,
      );
      // Set rather than passed: `play` has no speed argument, and setting it on
      // the handle immediately afterwards is the same frame, so nothing is
      // audible at the wrong speed.
      if (rate != 1.0) _soloud.setRelativePlaySpeed(handle, rate);
      return handle;
    } catch (error) {
      onIssue('could not play "$asset": $error');
      return null;
    }
  }

  /// **The three below run per audible voice per frame, and were the three
  /// with no guard.** Only [start] was wrapped, which is backwards: a throw
  /// there costs one sound, and a throw here comes out of the render loop and
  /// takes the frame with it. A `SoundHandle` goes stale for reasons this side
  /// does not control — a device change, an engine torn down underneath a
  /// voice — and the right answer to a stale handle is to stop using it, not
  /// to stop the game.
  @override
  void update(
    VoiceId voice, {
    required double gain,
    required double pan,
    required double rate,
  }) {
    final handle = voice as SoundHandle;
    try {
      _soloud
        ..setVolume(handle, gain)
        ..setPan(handle, pan)
        ..setRelativePlaySpeed(handle, rate);
    } catch (error) {
      onIssue('could not update a voice: $error');
    }
  }

  @override
  void stop(VoiceId voice) {
    try {
      _soloud.stop(voice as SoundHandle);
    } catch (error) {
      onIssue('could not stop a voice: $error');
    }
  }

  @override
  bool isAlive(VoiceId voice) {
    try {
      return _soloud.getIsValidVoiceHandle(voice as SoundHandle);
    } catch (error) {
      // Not alive, which is the answer that lets the scene forget it. Saying
      // "yes" here would keep a dead handle being updated every frame for the
      // life of the level.
      onIssue('could not ask about a voice: $error');
      return false;
    }
  }
}
