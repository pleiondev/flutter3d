import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'particle.dart';
import 'particle_affector.dart';
import 'particle_emitter.dart';

/// A recipe for a burst: what is emitted, and what happens to it.
///
/// Data, and const-constructible, so effects live next to the game code that
/// triggers them and cost nothing to hold. Nothing here names a specific
/// effect — an explosion and a footstep puff are the same three fields with
/// different numbers.
final class ParticleEffect {
  const ParticleEffect({
    required this.count,
    required this.emitter,
    required this.lifetime,
    required this.size,
    required this.color,
    this.affectors = const <ParticleAffector>[],
  });

  /// How many particles one burst emits.
  final int count;

  final ParticleEmitter emitter;

  /// What happens to each of them, in order, every step.
  final List<ParticleAffector> affectors;

  final Range lifetime;
  final Range size;

  /// Colour at birth. Alpha reads as brightness, since these draw additively.
  final Vector4 color;
}

/// Every particle in the world, and the one buffer they are drawn from.
///
/// ## One system, not one per effect
///
/// A system per effect means a draw call per effect, and on this engine a
/// pipeline change is the most expensive state change there is. Everything
/// additive can share a pool and a buffer, and then an explosion, its smoke and
/// the sparks off the wall behind it are one draw between them.
///
/// It also means the cap is global, which is the honest way to bound the cost:
/// a per-effect cap is a promise that no combination of effects can be
/// expensive, and no such promise is true.
///
/// ## No sorting
///
/// These are drawn additively, and addition does not care about order. That is
/// what makes a shared pool possible at all — a transparent pool would need
/// sorting by depth every frame, which for a few thousand particles is the
/// whole budget. It is also why smoke here is a dark additive haze rather than
/// a proper alpha-blended puff: the second needs sorting, and it is not worth a
/// second pipeline yet.
final class ParticleSystem {
  ParticleSystem({this.capacity = 2048, math.Random? random})
      : _random = random ?? math.Random(),
        _pool = List<Particle>.generate(
          capacity,
          (_) => Particle(),
          growable: false,
        );

  /// The most particles that can be alive at once. Reached by dropping new
  /// ones, never by growing — a pool that grows under load allocates during
  /// exactly the frame that was already struggling.
  final int capacity;

  final List<Particle> _pool;
  final math.Random _random;

  /// How many emissions were refused because the pool was full.
  ///
  /// Reported rather than hidden: a number that climbs during ordinary play
  /// means the cap is wrong, and silence would make that invisible.
  int get dropped => _dropped;
  int _dropped = 0;

  int get aliveCount {
    var count = 0;
    for (final particle in _pool) {
      if (particle.alive) count++;
    }
    return count;
  }

  /// Keeps [effect] emitting at [origin], at [perSecond] particles a second.
  ///
  /// [key] identifies the source — a torch, a smoking wreck — so each keeps its
  /// own fractional remainder. Without that, a rate below one particle per
  /// frame rounds to zero every frame and the flame never lights; and rounding
  /// up instead would tie the rate to the frame rate, so a fast machine would
  /// burn brighter than a slow one.
  ///
  /// This is what a flame is. A cone is a cone however orange it is painted.
  int emitFor(
    Object key,
    ParticleEffect effect,
    Vector3 origin,
    double dt, {
    required double perSecond,
    Vector3? direction,
  }) {
    if (perSecond <= 0.0 || dt <= 0.0) return 0;
    final owed = (_owed[key] ?? 0.0) + perSecond * dt;
    final whole = owed.floor();
    _owed[key] = owed - whole;
    if (whole <= 0) return 0;

    var emitted = 0;
    for (var i = 0; i < whole; i++) {
      emitted += _emitOne(effect, origin, direction);
    }
    return emitted;
  }

  /// Forgets a source's remainder, so a torch that is put out and relit does
  /// not owe particles from before.
  void stopEmitting(Object key) => _owed.remove(key);

  final Map<Object, double> _owed = <Object, double>{};

  /// Emits one burst of [effect] at [origin].
  ///
  /// [direction] matters only to emitters that use it; it is normalised here so
  /// callers can pass a surface normal or a velocity without thinking about it.
  ///
  /// Returns how many particles were actually emitted.
  int _emitOne(ParticleEffect effect, Vector3 origin, Vector3? direction) {
    final axis = direction == null || direction.length2 < 1e-12
        ? Vector3(0.0, 1.0, 0.0)
        : direction.normalized();
    final taken = _take(0);
    if (taken == null) {
      _dropped++;
      return 0;
    }
    _initialise(taken.$1, effect, origin, axis);
    return 1;
  }

