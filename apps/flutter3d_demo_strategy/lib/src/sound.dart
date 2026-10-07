/// The map heard: what [PhysicsHearing] reads off the effects' world,
/// played.
///
/// **Heard from where the camera hangs**, forty metres and more over the
/// ground, so every voice carries further than it would to somebody standing
/// in the field: a burning wood is a roar from up there and a hall alight is
/// heard across the map, and a stone landing in the pond is heard only near
/// it.
library;

import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';

/// A looping voice held to every fire and every fall of the stream, as loud
/// as the physics says, and a splash played once for each one heard.
final class StrategySound {
  /// Plays what [_hearing] hears through [_scene].
  StrategySound(this._scene, this._hearing);

  static const String _from = 'packages/flutter3d_effects/assets';

  static const SoundDef _fire = SoundDef(
    name: 'fire',
    asset: '$_from/fire_loop.wav',
    loop: true,
    attenuation: InverseRolloff(reference: 30.0, maximum: 220.0),
    maxInstances: 10,
  );
  static const SoundDef _falls = SoundDef(
    name: 'falls',
    asset: '$_from/falls_loop.wav',
    loop: true,
    attenuation: InverseRolloff(reference: 25.0, maximum: 160.0),
    maxInstances: 4,
  );
  static const SoundDef _splash = SoundDef(
    name: 'splash',
    asset: '$_from/splash.wav',
    attenuation: InverseRolloff(reference: 25.0, maximum: 140.0),
    rateVariance: 0.1,
  );

  /// Every sound the map makes, preloaded when the speakers open.
  static final SoundBank bank = SoundBank(<SoundDef>[_fire, _falls, _splash]);

  final AudioScene _scene;
  final PhysicsHearing _hearing;
  final Map<int, SoundEmitter> _fires = <int, SoundEmitter>{};
  final Map<int, SoundEmitter> _falling = <int, SoundEmitter>{};

  /// The frame heard from [listener].
  void update(AudioListener listener) {
    _hold(_fires, _hearing.fires, _fire);
    _hold(_falling, _hearing.falls, _falls);
    for (final Audible s in _hearing.splashes) {
      _scene.play(_splash, s.at)
        ..gain = s.loudness
        ..rate = s.rate;
    }
    _scene.update(listener);
  }

  /// One looping voice per thing heard, moved to it; the voices of things no
  /// longer heard stopped.
  void _hold(Map<int, SoundEmitter> voices, List<Audible> heard, SoundDef def) {
    final live = <int>{};
    for (final Audible h in heard) {
      live.add(h.key);
      (voices[h.key] ??= _scene.play(def, h.at))
        ..position.setFrom(h.at)
        ..gain = h.loudness
        ..rate = h.rate;
    }
    voices.removeWhere((int key, SoundEmitter voice) {
      if (live.contains(key)) return false;
      voice.stop();
      return true;
    });
  }

  /// Every voice stopped, for the window closing.
  void stop() => _scene.stopAll();
}
