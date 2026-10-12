import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'particle.dart';

/// Decides where a particle starts and which way it is going.
///
/// The other half of the split that keeps effects declarative: an emitter says
/// what a burst looks like at the instant it happens, and the affectors say
/// what happens to it afterwards. Between them they cover every effect this
/// game needs without a single field named after a specific one.
abstract base class ParticleEmitter {
  const ParticleEmitter();

  /// Places [ParticleBirth.particle] for a burst at [ParticleBirth.origin],
  /// in scene space, pointing along [ParticleBirth.direction].
  ///
  /// The system reuses one [ParticleBirth] for every particle it emits: read
  /// it here and do not keep it.
  void emit(ParticleBirth birth);

  /// A unit vector, uniformly over the sphere.
  ///
  /// On the base class because two of the three emitters need it, and the naive
  /// version — three random components normalised — is not uniform: it
  /// concentrates towards the corners of the cube it samples.
  void randomDirection(Vector3 out, math.Random random) {
    final z = random.nextDouble() * 2.0 - 1.0;
    final angle = random.nextDouble() * 2.0 * math.pi;
    final r = math.sqrt(1.0 - z * z);
    out.setValues(r * math.cos(angle), r * math.sin(angle), z);
  }
}

/// What [ParticleEmitter.emit] is handed: the particle to place, and the
/// burst it is born in.
///
/// **One object, so a minor can hand an emitter more** — the effect, the
/// burst's source — without breaking an emitter written against 1.0.
/// **Reused**: a particle system owns one and sets it before every particle
/// it emits, so a burst allocates nothing for it; an emitter reads it during
/// [ParticleEmitter.emit] and does not keep it.
final class ParticleBirth {
  ParticleBirth({
    required this.particle,
    required this.origin,
    required this.direction,
    required this.random,
  });

  /// The particle to place.
  Particle particle;

  /// Where the burst is, in scene space.
  Vector3 origin;

  /// Which way it is fired, normalized; an emitter that does not care — a
  /// sphere does not — ignores it.
  Vector3 direction;

  /// The particle's own random stream.
  math.Random random;
}

/// Outwards in every direction. Explosions, and anything that bursts.
final class SphereEmitter extends ParticleEmitter {
  const SphereEmitter({
    this.speed = const Range(2.0, 6.0),
    this.radius = const Range.exact(0.0),
  });

  final Range speed;

  /// How far from the origin a particle starts, so a burst begins as a shell
  /// rather than as a point.
  final Range radius;

  @override
  void emit(ParticleBirth birth) {
    final particle = birth.particle;
    final origin = birth.origin;
    final random = birth.random;
    randomDirection(particle.velocity, random);
    final offset = radius.sample(random);
    particle.position
      ..setFrom(origin)
      ..x += particle.velocity.x * offset
      ..y += particle.velocity.y * offset
      ..z += particle.velocity.z * offset;
    particle.velocity.scale(speed.sample(random));
  }
}

/// A cone around a direction. Muzzle flashes, sparks off a wall, blood.
final class ConeEmitter extends ParticleEmitter {
  const ConeEmitter({
    this.speed = const Range(3.0, 8.0),
    this.halfAngle = 25.0 * math.pi / 180.0,
  });

  /// Metres per second, sampled per particle.
  final Range speed;

  /// The angle between the axis and the cone's edge, in radians.
  final double halfAngle;

  @override
  void emit(ParticleBirth birth) {
    final particle = birth.particle;
    final origin = birth.origin;
    final direction = birth.direction;
    final random = birth.random;
    // A random direction blended towards the axis. Cheaper than building an
    // orthonormal basis, and the distribution is close enough for something
    // that lasts a third of a second.
    randomDirection(particle.velocity, random);
    final spread = math.sin(halfAngle);
    particle.velocity
      ..scale(spread)
      ..add(direction)
      ..normalize()
      ..scale(speed.sample(random));
    particle.position.setFrom(origin);
  }
}

/// Anywhere inside a box. Rain over an area, dust in a shaft of light, embers
/// rising off the whole width of a fire rather than out of one point.
///
/// The shape every other emitter here cannot express: a sphere with a radius
/// gives a shell, a cone gives a point, and a volume that is wider than it is
/// tall has to be built out of several emitters that then have to be kept in
/// step with each other.
final class BoxEmitter extends ParticleEmitter {
  BoxEmitter({
    required Vector3 halfExtents,
    this.speed = const Range(0.0, 0.0),
    Vector3? along,
  }) : _halfExtents = halfExtents.clone(),
       _along = along?.clone();

  final Vector3 _halfExtents;

  /// Fixed direction for the whole box, or null to use the direction the burst
  /// was fired along.
  ///
  /// A box usually wants one: the point of emitting over an area is that every
  /// particle goes the same way — rain falls down, it does not fall outwards.
  final Vector3? _along;

  final Range speed;

  @override
  void emit(ParticleBirth birth) {
    final particle = birth.particle;
    final origin = birth.origin;
    final direction = birth.direction;
    final random = birth.random;
    particle.position.setValues(
      origin.x + (random.nextDouble() * 2.0 - 1.0) * _halfExtents.x,
      origin.y + (random.nextDouble() * 2.0 - 1.0) * _halfExtents.y,
      origin.z + (random.nextDouble() * 2.0 - 1.0) * _halfExtents.z,
    );
    final along = _along ?? direction;
    final v = speed.sample(random);
    particle.velocity
      ..setFrom(along)
      ..scale(v);
  }
}

/// Straight up, slowly. Smoke and dust.
final class DriftEmitter extends ParticleEmitter {
  const DriftEmitter({
    this.speed = const Range(0.3, 1.0),
    this.spread = const Range(-0.3, 0.3),
  });

  final Range speed;

  /// Sideways wander at birth, so a column is not a line.
  final Range spread;

  @override
  void emit(ParticleBirth birth) {
    final particle = birth.particle;
    final origin = birth.origin;
    final random = birth.random;
    particle.position.setFrom(origin);
    particle.velocity.setValues(
      spread.sample(random),
      speed.sample(random),
      spread.sample(random),
    );
  }
}
