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
    this.iterations = 2,
    this.distanceCompliance = 0.0,
    this.bendCompliance = 1e-3,
    this.damping = 0.02,
    this.wind = const WindSettings(),
    this.collisionThickness = 0.01,
    this.friction = 0.0,
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

  /// Constraint-and-contact passes per substep.
  ///
  /// **Two, and one is not enough once the sheet wraps something.** A free
  /// sheet or a hanging curtain converges in one, which is what this used to
  /// promise for every case. Draped over a ball or a table edge it does not:
  /// a single sweep and the contacts undo each other every substep, and the
  /// residual turns into velocity — a 48×48 sheet on a ball went from half a
  /// metre a second to NaN in about thirty steps, with or without wind. A
  /// second sweep dissipates instead (measured: the same scene peaks at 0.6
  /// m/s and stretches 1.5%).
  final int iterations;

  /// Compliance of the structural (edge-length) constraints. Zero holds
  /// edges to their rest length as tightly as the substep count allows.
  final double distanceCompliance;

  /// Compliance of the cross-edge bending constraints — softer by default
  /// than the structural ones, since cloth that resists folding as hard as
  /// it resists stretching reads as cardboard, not fabric.
  final double bendCompliance;

  /// Fraction of velocity removed every **substep**, applied to the old
  /// velocity before gravity adds the substep's own. Zero is undamped; this
  /// codebase's own default leaves the cloth visibly springy rather than dead
  /// on the first swing.
  ///
  /// Per substep, so the same value damps harder at a higher [substeps]: at
  /// the default eight it behaves like a linear drag of about ten per second.
  /// This said "every full step" until 0.7.4, which it never was.
  final double damping;

  /// Aerodynamic wind force, off by default.
  final WindSettings wind;

  /// How far outside a collision shape's own surface a settled particle
  /// rests — a small positive margin so repeated pushes do not chatter a
  /// particle in and out of contact by rounding alone.
  final double collisionThickness;

  /// Coulomb friction against obstacles, at position level: how much of a
  /// contact's push may be taken back from the particle's slide along the
  /// surface in one substep, measured against the push summed over the
  /// substep's iterations, so the answer does not depend on [iterations].
  /// Zero, the default, lets a sheet slide off a ball as it always has; 0.3
  /// slows the slide, and around 1 holds a sheet dropped off-centre where it
  /// landed.
  final double friction;
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

  /// Newtons per square metre per metre-per-second of air moving through the
  /// cloth along its normal: how much of the wind-relative normal velocity
  /// becomes force. Zero turns wind off regardless of
  /// [velocityX]/[velocityY]/[velocityZ].
  ///
  /// A force since 0.7.4. It was applied as a velocity before, which made it
  /// several hundred times stronger than its value and dependent on the
  /// substep count; a scene tuned against that needs a drag in the ones to
  /// tens where it had tenths.
  final double drag;

  bool get isNone => drag == 0;
}
