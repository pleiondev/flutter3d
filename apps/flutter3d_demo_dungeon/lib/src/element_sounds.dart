/// The crypt's fires and water heard: what `PhysicsHearing` reads off the
/// effects world, and the wading `CryptElements` counts, played through the
/// game's own mixer.
library;

import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:vector_math/vector_math.dart';

/// A looping crackle held to every burning crate, a roar to the water
/// spilling into the flooded vault, and a splash for each body that drops
/// into it and each stride taken through it.
///
/// The recordings are the effects package's own. The torches are not here:
/// each already has its loop in `Sounds.torch`, started with the level.
final class ElementSounds {
  static const String _from = 'packages/flutter3d_effects/assets';

  /// A fire across a room is heard; one three rooms away, through the walls
  /// the mixer's occlusion takes its share of, barely.
  static const Attenuation _room = InverseRolloff(
    reference: 2.5,
    maximum: 30.0,
    factor: 1.3,
  );

  static const SoundDef fire = SoundDef(
    name: 'crate_fire',
    asset: '$_from/fire_loop.wav',
    loop: true,
    attenuation: _room,
    priority: 3,
    maxInstances: 6,
  );

  static const SoundDef falls = SoundDef(
    name: 'culvert',
    asset: '$_from/falls_loop.wav',
    loop: true,
    gain: 0.7,
    attenuation: InverseRolloff(reference: 2.0, maximum: 26.0, factor: 1.4),
    priority: 2,
    maxInstances: 2,
  );

  static const SoundDef splash = SoundDef(
    name: 'splash',
    asset: '$_from/splash.wav',
    attenuation: _room,
    rateVariance: 0.12,
    priority: 4,
    maxInstances: 4,
  );

  /// Everything above, for the mixer to load once it is open.
  static const List<SoundDef> all = <SoundDef>[fire, falls, splash];

  final Map<int, SoundEmitter> _fires = <int, SoundEmitter>{};
  final Map<int, SoundEmitter> _falls = <int, SoundEmitter>{};
  AudioScene? _playingOn;

  /// This frame's fires, falls and splashes played on [audio]. The voices
  /// held from a mixer that has since been replaced are dropped with it.
  void play(
    AudioScene audio,
    PhysicsHearing hearing, {
    required List<Audible> wading,
  }) {
    if (!identical(audio, _playingOn)) {
      _fires.clear();
      _falls.clear();
      _playingOn = audio;
    }
    _hold(audio, _fires, hearing.fires, fire);
    _hold(audio, _falls, hearing.falls, falls);
    for (final s in hearing.splashes.followedBy(wading)) {
      audio.play(splash, s.at)
        ..gain = s.loudness
        ..rate = s.rate;
    }
  }

  void _hold(
    AudioScene audio,
    Map<int, SoundEmitter> voices,
    List<Audible> heard,
    SoundDef def,
  ) {
    final live = <int>{for (final h in heard) h.key};
    for (final h in heard) {
      (voices[h.key] ??= audio.play(def, Vector3.copy(h.at)))
        ..position.setFrom(h.at)
        ..gain = h.loudness
        ..rate = h.rate;
    }
    voices.removeWhere((key, voice) {
      if (live.contains(key)) return false;
      voice.stop();
      return true;
    });
  }

  /// Every voice stopped, for a level change.
  void stop() {
    for (final voice in _fires.values.followedBy(_falls.values)) {
      voice.stop();
    }
    _fires.clear();
    _falls.clear();
  }
}
