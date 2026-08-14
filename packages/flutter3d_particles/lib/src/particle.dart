import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'particle_affector.dart';

/// One particle, reused for the life of the system.
///
/// A pooled object rather than parallel typed arrays. Struct-of-arrays is the
/// faster layout in principle, and at the few thousand particles a corridor
/// shooter puts on screen the difference is not measurable — while the cost of
/// reading fourteen parallel `Float32List`s every time somebody touches this
/// file is paid on every change. Allocated once and reused, which is the part
/// that actually matters.
final class Particle {
  final Vector3 position = Vector3.zero();
  final Vector3 velocity = Vector3.zero();

  /// Linear RGB and an alpha that behaves as brightness, since these are drawn
  /// additively.
  final Vector4 color = Vector4.zero();

  /// How far the quad is turned about the view axis, in radians.
  ///
  /// Zero for every particle nothing rotates, and the billboard path checks for
  /// that before doing any trigonometry — a burst of two hundred untextured
  /// sparks should not pay for a feature it does not use.
  ///
  /// **Only a billboard turns.** A mesh particle is a shape in the world and
  /// would need a real orientation; this is the angle of a camera-facing quad
  /// about the direction it faces, which is the only rotation a billboard has.
  double rotation = 0.0;

  double age = 0.0;
  double lifetime = 0.0;
  double size = 0.0;

  /// The size this particle was born with.
  ///
  /// Kept apart from [size] so an affector that scales over life recomputes
  /// from the original each step. Multiplying [size] repeatedly compounds, and
  /// a particle meant to halve over a second vanishes in a tenth of one.
  double birthSize = 0.0;

  /// Set once when the particle is emitted, so an affector can vary a value per
  /// particle without asking for a random number every step and losing
  /// determinism.
  double seed = 0.0;

  /// What emitted this, for anything that wants to measure a fire rather than
  /// guess at it. Null for a burst that nobody keyed.
  Object? source;

  /// What happens to this particle each step.
  ///
  /// Held here rather than in a map from particle to affectors: the pool is
  /// shared between effects, so a particle outlives the burst that emitted it
  /// and has to carry its own rules — and hashing an object per particle per
  /// step is a cost with nothing to show for it.
  ///
  /// The list is shared with the effect and never mutated.
  List<ParticleAffector> affectors = const <ParticleAffector>[];

  bool alive = false;

  /// How far through its life, in `[0, 1]`.
  double get life {
    if (lifetime <= 0.0) return 1.0;
    final t = age / lifetime;
    return t < 0.0 ? 0.0 : (t > 1.0 ? 1.0 : t);
  }
}

/// A range a value is drawn from when a particle is born.
///
/// A pair rather than a single number, because identical particles read as a
/// texture rather than as an effect — variation in size and lifetime is most of
/// what makes a burst look like one.
final class Range {
  const Range(this.min, this.max);

  const Range.exact(double value)
      : min = value,
        max = value;

  final double min;
  final double max;

  double sample(math.Random random) =>
      min == max ? min : min + random.nextDouble() * (max - min);
}
