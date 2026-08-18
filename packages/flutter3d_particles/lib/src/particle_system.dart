import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'flipbook.dart';
import 'light_emitter.dart';
import 'particle.dart';
import 'particle_affector.dart';
import 'particle_emitter.dart';
import 'particle_random.dart';

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

/// A standing emission: what, where, how fast, and for how long.
final class _Emission {
  _Emission(
    this.effect,
    this.origin,
    this.perSecond,
    this.direction,
    this.remaining,
  );

  final ParticleEffect effect;
  final Vector3 origin;
  final double perSecond;
  final Vector3? direction;

  /// Seconds of emission left, or null to run until stopped.
  ///
  /// Counted down in the sub-step rather than in the frame, so an emission that
  /// should last a quarter of a second emits the same particles whether the
  /// frame took four milliseconds or forty. That is the same reason the
  /// accumulator exists.
  double? remaining;

  /// Whether this emission has run out and should be dropped.
  bool get spent => remaining != null && remaining! <= 0.0;
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
  /// [seed] makes the whole simulation reproducible: the same seed and the
  /// same sequence of `advance` calls give byte-identical particles, which is
  /// what a golden of a burning torch needs.
  ///
  /// [random] is still accepted and now only supplies that seed, because a
  /// `math.Random` cannot be re-seeded and per-particle streams need to be.
  /// Passing one is deprecated; pass a seed.
  ParticleSystem({this.capacity = 2048, math.Random? random, int? seed})
      : _random = ParticleRandom(
            seed ?? random?.nextInt(0x7FFFFFFF) ?? _defaultSeed),
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
  final ParticleRandom _random;

  /// Distinct per system when nobody says otherwise, so two systems in one
  /// application do not emit the same burst.
  static const int _defaultSeed = 0x5EED;

  /// How many particles this system has ever emitted.
  ///
  /// The key each particle's random stream is derived from, so a particle's
  /// values depend on *which emission it is* rather than on how many draws
  /// anything else has taken. That is what stops adding a property from
  /// shifting every particle born after it.
  int _ordinal = 0;

  /// How many emissions were refused because the pool was full.
  ///
  /// Reported rather than hidden: a number that climbs during ordinary play
  /// means the cap is wrong, and silence would make that invisible.
  int get dropped => _dropped;
  int _dropped = 0;

  /// Forgets the drop count.
  ///
  /// A number that climbs during ordinary play means the cap is wrong; a number
  /// that never resets means it climbed once, three levels ago, and nobody can
  /// tell whether it is still climbing.
  void resetDropped() => _dropped = 0;

  /// How many of [_pool] are alive. **The live ones are always `_pool[0.._alive)`.**
  ///
  /// A dense prefix rather than an `alive` flag scanned for. Death swaps the
  /// dying particle with the last live one, so the prefix stays packed at the
  /// cost of not preserving emission order — and nothing here depends on that
  /// order, because these draw additively and addition is commutative.
  ///
  /// What it buys, measured rather than assumed: `step`, `writeQuads` and
  /// `aliveCount` all walked the whole pool, so a big pool holding a small live
  /// set paid for every empty slot every frame. At the same ~220 live particles,
  /// raising the capacity from 256 to 3000 cost 9x in `step`, 17x in
  /// `writeQuads` and 13x in `aliveCount`. That is the scan, not the layout —
  /// which is why this is a dense prefix and not a rewrite into
  /// structure-of-arrays. See `tool/bench/particle_bench.dart`.
  int _alive = 0;

  /// How many are alive, in constant time.
  ///
  /// It used to be a scan of the whole pool, and it is called every frame from
  /// `ParticleContributor.isActive`. At the dungeon's capacity of 3000 with
  /// about 220 alive that was measured at 2.7us a frame to answer a question
  /// the system already knew — see `tool/bench/particle_bench.dart`.
  int get aliveCount => _alive;

