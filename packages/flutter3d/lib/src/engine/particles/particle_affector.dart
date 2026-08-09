import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'particle.dart';

/// One thing that happens to a particle while it is alive.
///
/// ## Why these are objects
///
/// The alternative is an effect with a field for every behaviour anybody might
/// want — gravity, drag, a start colour, an end colour, a size curve, a wind
/// vector — where every effect carries the whole set and most of them are zero.
/// Adding turbulence then means editing the effect, the update loop and every
/// existing effect's constructor.
///
/// A list of affectors instead: an effect names only what applies to it, a new
/// one is a new class and nothing else changes, and a game built on this engine
/// can add its own without touching the engine at all. The update loop knows
/// nothing but `apply`.
///
/// They are const and stateless, so one instance is shared by every particle of
/// every effect that uses it.
abstract base class ParticleAffector {
  const ParticleAffector();

  /// Advances one particle by [dt]. Called once per particle per step, after
  /// its age has been updated and before it is moved.
  void apply(Particle particle, double dt);
}

/// Pulls particles down. Sparks and debris; not smoke.
final class ParticleGravity extends ParticleAffector {
  const ParticleGravity([this.acceleration = -9.8]);

  /// Metres per second squared. Negative is downwards, and a fraction of real
  /// gravity usually looks better than the real figure — nine-eighty reads as
  /// heavy for something the size of a spark.
  final double acceleration;

  @override
  void apply(Particle particle, double dt) {
    particle.velocity.y += acceleration * dt;
  }
}

/// Bleeds off speed, so a burst slows into a drift instead of flying away.
final class ParticleDrag extends ParticleAffector {
  const ParticleDrag(this.perSecond);

  /// Fraction of the remaining speed lost each second.
  final double perSecond;

  @override
  void apply(Particle particle, double dt) {
    // Exponential rather than linear: linear drag reaches zero and then pushes
    // the particle backwards, which is a very recognisable bug.
    final factor = math.exp(-perSecond * dt);
    particle.velocity.scale(factor);
  }
}

/// Pushes everything one way, for a draught or the wake of an explosion.
final class ParticleWind extends ParticleAffector {
  ParticleWind(Vector3 acceleration) : _acceleration = acceleration.clone();

  final Vector3 _acceleration;

  @override
  void apply(Particle particle, double dt) {
    particle.velocity
      ..x += _acceleration.x * dt
      ..y += _acceleration.y * dt
      ..z += _acceleration.z * dt;
  }
}

/// Moves the colour from one to another across the particle's life.
final class ParticleColorOverLife extends ParticleAffector {
  ParticleColorOverLife(Vector4 from, Vector4 to)
      : _from = from.clone(),
        _to = to.clone();

  final Vector4 _from;
  final Vector4 _to;

  @override
  void apply(Particle particle, double dt) {
    final t = particle.life;
    particle.color.setValues(
      _from.x + (_to.x - _from.x) * t,
      _from.y + (_to.y - _from.y) * t,
      _from.z + (_to.z - _from.z) * t,
      _from.w + (_to.w - _from.w) * t,
    );
  }
}

/// Fades a particle out towards the end of its life.
///
/// Separate from [ParticleColorOverLife] because most effects want the fade and
/// not the colour change, and an effect that had to spell out both ends of a
/// colour ramp just to disappear would spell it out wrong.
final class ParticleFade extends ParticleAffector {
  const ParticleFade({this.startsAt = 0.0});

  /// Point in the particle's life where the fade begins, in `[0, 1)`.
  final double startsAt;

  @override
  void apply(Particle particle, double dt) {
    final t = particle.life;
    if (t <= startsAt) return;
    final span = 1.0 - startsAt;
    final fade = span <= 0.0 ? 0.0 : 1.0 - (t - startsAt) / span;
    particle.color.w *= fade;
  }
}

/// Scales a particle across its life.
final class ParticleSizeOverLife extends ParticleAffector {
  const ParticleSizeOverLife({this.from = 1.0, this.to = 0.0});

  /// Multipliers on the size the particle was born with.
  final double from;
  final double to;

  @override
  void apply(Particle particle, double dt) {
    // Rebuilt from the birth size each step rather than compounded. Multiplying
    // the current size every step shrinks a particle meant to halve over a
    // second to nothing in a tenth of one.
    final birth = particle.birthSize;
    if (birth <= 0.0) return;
    final t = particle.life;
    particle.size = birth * (from + (to - from) * t);
  }
}
