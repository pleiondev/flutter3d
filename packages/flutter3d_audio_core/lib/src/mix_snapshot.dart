import 'bus_effect.dart';
import 'mixer.dart';

/// A named state of the mix — "under water", "paused", "boss fight" — that
/// the mixer blends into and out of.
///
/// **What it holds is offsets, not a whole desk.** [levels] are decibels
/// added to a bus's level, and [effects] are put on a bus while the snapshot
/// is in; a bus it does not name is left as it was. That is what lets two be
/// in at once: "paused" taking 12 dB off the effects and "under water"
/// muffling them both apply, and leaving one leaves the other.
///
/// Separate from the player's volume sliders ([Mixer.setVolume]), which a
/// snapshot never moves: a pause menu that ducks the game must not be how a
/// player's music setting is lost.
///
/// The maps are keyed by [AudioBus], which overrides `==`, so a snapshot that
/// names buses is built with `final`, not `const`.
///
/// ```dart
/// final underWater = MixSnapshot(
///   'under water',
///   levels: {AudioBus.sfx: -6.0},
///   effects: {AudioBus.sfx: [LowPassEffect(800.0)]},
///   blendInSeconds: 0.2,
///   blendOutSeconds: 0.6,
/// );
/// mixer.enterSnapshot(underWater);
/// ```
final class MixSnapshot {
  const MixSnapshot(
    this.name, {
    this.levels = const <AudioBus, double>{},
    this.effects = const <AudioBus, List<BusEffect>>{},
    this.blendInSeconds = 0.25,
    this.blendOutSeconds = 0.25,
  }) : assert(blendInSeconds >= 0.0),
       assert(blendOutSeconds >= 0.0);

  /// What a game calls it, and what [Mixer.leaveSnapshot] names it by.
  final String name;

  /// Decibels added to each bus's level while this is fully in: −6 is half
  /// the amplitude, and anything at or below `silenceDecibels` is silence.
  final Map<AudioBus, double> levels;

  /// Effects put on each bus while this is in, blended by their own
  /// [BusEffect.atWeight] as it comes and goes.
  final Map<AudioBus, List<BusEffect>> effects;

  /// Seconds from nothing to fully in. Nought is at once.
  final double blendInSeconds;

  /// Seconds from fully in to gone. Nought is at once.
  final double blendOutSeconds;

  @override
  String toString() => 'MixSnapshot($name)';
}

/// One bus turned down while another is heard: the music under a line of
/// dialogue, the ambience under an explosion.
///
/// While anything routed into [trigger] is audible above [thresholdDecibels]
/// — measured where it is heard, before any slider — [target] is taken down
/// by [depthDecibels], reaching it over [attackSeconds] and coming back over
/// [releaseSeconds] once [trigger] falls quiet.
final class DuckRule {
  const DuckRule({
    required this.trigger,
    required this.target,
    this.depthDecibels = -12.0,
    this.attackSeconds = 0.08,
    this.releaseSeconds = 0.6,
    this.thresholdDecibels = -40.0,
  }) : assert(depthDecibels <= 0.0),
       assert(attackSeconds >= 0.0),
       assert(releaseSeconds >= 0.0);

  /// The bus whose sound does the ducking, with every bus routed into it.
  final AudioBus trigger;

  /// The bus that is ducked.
  final AudioBus target;

  /// How far [target] is taken down, in decibels: nought or less.
  final double depthDecibels;

  /// Seconds to reach the full depth once [trigger] is heard.
  final double attackSeconds;

  /// Seconds to come back once [trigger] is quiet.
  final double releaseSeconds;

  /// How loud [trigger]'s loudest voice must be to count as heard, in
  /// decibels of its audible gain.
  final double thresholdDecibels;

  @override
  String toString() => 'DuckRule(${trigger.name} ducks ${target.name})';
}
