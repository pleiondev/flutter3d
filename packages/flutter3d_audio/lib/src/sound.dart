import 'attenuation.dart';
import 'mixer.dart';

/// A sound the game can ask for, by name and behaviour rather than by file.
///
/// Const so a game can declare its whole bank as constants and have the
/// compiler check every reference — the same reason weapons and monsters are
/// declared that way.
final class SoundDef {
  const SoundDef({
    required this.name,
    required this.asset,
    this.gain = 1.0,
    this.loop = false,
    this.attenuation = const InverseRolloff(),
    this.priority = 0,
    this.maxInstances = 4,
    this.bus = AudioBus.sfx,
    this.rate = 1.0,
    this.rateVariance = 0.0,
  })  : assert(gain >= 0.0),
        assert(maxInstances > 0),
        assert(rate > 0.0),
        assert(rateVariance >= 0.0 && rateVariance < 1.0);

  /// What the game calls it. Used in messages and in the mixer's own reports.
  final String name;

  /// Asset path, resolved by the backend.
  final String asset;

  /// Volume before distance is taken into account.
  final double gain;

  final bool loop;

  final Attenuation attenuation;

  /// How fast to play it. One is the file's own speed.
  ///
  /// **Rate, not pitch.** Pitch implies resampling that keeps the duration, and
  /// neither SoLoud's `setRelativePlaySpeed` nor WebAudio's `playbackRate` does
  /// that. Calling it pitch would be a promise the backends cannot keep.
  final double rate;

  /// How much to vary [rate] on each play, either side of it.
  ///
  /// The other half of what [maxInstances] is for. Ten identical grunts on one
  /// frame is a click; ten identical *coins* half a second apart is a machine
  /// noise, and the ear notices the sameness long before it notices the sound.
  /// A few per cent is enough.
  final double rateVariance;

  /// Breaks ties when there are more sounds than voices.
  ///
  /// A door closing matters more than the ninth footstep, and distance alone
  /// would let the footstep win because it is nearer.
  final int priority;

  /// Which volume slider turns this down.
  ///
  /// Effects by default, because a game that has never thought about buses has
  /// effects — and the one sound that is obviously not an effect, the music, is
  /// the one a caller will remember to mark.
  final AudioBus bus;

  /// How many of this one may sound at once.
  ///
  /// Ten monsters hit by one rocket produce ten identical grunts on the same
  /// frame, which is not ten times as loud — it is a click.
  final int maxInstances;
}
