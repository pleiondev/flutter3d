/// How a [ClothMesh] moves, as values rather than as solver internals.
///
/// XPBD's own compliance is the inverse of stiffness — zero is a rigid,
/// inextensible constraint, and a small positive number is a constraint that
/// yields under load and recovers. Kept as a plain field here rather than a
/// spring constant because compliance is the one parameter in XPBD whose
/// result does not change with the substep count, which a spring constant's
/// does — the whole reason the "X" is in XPBD.
final class ClothSettings {
  const ClothSettings({
    this.gravity = 9.81,
    this.substeps = 8,
    this.iterations = 1,
    this.distanceCompliance = 0.0,
    this.bendCompliance = 1e-3,
    this.damping = 0.02,
    this.wind = const WindSettings(),
    this.collisionThickness = 0.01,
  });

  /// Downward acceleration, metres per second squared.
  final double gravity;

  /// How many substeps one call to `stepCloth` divides its `dt` into.
  ///
  /// XPBD's own stability comes from here, not from more constraint-solve
  /// iterations at a coarse step: a stiff constraint solved once at a small
  /// substep converges where the same constraint solved ten times at a large
  /// one still overshoots. [distanceCompliance] at zero needs several
  /// substeps to look inextensible; raising this is the first thing to try
  /// before touching a compliance value.
  final int substeps;

  /// Constraint-solve passes per substep. XPBD converges in one; more than
  /// one trades speed for a stiffer-looking result at the same compliance.
  final int iterations;

  /// Compliance of the structural (edge-length) constraints. Zero holds
  /// edges to their rest length as tightly as the substep count allows.
  final double distanceCompliance;

  /// Compliance of the cross-edge bending constraints — softer by default
  /// than the structural ones, since cloth that resists folding as hard as
  /// it resists stretching reads as cardboard, not fabric.
  final double bendCompliance;

  /// Fraction of velocity removed every full step, applied after the
  /// constraint solve. Zero is undamped; this codebase's own default
  /// leaves the cloth visibly springy rather than dead on the first swing.
  final double damping;

  /// Aerodynamic wind force, off by default.
  final WindSettings wind;

  /// How far outside a collision shape's own surface a settled particle
  /// rests — a small positive margin so repeated pushes do not chatter a
  /// particle in and out of contact by rounding alone.
  final double collisionThickness;
}

/// A uniform wind field, applied per triangle as drag along its own normal.
final class WindSettings {
  const WindSettings({
    this.velocityX = 0,
    this.velocityY = 0,
    this.velocityZ = 0,
    this.drag = 0.3,
  });

  final double velocityX;
  final double velocityY;
  final double velocityZ;

  /// How much of the wind-relative normal velocity becomes force. Zero
  /// turns wind off regardless of [velocityX]/[velocityY]/[velocityZ].
  final double drag;

  bool get isNone => drag == 0;
}
