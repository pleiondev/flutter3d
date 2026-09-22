/// How a value travels from one key to the next.
///
/// **A value class rather than an enum, and the shape is carried on it.**
/// Opening the list alone would have been useless: a game could name its own
/// ease and `easeShape` would have had no branch for it. So an ease *is* its
/// curve — a game writes `const KeyEase('bounce', _bounce)` and every
/// [ParticleCurve] and [ParticleGradient] in the engine samples it without
/// this package having heard of it.
///
/// `base` so a shape added here later is inherited rather than missing.
final class KeyEase {
  const KeyEase(this.name, this.shape);

  /// What it is called, in a saved effect and in a debug overlay. Identity:
  /// two eases with the same name are the same ease.
  final String name;

  /// Maps a fraction already normalised into `[0, 1]` onto the eased one.
  ///
  /// A function rather than a method to override, so an ease stays a `const`
  /// value: an effect is data, and data with a subclass in it cannot be a
  /// constant.
  final double Function(double t) shape;

  /// Holds until the next key, then jumps. Flipbooks and anything that should
  /// read as discrete rather than as a blend.
  static const KeyEase step = KeyEase('step', _step);

  /// Straight line. What a keyframed curve means by default everywhere.
  static const KeyEase linear = KeyEase('linear', _linear);

  /// Smoothstep: leaves and arrives at rest. A puff of smoke that expands and
  /// settles reads wrong with linear segments, because the corner at the top of
  /// the curve is visible as a crease in the motion.
  static const KeyEase smooth = KeyEase('smooth', _smooth);

  @override
  bool operator ==(Object other) => other is KeyEase && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'KeyEase($name)';
}

double _step(double t) => 0.0;
double _linear(double t) => t;

/// 3t squared minus 2t cubed. The classic, and cheap: two multiplies and a
/// subtract.
double _smooth(double t) => t * t * (3.0 - 2.0 * t);

/// Applies [ease] to a fraction already normalised into `[0, 1]`.
///
/// Shared by [ParticleCurve] and [ParticleGradient], which sample the same
/// shape of segment over two different kinds of value. Kept as a function
/// rather than replaced by `ease.shape(t)` at every call site, because it is
/// what those two say and it is the one place the contract on `t` is written.
double easeShape(double t, KeyEase ease) => ease.shape(t);