  /// Keeps [effect] emitting at [origin], at [perSecond] particles a second.
  ///
  /// [key] identifies the source — a torch, a smoking wreck — so each keeps its
  /// own fractional remainder. Without that, a rate below one particle per
  /// frame rounds to zero every frame and the flame never lights; and rounding
  /// up instead would tie the rate to the frame rate, so a fast machine would
  /// burn brighter than a slow one.
  ///
  /// This is what a flame is. A cone is a cone however orange it is painted.
  ///
  /// **Emits immediately, at the frame's own rate**, which is why it is
  /// deprecated: everything a frame owes is born at the instant the frame
  /// begins, so a burst at 30 Hz is one fat clump where 120 Hz gives four thin
  /// ones. The comment above about not tying the rate to the frame rate is
  /// true of the *count* and was never true of the *shape*.
  @Deprecated(
    'Use emit() plus advance(), which spends the rate across fixed sub-steps. '
    'This emits a whole frame at once, so the result depends on the frame rate.',
  )
  int emitFor(
    Object key,
    ParticleEffect effect,
    Vector3 origin,
    double dt, {
    required double perSecond,
    Vector3? direction,
  }) {
    if (perSecond <= 0.0 || dt <= 0.0) return 0;
    // Only what asked to be measured. See [LightEmitter].
    if (key is LightEmitter) _emitters.add(key);
    final owed = (_owed[key] ?? 0.0) + perSecond * dt;
    final whole = owed.floor();
    _owed[key] = owed - whole;
    if (whole <= 0) return 0;

    var emitted = 0;
    for (var i = 0; i < whole; i++) {
      emitted += _emitOne(effect, origin, direction, key);
    }
    return emitted;
  }

  /// Keeps [effect] emitting from [key] until told otherwise.
  ///
  /// The deferred half of [emitFor], and the one [advance] drains. Nothing is
  /// emitted here: the rate is recorded for this frame and spent inside each
  /// sub-step, so a burst at 30 Hz is not one fat clump where 120 Hz gives four
  /// thin ones. That is what [emitFor]'s doc already claimed and could not
  /// deliver, because it emitted everything the frame owed at the instant the
  /// frame began.
  ///
  /// Re-stating a rate replaces the previous one, so calling this every frame —
  /// which is what a game does — is how a torch stays lit, and *not* calling it
  /// is how it goes out.
  ///
  /// For an emission that stops itself, see [emitTimed].
  void emit(
    Object key,
    ParticleEffect effect,
    Vector3 origin, {
    required double perSecond,
    Vector3? direction,
  }) {
    if (perSecond <= 0.0) {
      _rates.remove(key);
      return;
    }
    if (key is LightEmitter) _emitters.add(key);
    _rates[key] = _Emission(effect, origin.clone(), perSecond, direction, null);
  }

  /// Emits from [key] for [seconds] and then stops on its own.
  ///
  /// The plume of smoke an explosion leaves behind, or the sparks off a wall
  /// that has just been hit: something that runs for a known time and that
  /// nobody wants to have to remember to switch off.
  ///
  /// **Call this once, not every frame.** That is the whole reason it is a
  /// separate method from [emit] rather than a `duration` argument on it. The
  /// two are called in opposite ways — [emit] is re-stated every frame and goes
  /// out when the caller stops saying it, this one is stated once and goes out
  /// by itself — and a single method taking both would have to guess which the
  /// caller meant. It guesses wrong in a way nothing catches: re-stating a
  /// countdown every frame resets the very clock that was supposed to end it,
  /// so the emission never stops and the pool fills up. The symptom is every
  /// other effect in the game quietly losing its particles to the cap.
  ///
  /// Calling it again does restart it, which is what re-firing a rocket should
  /// do.
  void emitTimed(
    Object key,
    ParticleEffect effect,
    Vector3 origin, {
    required double perSecond,
    required double seconds,
    Vector3? direction,
  }) {
    if (perSecond <= 0.0 || seconds <= 0.0) {
      _rates.remove(key);
      return;
    }
    if (key is LightEmitter) _emitters.add(key);
    _rates[key] =
        _Emission(effect, origin.clone(), perSecond, direction, seconds);
  }

