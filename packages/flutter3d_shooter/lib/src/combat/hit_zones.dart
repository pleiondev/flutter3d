import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

/// What a shot is worth depending on where it lands on a body.
///
/// **The shooter had none of this**: every hit was worth the same, so a
/// shotgun in the face and a pistol in the shin came to the same arithmetic and
/// aiming was only a question of whether the ray connected at all. That is the
/// difference between a weapon having a feel and a weapon having a number.
///
/// The measurement is the engine's — `Actor.fractionUp`, nought at the feet and
/// one at the crown — because it is geometry. What the fractions *mean* is
/// here, because "head" is a word about a fiction and a platformer has no use
/// for it.
///
/// **Two zones and no more, on purpose.** A head that is worth aiming for and
/// legs that are worth not aiming for is the whole of what a player can feel at
/// the range this game is fought at; a table of six would be five of them
/// nobody can tell apart, and each one is a number somebody has to keep true.
final class HitZones {
  const HitZones({
    this.headAbove = 0.78,
    this.headMultiplier = 2.5,
    this.legsBelow = 0.34,
    this.legsMultiplier = 0.6,
  });

  /// Nothing is worth more or less than anything else. What a game gets before
  /// it decides it wants headshots — and what a boss that is one solid mass
  /// should be given.
  const HitZones.even()
      : headAbove = 1.1,
        headMultiplier = 1.0,
        legsBelow = -0.1,
        legsMultiplier = 1.0;

  /// Above this fraction of the body counts as the head.
  ///
  /// A little over three quarters: a capsule's top quarter is the head and the
  /// neck, and a threshold at exactly the shoulder rewards a shot that a player
  /// would read as having hit the chest.
  final double headAbove;

  final double headMultiplier;

  /// Below this fraction counts as the legs.
  final double legsBelow;

  final double legsMultiplier;

  /// What a hit at [fractionUp] of the way up a body is worth.
  double multiplierFor(double fractionUp) {
    if (fractionUp >= headAbove) return headMultiplier;
    if (fractionUp <= legsBelow) return legsMultiplier;
    return 1.0;
  }

  /// What a hit at [point] on [target] is worth, or one if there is no body to
  /// measure — a barrel, a door, a lamp post.
  double forHitOn(Object? target, Vector3 point) {
    if (target is! Actor) return 1.0;
    final fraction = target.fractionUp(point);
    return fraction == null ? 1.0 : multiplierFor(fraction);
  }
}
