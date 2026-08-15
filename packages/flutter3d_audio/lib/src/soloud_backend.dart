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
final class SoLoudBackend implements AudioBackend {
  SoLoudBackend({SoLoud? soloud}) : _soloud = soloud ?? SoLoud.instance;

  final SoLoud _soloud;

  final Map<String, AudioSource> _sources = <String, AudioSource>{};

  /// Boots the audio engine. Safe to call twice.
  ///
  /// Named for the engine rather than for a voice, because [start] on the
  /// interface begins a sound and two meanings of one word in one class is how
  /// somebody eventually calls the wrong one.
  Future<void> open() async {
    if (_soloud.isInitialized) return;
    await _soloud.init();
  }

  Future<void> dispose() async {
    _sources.clear();
    await _soloud.disposeAllSources();
  }

  @override
  Future<void> preload(String asset) async {
    if (_sources.containsKey(asset)) return;
    try {
      _sources[asset] = await _soloud.loadAsset(asset);
    } catch (error) {
      // A missing sound leaves the game silent in one place rather than
      // stopping it. Losing a footstep should not cost the play-test.
      debugPrint('flutter3d_audio: could not load "$asset": $error');
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
      debugPrint('flutter3d_audio: could not play "$asset": $error');
      return null;
    }
  }

  @override
  void update(VoiceId voice, {required double gain, required double pan}) {
    final handle = voice as SoundHandle;
    _soloud
      ..setVolume(handle, gain)
      ..setPan(handle, pan);
  }

  @override
  void stop(VoiceId voice) => _soloud.stop(voice as SoundHandle);

  @override
  bool isAlive(VoiceId voice) =>
      _soloud.getIsValidVoiceHandle(voice as SoundHandle);
}