  /// Advances the simulation by [dt] in fixed sub-steps.
  ///
  /// **A fixed step, because a variable one is not the same simulation.** Drag
  /// is exponential and gravity is integrated; run the same effect at 30 Hz and
  /// at 120 Hz with the frame's own delta and the two diverge visibly — the
  /// flame is a different shape on a faster machine. The goldens needed this
  /// before it existed, which is why `golden_extras.dart` hand-rolls its own
  /// fixed loop.
  ///
  /// Emission is drained *inside* the loop, so particles from one frame are
  /// spread across its sub-steps rather than all born at its first instant.
  ///
  /// The remainder below [_stepSize] is left unsimulated rather than scaled
  /// into the last sub-step: scaling would make the step variable again, which
  /// is the thing being removed. At eight milliseconds it is not visible, and
  /// interpolating for render would need a second position buffer to fix
  /// something nobody can see.
  void advance(double dt) {
    if (dt <= 0.0) return;
    _accumulator += dt;

    // A ceiling on sub-steps, because a debugger pause or a stalled frame hands
    // this a delta of several seconds and the loop would try to catch up all of
    // it — which takes longer than the stall did, and never finishes.
    var steps = 0;
    while (_accumulator >= _stepSize && steps < _maxSubSteps) {
      _drainEmitters(_stepSize);
      step(_stepSize);
      _accumulator -= _stepSize;
      steps++;
    }
    if (steps >= _maxSubSteps) _accumulator = 0.0;
  }

  /// One sub-step's worth of every standing rate.
  void _drainEmitters(double h) {
    if (_rates.isEmpty) return;
    List<Object>? spent;
    for (final entry in _rates.entries) {
      final emission = entry.value;

      // A timed emission emits for the part of this sub-step it is still
      // alive for, not for all of it. Without that, a duration of a tenth of a
      // second at 120 Hz would round up to the whole sub-step it expires in,
      // and a very short emission would be measurably longer than it asked.
      //
      // An emission is never seen here with its time already gone: it is
      // dropped at the end of the sub-step that spends it, and this runs once
      // per sub-step. So there is no expired case to handle, and a branch for
      // one would be a branch nothing can reach.
      var slice = h;
      final left = emission.remaining;
      if (left != null) {
        if (left < slice) slice = left;
        emission.remaining = left - h;
        if (emission.spent) (spent ??= <Object>[]).add(entry.key);
      }

      final owed = (_owed[entry.key] ?? 0.0) + emission.perSecond * slice;
      final whole = owed.floor();
      _owed[entry.key] = owed - whole;
      for (var i = 0; i < whole; i++) {
        _emitOne(emission.effect, emission.origin, emission.direction,
            entry.key);
      }
    }
    // Removed after the walk, not during it: mutating the map being iterated
    // throws, and the throw would land in whichever frame first ran an
    // emission out — a crash whose trigger is a duration nobody was thinking
    // about.
    if (spent != null) {
      for (final key in spent) {
        stopEmitting(key);
      }
    }
  }

  /// Forgets a source's remainder, so a torch that is put out and relit does
  /// not owe particles from before.
  void stopEmitting(Object key) {
    _owed.remove(key);
    _rates.remove(key);
    // The emitter stays in `_emitters`. Its particles are still alive and still
    // casting light, and `step` drops it once they are gone — see the note
    // there. Removing it here is what used to leave a snuffed torch shining.
  }

  /// Simulated seconds per sub-step.
  ///
  /// A hundred and twenty, which is twice the common display rate: fast enough
  /// that a 60 Hz frame is two whole sub-steps rather than one and a
  /// remainder, and slow enough that a 30 Hz frame is four rather than eight.
  static const double _stepSize = 1.0 / 120.0;

  /// Sub-steps one [advance] may take before it gives up and drops the rest.
  static const int _maxSubSteps = 8;

  double _accumulator = 0.0;
  final Map<Object, _Emission> _rates = <Object, _Emission>{};

  final Set<LightEmitter> _emitters = <LightEmitter>{};

  final Map<Object, double> _owed = <Object, double>{};

  /// Emits one burst of [effect] at [origin].
  ///
  /// [direction] matters only to emitters that use it; it is normalised here so
  /// callers can pass a surface normal or a velocity without thinking about it.
  ///
  /// Returns how many particles were actually emitted.
  int _emitOne(
    ParticleEffect effect,
    Vector3 origin,
    Vector3? direction,
    Object? source,
  ) {
    final axis = direction == null || direction.length2 < 1e-12
        ? Vector3(0.0, 1.0, 0.0)
        : direction.normalized();
    final taken = _take();
    if (taken == null) {
      _dropped++;
      return 0;
    }
    _initialise(taken, effect, origin, axis);
    taken.source = source;
    return 1;
  }

