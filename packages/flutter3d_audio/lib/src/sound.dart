import 'attenuation.dart';

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
  })  : assert(gain >= 0.0),
        assert(maxInstances > 0);

  /// What the game calls it. Used in messages and in the mixer's own reports.
  final String name;

  /// Asset path, resolved by the backend.
  final String asset;

  /// Volume before distance is taken into account.
  final double gain;

  final bool loop;

  final Attenuation attenuation;

  /// Breaks ties when there are more sounds than voices.
  ///
  /// A door closing matters more than the ninth footstep, and distance alone
  /// would let the footstep win because it is nearer.
  final int priority;

  /// How many of this one may sound at once.
  ///
  /// Ten monsters hit by one rocket produce ten identical grunts on the same
  /// frame, which is not ten times as loud — it is a click.
  final int maxInstances;
}
