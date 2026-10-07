/// The level's fires, falls and splashes heard: what [PhysicsHearing] reads
/// off the effects world, played through the game's own audio scene.
library;

import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';

/// A looping voice held to every fire and every fall of water, as loud as
/// the physics says, and a splash played once for each one heard.
///
/// Apart from `Sounds` on purpose: that table is checked against its own
/// source for sounds declared and never banked, and these are banked
/// beside it, by `AudioCubit`, from [bank].
final class ElementSounds {
  ElementSounds(this._scene);

  static const String _from = 'packages/flutter3d_effects/assets';

  /// Full within a few metres, halving with each doubling of distance past
  /// that, gone across a hall.
  static const Attenuation _near = InverseRolloff(
    reference: 4.0,
    maximum: 50.0,
  );

  static const SoundDef fire = SoundDef(
    name: 'fire',
    asset: '$_from/fire_loop.wav',
    loop: true,
    gain: 0.7,
    attenuation: _near,
    maxInstances: 8,
  );
  static const SoundDef falls = SoundDef(
    name: 'falls',
    asset: '$_from/falls_loop.wav',
    loop: true,
    attenuation: InverseRolloff(reference: 6.0, maximum: 70.0),
    maxInstances: 4,
  );
  static const SoundDef splash = SoundDef(
    name: 'splash',
    asset: '$_from/splash.wav',
    attenuation: _near,
    rateVariance: 0.1,
    maxInstances: 3,
  );

  /// What has to be loaded for these to play.
  static final SoundBank bank = SoundBank(<SoundDef>[fire, falls, splash]);

  /// The scene to play through, asked each frame: the game swaps its
  /// silent one for the speakers' once they open.
  final AudioScene Function() _scene;
  AudioScene? _playingIn;
  final Map<int, SoundEmitter> _fires = <int, SoundEmitter>{};
  final Map<int, SoundEmitter> _falls = <int, SoundEmitter>{};

  /// The frame [hearing] heard, played. The scene is brought up to date
  /// with its listener by the game, with everything else.
  void update(PhysicsHearing hearing) {
    final scene = _scene();
    if (!identical(scene, _playingIn)) {
      // Voices begun in a scene no longer played through are gone with it.
      _fires.clear();
      _falls.clear();
      _playingIn = scene;
    }
    _hold(scene, _fires, hearing.fires, fire);
    _hold(scene, _falls, hearing.falls, falls);
    for (final s in hearing.splashes) {
      scene.play(splash, s.at)
        ..gain = s.loudness
        ..rate = s.rate;
    }
  }

  /// One looping voice per thing heard, moved and turned to it; the voices
  /// of things no longer heard stopped.
  void _hold(
    AudioScene scene,
    Map<int, SoundEmitter> voices,
    List<Audible> heard,
    SoundDef def,
  ) {
    final live = <int>{};
    for (final h in heard) {
      live.add(h.key);
      (voices[h.key] ??= scene.play(def, h.at))
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

  /// Every voice stopped, for a level taken down.
  void silence() {
    for (final voice in <SoundEmitter>[..._fires.values, ..._falls.values]) {
      voice.stop();
    }
    _fires.clear();
    _falls.clear();
  }
}