  int burst(ParticleEffect effect, Vector3 origin, {Vector3? direction}) {
    final axis = direction == null || direction.length2 < 1e-12
        ? Vector3(0.0, 1.0, 0.0)
        : direction.normalized();

    var emitted = 0;
    for (var i = 0; i < effect.count; i++) {
      final particle = _take();
      if (particle == null) {
        _dropped += effect.count - i;
        break;
      }
      _initialise(particle, effect, origin, axis);
      emitted++;
    }
    return emitted;
  }

  /// The next free slot, or null when the pool is full.
  ///
  /// Constant time: the live set is a dense prefix, so the first free slot is
  /// always the one just past it. This replaced a linear scan carrying a cursor
  /// across a burst, which was the best that could be done without compaction.
  Particle? _take() => _alive < _pool.length ? _pool[_alive++] : null;

  void _initialise(
    Particle particle,
    ParticleEffect effect,
    Vector3 origin,
    Vector3 axis,
  ) {
    final ordinal = _ordinal++;
    _random.reseed(ordinal, ParticleSalt.emitter);
    effect.emitter.emit(particle, origin, axis, _random);
    _random.reseed(ordinal, ParticleSalt.birth);
    particle
      ..alive = true
      // Cleared, not left. A slot is reused, and [source] is the only field
      // here that a *previous* occupant sets and this method did not — so a
      // burst landing in a slot a torch's flame had just vacated inherited the
      // torch, and `step` fed the burst's particles into that torch's
      // [ParticleGlow]. A rocket going off near a wall brightened the torch on
      // it. [_emitOne] assigns the real source after this returns.
      ..source = null
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

    for (final emitter in _emitters) {
      emitter.glow.beginStep();
    }

    // Not a for-in: a dying particle is swapped with the last live one, and
    // the one swapped into its slot has not been stepped yet, so the index
    // must not advance. Walking `_pool` directly would step it twice.
    var i = 0;
    while (i < _alive) {
      final particle = _pool[i];

      particle.age += dt;
      if (particle.age >= particle.lifetime) {
        particle.alive = false;
        _alive--;
        _pool[i] = _pool[_alive];
        _pool[_alive] = particle;
        continue;
      }

      for (final affector in particle.affectors) {
        affector.apply(particle, dt);
      }

      particle.position
        ..x += particle.velocity.x * dt
        ..y += particle.velocity.y * dt
        ..z += particle.velocity.z * dt;

      final source = particle.source;
      if (source is LightEmitter) source.glow.accumulate(particle);
      i++;
    }

    List<LightEmitter>? finished;
    for (final emitter in _emitters) {
      emitter.glow.endStep(dt);
      // An emitter stops being measured when it has nothing left to measure:
      // no particles this step, no light still fading, and no standing rate
      // about to make more.
      //
      // **`stopEmitting` deliberately does not do this itself**, and that is
      // the bug this replaced. Removing the emitter there froze its glow at
      // whatever it last read, because nothing called `beginStep` on it again
      // — so a torch that was put out kept casting exactly as much light as it
      // had while burning, while its flame visibly died. The light has to
      // follow the particles down, and the particles outlive the rate that
      // made them.
      if (emitter.glow.count == 0 &&
          emitter.glow.power < _glowFloor &&
          !_rates.containsKey(emitter)) {
        (finished ??= <LightEmitter>[]).add(emitter);
      }
    }
    if (finished != null) {
      for (final emitter in finished) {
        _emitters.remove(emitter);
      }
    }
  }

  /// Below this a glow is out, and its emitter stops being walked every step.
  ///
  /// Needed because the smoothing is exponential and never reaches zero: an
  /// emitter dropped the instant its last particle died would freeze at a small
  /// but non-zero power, which is a torch that has gone out still lighting the
  /// wall behind it — dimly, and forever.
  static const double _glowFloor = 1e-4;

  void clear() {
    for (var i = 0; i < _alive; i++) {
      _pool[i].alive = false;
    }
    _alive = 0;
  }

