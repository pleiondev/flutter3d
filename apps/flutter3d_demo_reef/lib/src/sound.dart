/// The dive heard: the splashes [PhysicsHearing] reads off the sea, and the
/// diver's own breath going out as bubbles, as often and as loud as the
/// tank gives it.
library;

import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';

final class ReefSound {
  ReefSound(this._scene, this._hearing);

  static const String _from = 'packages/flutter3d_effects/assets';

  static const SoundDef splash = SoundDef(
    name: 'splash',
    asset: '$_from/splash.wav',
    attenuation: InverseRolloff(reference: 4.0, maximum: 60.0),
    rateVariance: 0.1,
  );

  /// The breath out through the regulator: the falling-water recording,
  /// played fast and short, is a column of bubbles.
  static const SoundDef exhale = SoundDef(
    name: 'exhale',
    asset: '$_from/falls_loop.wav',
    attenuation: NoAttenuation(),
    gain: 0.25,
    maxInstances: 2,
  );

  static final SoundBank bank = SoundBank(<SoundDef>[splash, exhale]);

  final AudioScene _scene;
  final PhysicsHearing _hearing;
  AudioEmitter? _breath;
  double _sinceBreath = 0.0;

  /// The frame heard from [listener], [dt] after the last; [breathing], 0
  /// to 1, how hard the diver breathes, and [under] whether they are.
  void update(
    AudioListener listener,
    double dt, {
    required double breathing,
    required bool under,
  }) {
    for (final s in _hearing.splashes) {
      _scene.play(splash, s.at)
        ..gain = s.loudness
        ..rate = s.rate;
    }
    // Played once: the dive steps at its own rate now, and a frame that ran
    // no step would otherwise hear the last step's splashes again.
    _hearing.splashes.clear();
    // A breath every four seconds at rest, every two and a half finning
    // hard; out as bubbles for a second and a half of it.
    _sinceBreath += dt;
    final period = 4.0 - 1.5 * breathing;
    if (under && _sinceBreath >= period) {
      _sinceBreath = 0.0;
      _breath = _scene.play(exhale, listener.position)
        ..rate = 1.6
        ..gain = 0.6 + 0.4 * breathing;
    }
    if (_breath != null && _sinceBreath > 1.5) {
      _breath!.stop();
      _breath = null;
    }
    _scene.update(listener);
  }

  void stop() => _scene.stopAll();
}
