/// Randomness a particle owns, rather than randomness it takes a turn at.
///
/// The system used to hold one `math.Random` and let every birth draw from it
/// in turn. That is deterministic — the same seed and the same call sequence
/// give the same particles — and it is fragile in a specific way: **adding a
/// property shifts every draw after it.** Give `ParticleEffect` one more
/// sampled field, or an emitter one more call, and every particle born
/// afterwards gets different values, so every golden with particles in it
/// moves for a reason that has nothing to do with what changed.
///
/// Here each particle's values come from its own stream, keyed on the system's
/// seed and the particle's emission ordinal. Adding a property adds a draw to
/// one particle's stream and leaves every other particle alone.
///
/// It implements `math.Random` on purpose. `ParticleEmitter.emit` takes one,
/// and that class is public and meant to be extended by games — changing its
/// signature to thread a different generator would break every emitter anybody
/// has written, to no benefit they can see.
///
/// **Xorshift rather than a multiplying mixer**, because this engine runs on
/// the web, where an `int` is a double and a 32-by-32 multiply loses the top
/// bits silently. Shifts and xors are exact in both worlds. The quality is well
/// past what a flame needs and would not be enough for anything cryptographic,
/// which nothing here is.
library;

import 'dart:math' as math;

/// A reusable, re-seedable generator.
///
/// One instance is kept by the system and re-seeded per particle rather than
/// allocated per particle: a torch emits a hundred and fifty a second and this
/// sits on the frame path.
final class ParticleRandom implements math.Random {
  ParticleRandom(this.systemSeed);

  /// The system's own seed. Two systems with the same one produce the same
  /// particles from the same ordinals.
  final int systemSeed;

  int _state = 1;

  /// Points this at the stream belonging to [ordinal] within [salt].
  ///
  /// [salt] separates the streams a single particle needs — its birth
  /// properties, its emitter's direction — so an emitter that draws one more
  /// number does not shift the lifetime of the particle it is emitting.
  void reseed(int ordinal, int salt) {
    // Fold the three together, then stir. The stir matters: consecutive
    // ordinals differ in one low bit, and xorshift alone would give
    // consecutive particles visibly similar first draws.
    var x = (systemSeed ^ (ordinal * 0x9E37) ^ (salt << 20)) & 0xFFFFFFFF;
    if (x == 0) x = 0x1234567;
    _state = x;
    for (var i = 0; i < 3; i++) {
      _advance();
    }
  }

  int _advance() {
    var x = _state;
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    _state = x;
    return x;
  }

  @override
  double nextDouble() => _advance() / 4294967296.0;

  @override
  int nextInt(int max) {
    if (max <= 0) throw RangeError.value(max, 'max', 'must be positive');
    return _advance() % max;
  }

  @override
  bool nextBool() => _advance() & 1 == 1;
}

/// Which stream a draw comes from.
///
/// Kept together so a new one is added by reading a list rather than by
/// guessing a number nothing else uses.
abstract final class ParticleSalt {
  /// Lifetime, size, and the particle's own `seed`.
  static const int birth = 1;

  /// Whatever the emitter draws: direction, speed, offset.
  static const int emitter = 2;
}
