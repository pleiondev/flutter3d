import 'package:vector_math/vector_math.dart';

import 'particle_effect.dart';

/// A standing emission: what, where, how fast, and for how long.
///
/// An implementation detail of [ParticleSystem]'s standing-rate bookkeeping,
/// kept in its own file for the same reason [Emission.isSpent] is a getter
/// rather than a field read at the call site: it is a fact about one source's
/// countdown, not part of what a particle effect is.
final class Emission {
  /// An emission of [effect] from [origin] at [perSecond], running until
  /// stopped unless [remaining] gives it seconds.
  Emission({
    required this.effect,
    required this.origin,
    required this.perSecond,
    this.direction,
    this.remaining,
  });

  /// The recipe each emitted particle is born from.
  final ParticleEffect effect;

  /// Where it emits from, in scene space (relative to `Scene.origin`).
  final Vector3 origin;

  /// How many particles it emits, per second.
  final double perSecond;

  /// The way the emitter leans its particles, handed to it as
  /// `ParticleBirth.direction`; null leaves the emitter's own shape.
  final Vector3? direction;

  /// Seconds of emission left, or null to run until stopped.
  ///
  /// Counted down in the sub-step rather than in the frame, so an emission that
  /// should last a quarter of a second emits the same particles whether the
  /// frame took four milliseconds or forty. That is the same reason the
  /// accumulator exists.
  double? remaining;

  /// Whether this emission has run out and should be dropped.
  bool get isSpent => remaining != null && remaining! <= 0.0;
}