  int burst(ParticleEffect effect, Vector3 origin, {Vector3? direction}) {
    final axis = direction == null || direction.length2 < 1e-12
        ? Vector3(0.0, 1.0, 0.0)
        : direction.normalized();

    var emitted = 0;
    var cursor = 0;
    for (var i = 0; i < effect.count; i++) {
      final particle = _take(cursor);
      if (particle == null) {
        _dropped += effect.count - i;
        break;
      }
      cursor = particle.$2 + 1;
      _initialise(particle.$1, effect, origin, axis);
      emitted++;
    }
    return emitted;
  }

  /// The next free slot at or after [from], with its index.
  ///
  /// The cursor is carried across one burst so emitting two hundred particles
  /// does not rescan the pool from zero two hundred times.
  (Particle, int)? _take(int from) {
    for (var i = from; i < _pool.length; i++) {
      if (!_pool[i].alive) return (_pool[i], i);
    }
    return null;
  }

  void _initialise(
    Particle particle,
    ParticleEffect effect,
    Vector3 origin,
    Vector3 axis,
  ) {
    effect.emitter.emit(particle, origin, axis, _random);
    particle
      ..alive = true
      ..age = 0.0
      ..lifetime = effect.lifetime.sample(_random)
      ..birthSize = effect.size.sample(_random)
      ..seed = _random.nextDouble();
    particle.size = particle.birthSize;
    particle.color.setFrom(effect.color);
    particle.affectors = effect.affectors;
  }

  void step(double dt) {
    if (dt <= 0.0) return;

    for (final particle in _pool) {
      if (!particle.alive) continue;

      particle.age += dt;
      if (particle.age >= particle.lifetime) {
        particle.alive = false;
        continue;
      }

      for (final affector in particle.affectors) {
        affector.apply(particle, dt);
      }

      particle.position
        ..x += particle.velocity.x * dt
        ..y += particle.velocity.y * dt
        ..z += particle.velocity.z * dt;
    }
  }

  void clear() {
    for (final particle in _pool) {
      particle.alive = false;
    }
  }

  /// Floats one particle's quad occupies: four vertices of position, colour and
  /// texture coordinate.
  static const int floatsPerParticle = 4 * (3 + 4 + 2);

  /// Writes camera-facing quads into [vertices] and returns how many particles
  /// were written.
  ///
  /// Billboarding on the CPU: flutter_gpu has no geometry stage, and the
  /// alternative — four vertices carrying the same centre plus a corner index,
  /// expanded in the vertex shader — moves the same bytes and reconstructs what
  /// is already known here.
  ///
  /// Pure arithmetic, so this file needs no GPU and can be tested without one.
  int writeQuads(
    Vector3 cameraRight,
    Vector3 cameraUp,
    Float32List vertices,
    Uint32List indices,
  ) {
    var written = 0;
    final maxParticles = math.min(
      vertices.length ~/ floatsPerParticle,
      indices.length ~/ 6,
    );

    for (final particle in _pool) {
      if (!particle.alive) continue;
      if (written >= maxParticles) break;
      if (particle.size <= 0.0 || particle.color.w <= 0.0) continue;

      final half = particle.size * 0.5;
      final rx = cameraRight.x * half;
      final ry = cameraRight.y * half;
      final rz = cameraRight.z * half;
      final ux = cameraUp.x * half;
      final uy = cameraUp.y * half;
      final uz = cameraUp.z * half;

      var out = written * floatsPerParticle;
      for (final (sx, sy, u, v) in const <(double, double, double, double)>[
        (-1.0, -1.0, 0.0, 0.0),
        (1.0, -1.0, 1.0, 0.0),
        (1.0, 1.0, 1.0, 1.0),
        (-1.0, 1.0, 0.0, 1.0),
      ]) {
        vertices[out] = particle.position.x + rx * sx + ux * sy;
        vertices[out + 1] = particle.position.y + ry * sx + uy * sy;
        vertices[out + 2] = particle.position.z + rz * sx + uz * sy;
        vertices[out + 3] = particle.color.x;
        vertices[out + 4] = particle.color.y;
        vertices[out + 5] = particle.color.z;
        vertices[out + 6] = particle.color.w;
        vertices[out + 7] = u;
        vertices[out + 8] = v;
        out += 9;
      }

      final base = written * 4;
      final index = written * 6;
      indices[index] = base;
      indices[index + 1] = base + 1;
      indices[index + 2] = base + 2;
      indices[index + 3] = base;
      indices[index + 4] = base + 2;
      indices[index + 5] = base + 3;

      written++;
    }
    return written;
  }
}
