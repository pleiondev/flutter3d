/// Values that change over a particle's life, described rather than computed.
///
/// The affectors that came first each hard-coded a shape: [ParticleFade] goes
/// down, [ParticleSizeOverLife] goes from one number to another, and a particle
/// that should puff up and then shrink needed two affectors fighting over the
/// same field. A curve says the shape once, as data, and one affector reads it.
///
/// ## Why the ease belongs to the key before the segment
///
/// A keyframed curve has an off-by-one nobody agrees on: given keys at 0.0 and
/// 1.0, does the interpolation mode belong to the key you are leaving or the one
/// you are arriving at? Both conventions exist and both read naturally in
/// isolation, which is exactly why the choice has to be written down.
///
/// Here **[CurveKey.ease] describes how the value leaves that key**, so the last
/// key's ease is never read. Chosen because it makes a step curve read the way a
/// reader expects: a key with [KeyEase.step] holds its own value until the next
/// key, rather than reaching back and freezing the previous one.
///
/// ## Sampling is a linear scan
///
/// Not a binary search. These carry two to five keys — a curve with enough keys
/// for a search to win is a curve nobody can read — and the scan touches
/// contiguous memory that a search would jump around.
///
/// This has **not** been measured, and it is cheap enough to be worth saying so
/// rather than implying otherwise: the cost is paid per particle per step, so
/// if a curve ever grows past a handful of keys, `tool/bench` is the place to
/// settle it. The argument above is a reason to start here, not a result.
library;

import 'key_ease.dart';

export 'curve_affectors.dart';
export 'key_ease.dart';
export 'particle_gradient.dart';

/// One point on a [ParticleCurve].
final class CurveKey {
  const CurveKey(this.at, this.value, {this.ease = KeyEase.linear});

  /// Where in the particle's life this key sits, in `[0, 1]`.
  final double at;

  final double value;

  /// How the value leaves this key on its way to the next. Never read on the
  /// last key — see the note in the library comment.
  final KeyEase ease;
}

/// A scalar over a particle's life.
final class ParticleCurve {
  /// Keys must be ordered by [CurveKey.at] and there must be at least one.
  ///
  /// Not a `const` constructor, and the assert is why: checking that a list is
  /// sorted needs a loop, and a const constructor's asserts are limited to
  /// constant expressions. An unsorted curve samples wrong rather than
  /// throwing, and it does so only for the range between the two keys that are
  /// out of order — which is the sort of defect that reaches a golden and looks
  /// like a physics bug.
  ParticleCurve(this.keys)
      : assert(keys.isNotEmpty, 'a curve with no keys has no value'),
        assert(_isSorted(keys), 'curve keys must be ordered by `at`');

  /// A curve that never moves.
  ParticleCurve.constant(double value) : this(<CurveKey>[CurveKey(0.0, value)]);

  /// The two-key case, which is most of them.
  ParticleCurve.linear(double from, double to)
      : this(<CurveKey>[CurveKey(0.0, from), CurveKey(1.0, to)]);

  final List<CurveKey> keys;

  static bool _isSorted(List<CurveKey> keys) {
    for (var i = 1; i < keys.length; i++) {
      if (keys[i].at < keys[i - 1].at) return false;
    }
    return true;
  }

  /// The value at [t], which is clamped into `[0, 1]` by the caller's life.
  ///
  /// Outside the keys the curve holds its end values rather than extrapolating.
  /// Extrapolation would let a size curve that stops at 0.8 keep shrinking past
  /// zero and flip the quad inside out.
  double sample(double t) {
    final last = keys.length - 1;
    if (t <= keys[0].at) return keys[0].value;
    if (t >= keys[last].at) return keys[last].value;

    for (var i = 0; i < last; i++) {
      final a = keys[i];
      final b = keys[i + 1];
      if (t > b.at) continue;
      final span = b.at - a.at;
      // Two keys at the same spot is a deliberate hard edge, not an error.
      // Dividing by the zero span would give a NaN that spreads silently.
      if (span <= 0.0) return b.value;
      return a.value + (b.value - a.value) * easeShape((t - a.at) / span, a.ease);
    }
    return keys[last].value;
  }
}
