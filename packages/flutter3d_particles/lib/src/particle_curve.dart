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

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'particle.dart';
import 'particle_affector.dart';

/// How a value travels from one key to the next.
enum KeyEase {
  /// Holds until the next key, then jumps. Flipbooks and anything that should
  /// read as discrete rather than as a blend.
  step,

  /// Straight line. What a keyframed curve means by default everywhere.
  linear,

  /// Smoothstep: leaves and arrives at rest. A puff of smoke that expands and
  /// settles reads wrong with linear segments, because the corner at the top of
  /// the curve is visible as a crease in the motion.
  smooth,
}

/// Applies [ease] to a fraction already normalised into `[0, 1]`.
double _shape(double t, KeyEase ease) => switch (ease) {
      KeyEase.step => 0.0,
      KeyEase.linear => t,
      // 3t² − 2t³. The classic, and cheap: two multiplies and a subtract.
      KeyEase.smooth => t * t * (3.0 - 2.0 * t),
    };

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
      return a.value + (b.value - a.value) * _shape((t - a.at) / span, a.ease);
    }
    return keys[last].value;
  }
}

/// One point on a [ParticleGradient].
final class GradientKey {
  const GradientKey(this.at, this.color, {this.ease = KeyEase.linear});

  /// Where in the particle's life this key sits, in `[0, 1]`.
  final double at;

  /// Linear RGB with alpha as brightness, matching [Particle.color].
  final Vector4 color;

  final KeyEase ease;
}

/// A colour over a particle's life.
///
/// Separate from [ParticleCurve] rather than a curve of four channels: four
/// independent curves let the channels' keys fall at different points, which is
/// how a colour ramp ends up with a grey frame in the middle that nobody put
/// there. A gradient's keys are keys of the whole colour.
final class ParticleGradient {
  ParticleGradient(this.keys)
      : assert(keys.isNotEmpty, 'a gradient with no keys has no colour'),
        assert(_isSorted(keys), 'gradient keys must be ordered by `at`');

  ParticleGradient.constant(Vector4 color)
      : this(<GradientKey>[GradientKey(0.0, color)]);

  ParticleGradient.linear(Vector4 from, Vector4 to)
      : this(<GradientKey>[GradientKey(0.0, from), GradientKey(1.0, to)]);

  final List<GradientKey> keys;

  static bool _isSorted(List<GradientKey> keys) {
    for (var i = 1; i < keys.length; i++) {
      if (keys[i].at < keys[i - 1].at) return false;
    }
    return true;
  }

  /// Writes the colour at [t] into [out], allocating nothing.
  ///
  /// Into an output parameter because this is called per particle per step and
  /// returning a fresh [Vector4] would allocate once per particle per frame —
  /// at a few thousand particles that is the difference between a garbage
  /// collection nobody notices and one that shows up as a hitch.
  void sampleInto(Vector4 out, double t) {
    final last = keys.length - 1;
    if (t <= keys[0].at) {
      out.setFrom(keys[0].color);
      return;
    }
    if (t >= keys[last].at) {
      out.setFrom(keys[last].color);
      return;
    }

    for (var i = 0; i < last; i++) {
      final a = keys[i];
      final b = keys[i + 1];
      if (t > b.at) continue;
      final span = b.at - a.at;
      if (span <= 0.0) {
        out.setFrom(b.color);
        return;
      }
      final k = _shape((t - a.at) / span, a.ease);
      out.setValues(
        a.color.x + (b.color.x - a.color.x) * k,
        a.color.y + (b.color.y - a.color.y) * k,
        a.color.z + (b.color.z - a.color.z) * k,
        a.color.w + (b.color.w - a.color.w) * k,
      );
      return;
    }
    out.setFrom(keys[last].color);
  }
}

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
