/// The valley heard: what [PhysicsHearing] reads off the world, played.
library;

import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';

/// A looping voice held to every fire and every fall of water, as loud as
/// the physics says, and a splash played once for each one heard.
final class HollowSound {
  HollowSound(this._scene, this._hearing);

  static const String _from = 'packages/flutter3d_effects/assets';

  /// Full within a few metres, halving with each doubling of distance past
  /// that, gone across the valley.
  static const Attenuation _near = InverseRolloff(
    reference: 5.0,
    maximum: 70.0,
  );

  static const SoundDef fire = SoundDef(
    name: 'fire',
    asset: '$_from/fire_loop.wav',
    loop: true,
    attenuation: _near,
    maxInstances: 12,
  );
  static const SoundDef falls = SoundDef(
    name: 'falls',
    asset: '$_from/falls_loop.wav',
    loop: true,
    attenuation: InverseRolloff(reference: 8.0, maximum: 90.0),
    maxInstances: 6,
  );
  static const SoundDef splash = SoundDef(
    name: 'splash',
    asset: '$_from/splash.wav',
    attenuation: _near,
    rateVariance: 0.1,
  );

  static final SoundBank bank = SoundBank(<SoundDef>[fire, falls, splash]);

  final AudioScene _scene;
  final PhysicsHearing _hearing;
  final Map<int, SoundEmitter> _fires = <int, SoundEmitter>{};
  final Map<int, SoundEmitter> _falls = <int, SoundEmitter>{};

  /// The frame heard from [listener].
  void update(AudioListener listener) {
    _hold(_fires, _hearing.fires, fire);
    _hold(_falls, _hearing.falls, falls);
    for (final s in _hearing.splashes) {
      _scene.play(splash, s.at)
        ..gain = s.loudness
        ..rate = s.rate;
    }
    _scene.update(listener);
  }

  /// One looping voice per thing heard, moved and turned to it; the voices
  /// of things no longer heard stopped.
  void _hold(Map<int, SoundEmitter> voices, List<Audible> heard, SoundDef def) {
    final live = <int>{};
    for (final h in heard) {
      live.add(h.key);
      (voices[h.key] ??= _scene.play(def, h.at))
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

  /// Every voice stopped, for the window closing.
  void stop() => _scene.stopAll();
}