  /// Floats one particle's quad occupies: four vertices of position, colour and
  /// texture coordinate.
  static const int floatsPerParticle = 4 * (3 + 4 + 2);

  /// Floats one mesh-particle instance occupies: a place, a colour, a size.
  ///
  /// Eight rather than the sixteen a full transform would take. A particle's
  /// size is one number everywhere else in this engine, and a uniform scale
  /// leaves a normal a normal — which is why the mesh stage needs no inverse
  /// transpose and why this is the cheap layout rather than the lazy one.
  static const int floatsPerInstance = 3 + 4 + 1;

  /// Writes one record per live particle for an instanced mesh draw, and
  /// returns how many were written.
  ///
  /// The counterpart to [writeQuads], and much smaller: a billboard costs four
  /// vertices of nine floats because the quad *is* the particle, while a mesh
  /// particle costs eight floats because the geometry is already on the device
  /// and only the placement changes.
  ///
  /// Stops when [out] is full rather than growing it, for the same reason
  /// [writeQuads] does: the buffer is sized from the pool's capacity once, and
  /// a frame that would overrun it is a frame with a bug in the caller.
  int writeInstances(Float32List out) {
    final room = out.length ~/ floatsPerInstance;
    final count = _alive < room ? _alive : room;
    for (var i = 0; i < count; i++) {
      final particle = _pool[i];
      final at = i * floatsPerInstance;
      out[at] = particle.position.x;
      out[at + 1] = particle.position.y;
      out[at + 2] = particle.position.z;
      out[at + 3] = particle.color.x;
      out[at + 4] = particle.color.y;
      out[at + 5] = particle.color.z;
      out[at + 6] = particle.color.w;
      out[at + 7] = particle.size;
    }
    return count;
  }

  /// Writes camera-facing quads into [vertices] and returns how many particles
  /// were written.
  ///
  /// Billboarding on the CPU: no backend here has a geometry stage, and the
  /// alternative — four vertices carrying the same centre plus a corner index,
  /// expanded in the vertex shader — moves the same bytes and reconstructs what
  /// is already known here.
  ///
  /// Pure arithmetic, so this file needs no GPU and can be tested without one.
  int writeQuads(
    Vector3 cameraRight,
    Vector3 cameraUp,
    Float32List vertices,
    Uint32List indices, {
    Flipbook? flipbook,
  }) {
    var written = 0;
    final maxParticles = math.min(
      vertices.length ~/ floatsPerParticle,
      indices.length ~/ 6,
    );

    for (var i = 0; i < _alive; i++) {
      final particle = _pool[i];
      if (written >= maxParticles) break;
      if (particle.size <= 0.0 || particle.color.w <= 0.0) continue;

      final half = particle.size * 0.5;

      // The quad's own axes, which are the camera's turned by the particle's
      // rotation. Turning the axes rather than the corners is what makes a
      // rotation cost two trigonometric calls per particle instead of eight
      // multiplies per corner — and it is exact, because rotating a basis and
      // rotating everything expressed in it are the same operation.
      var ax = cameraRight.x;
      var ay = cameraRight.y;
      var az = cameraRight.z;
      var bx = cameraUp.x;
      var by = cameraUp.y;
      var bz = cameraUp.z;
      if (particle.rotation != 0.0) {
        final c = math.cos(particle.rotation);
        final s = math.sin(particle.rotation);
        ax = cameraRight.x * c + cameraUp.x * s;
        ay = cameraRight.y * c + cameraUp.y * s;
        az = cameraRight.z * c + cameraUp.z * s;
        bx = cameraUp.x * c - cameraRight.x * s;
        by = cameraUp.y * c - cameraRight.y * s;
        bz = cameraUp.z * c - cameraRight.z * s;
      }
      final rx = ax * half;
      final ry = ay * half;
      final rz = az * half;
      final ux = bx * half;
      final uy = by * half;
      final uz = bz * half;

      // Which cell of the atlas this particle is showing, as a rectangle in
      // texture space. Null is the whole texture, which is the zero-to-one the
      // corners already carry.
      final cell = flipbook?.cellFor(particle);

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
        vertices[out + 7] = cell == null ? u : cell.left + u * cell.width;
        vertices[out + 8] = cell == null ? v : cell.top + v * cell.height;
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


