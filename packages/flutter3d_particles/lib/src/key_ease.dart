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
///
/// Shared by [ParticleCurve] and [ParticleGradient], which sample the same
/// shape of segment over two different kinds of value.
double easeShape(double t, KeyEase ease) => switch (ease) {
      KeyEase.step => 0.0,
      KeyEase.linear => t,
      // 3t² − 2t³. The classic, and cheap: two multiplies and a subtract.
      KeyEase.smooth => t * t * (3.0 - 2.0 * t),
    };
