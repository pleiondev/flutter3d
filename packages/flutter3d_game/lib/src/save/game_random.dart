/// Randomness with a state you can write down.
///
/// `math.Random` has no readable state, which makes it the one thing in a
/// simulation that cannot be put in a snapshot. Two saves taken a step apart
/// would restore to worlds that then diverge — a monster flinches in one and
/// not the other — and a determinism test could never be exact.
///
/// **Xorshift rather than a multiplying mixer**, for the reason
/// `ParticleRandom` in `flutter3d_particles` already gives: this engine runs on
/// the web, where an `int` is a double and a 32-by-32 multiply loses the top
/// bits silently. Shifts and xors are exact in both worlds. The quality is well
/// past what a flinch roll needs and nowhere near cryptographic, which nothing
/// here is.
library;

import 'dart:math' as math;

final class GameRandom implements math.Random {
  GameRandom(int seed) : _state = _seeded(seed);

  /// The whole generator, as one number.
  ///
  /// Read it into a snapshot and write it back to continue the same sequence.
  int get state => _state;
  set state(int value) => _state = _seeded(value);
  int _state;

  /// Zero is a fixed point of xorshift — it would return zero for ever — so it
  /// is the one seed that has to be replaced rather than used.
  static int _seeded(int value) {
    final masked = value & 0xFFFFFFFF;
    return masked == 0 ? 0x9E3779B9 : masked;
  }

  int _next() {
    var x = _state;
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    return _state = x & 0xFFFFFFFF;
  }

  @override
  int nextInt(int max) {
    if (max <= 0) throw RangeError.range(max, 1, null, 'max');
    return _next() % max;
  }

  @override
  double nextDouble() => _next() / 4294967296.0;

  @override
  bool nextBool() => _next() & 1 == 1;
}
