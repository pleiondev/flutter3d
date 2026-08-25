import 'dart:math' as math;

import 'particle.dart';
import 'particle_affector.dart';
import 'particle_curve.dart';

/// Drives a particle's size from a curve, as a multiple of its birth size.
///
/// The curve is read as a multiplier rather than as an absolute size so a burst
/// keeps the size variation its emitter gave it. An absolute curve would make
/// every particle in the burst identical at every instant, which is the look
/// [Range] exists to avoid.
final class ParticleSizeCurve extends ParticleAffector {
  const ParticleSizeCurve(this.curve);

  final ParticleCurve curve;

  @override
  void apply(Particle particle, double dt) {
    final birth = particle.birthSize;
    if (birth <= 0.0) return;
    particle.size = birth * curve.sample(particle.life);
  }
}

/// Drives a particle's colour from a gradient.
final class ParticleColorGradient extends ParticleAffector {
  const ParticleColorGradient(this.gradient);

  final ParticleGradient gradient;

  @override
  void apply(Particle particle, double dt) {
    gradient.sampleInto(particle.color, particle.life);
  }
}

/// Turns a billboard over its life.
///
/// Reads [Particle.seed] for the starting angle and for the direction, so a
/// burst is not a sheet of aligned squares turning in step — which is the most
/// recognisable tell of a rotating sprite system, and worse than no rotation at
/// all because it draws the eye to the grid.
///
/// **Derived from age rather than accumulated.** Adding a delta to the angle
/// every step would make the result depend on how many sub-steps a frame
/// happened to take, and the fixed timestep exists precisely so that nothing
/// does. It also means an affector applied twice in one step is harmless.
final class ParticleSpin extends ParticleAffector {
  const ParticleSpin({
    required this.turnsPerSecond,
    this.randomiseStart = true,
  });

  /// The fastest a particle spins, in whole turns a second. Each takes a signed
  /// fraction of it from its own seed, so half of a burst turns each way.
  final double turnsPerSecond;

  /// Whether a particle starts at a random angle rather than at zero.
  final bool randomiseStart;

  @override
  void apply(Particle particle, double dt) {
    final spin = (particle.seed * 2.0 - 1.0) * turnsPerSecond;
    final start = randomiseStart ? particle.seed * _tau : 0.0;
    particle.rotation = start + spin * particle.age * _tau;
  }
}

const double _tau = 2.0 * math.pi;
