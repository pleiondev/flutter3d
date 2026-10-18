import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show SimulationProfile;

/// How a [ClothMesh] moves, as values rather than as solver internals.
///
/// XPBD's own compliance is the inverse of stiffness — zero is a rigid,
/// inextensible constraint, and a small positive number is a constraint that
/// yields under load and recovers. Kept as a plain field here rather than a
/// spring constant because compliance is the one parameter in XPBD whose
/// result does not change with the substep count, which a spring constant's
/// does — the whole reason the "X" is in XPBD.
final class ClothSettings {
  /// Settings for a cloth in standard gravity and still air: eight
  /// substeps of two iterations, rigid edges, a soft bend, a softer shear,
  /// one-centimetre collision thickness and self-collision on.
  const ClothSettings({
    this.gravity = standardGravity,
    this.substeps = 8,
    this.iterations = 2,
    this.distanceCompliance = 0.0,
    this.bendCompliance = 1e-3,
    this.shearCompliance = 5e-2,
    this.damping = 0.02,
    this.wind = const WindSettings(),
    this.collisionThickness = 0.01,
    this.friction = 0.0,
    this.selfCollision = true,
    this.selfCollisionThickness,
    this.selfCollisionFriction = 0.1,
    this.profile = SimulationProfile.deterministic,
  });

  /// A copy with the given fields replaced. A `clear…` flag resets that
  /// nullable field to null, which passing null cannot say.
  ClothSettings copyWith({
    SimulationProfile? profile,
    double? gravity,
    int? substeps,
    int? iterations,
    double? distanceCompliance,
    double? bendCompliance,
    double? shearCompliance,
    double? damping,
    WindSettings? wind,
    double? collisionThickness,
    double? friction,
    bool? selfCollision,
    double? selfCollisionThickness,
    double? selfCollisionFriction,
    bool clearSelfCollisionThickness = false,
  }) => ClothSettings(
    gravity: gravity ?? this.gravity,
    substeps: substeps ?? this.substeps,
    iterations: iterations ?? this.iterations,
    distanceCompliance: distanceCompliance ?? this.distanceCompliance,
    bendCompliance: bendCompliance ?? this.bendCompliance,
    shearCompliance: shearCompliance ?? this.shearCompliance,
    damping: damping ?? this.damping,
    wind: wind ?? this.wind,
    collisionThickness: collisionThickness ?? this.collisionThickness,
    friction: friction ?? this.friction,
    selfCollision: selfCollision ?? this.selfCollision,
    selfCollisionThickness: clearSelfCollisionThickness
        ? null
        : (selfCollisionThickness ?? this.selfCollisionThickness),
    selfCollisionFriction: selfCollisionFriction ?? this.selfCollisionFriction,
    profile: profile ?? this.profile,
  );

  /// These settings in [world], for a sheet of [material] when one is
  /// given: the world's gravity, its wind blowing through the sheet in its
  /// air ([WindSettings.airDensity]), and the material's friction against
  /// what the sheet lies on, at [state] — what a cloth hung in that world
  /// falls, flaps and slides by, and the world's simulation profile.
  /// Everything else is kept, and calling it
  /// again with another world gives that world's, not both.
  ///
  /// **How a game gives a sheet its world**: `settings.inWorld(
  /// collision.properties)`, made again when the world changes, so a level
  /// on the Moon drapes its banners at the Moon's gravity and a sheet in
  /// thin air flaps less in the same wind.
  ///
  /// **The material's mechanical group.** Its coefficient of friction
  /// (`MechanicalProperties.friction`) at [state], the reference state by
  /// default, becomes [friction]; a material that says none leaves the
  /// friction as it was. Its density is a sheet's mass, which the mesh
  /// holds: `ClothMesh.grid(mass: ClothMesh.particleMassOf(…))`.
  ClothSettings inWorld(
    WorldProperties world, {
    PhysicalMaterial? material,
    MatterState state = MatterState.standard,
  }) {
    final air = world.wind;
    final mu = material?.mechanical?.friction?.at(state);
    return copyWith(
      gravity: world.gravityMagnitude,
      wind: wind.copyWith(
        velocityX: air.x,
        velocityY: air.y,
        velocityZ: air.z,
        airDensity: world.airDensity,
      ),
      friction: mu,
      profile: world.profile,
    );
  }

  /// What the steps promise about their numbers.
  ///
  /// Under a profile that `allowsAdaptiveSteps` the sheet is not stepped by
  /// XPBD but integrated: an adaptive Runge–Kutta integrator held to a
  /// relative error of 1e-10 carries every particle through the step, the
  /// zero-compliance constraints held exactly by their Lagrange multipliers
  /// and every other one a spring of stiffness one over its compliance, and
  /// [damping] a drag at the rate it has at [substeps]. Obstacles and the
  /// sheet's own layers are pushed apart between the integrator's steps, as
  /// the fixed path does, and are not held to analytic tests. [substeps]
  /// and [iterations] say nothing there. The deterministic profile, the
  /// default, is the XPBD step.
  final SimulationProfile profile;

  /// Downward acceleration, metres per second squared: the world's the
  /// cloth hangs in ([inWorld]); [standardGravity] when a game gives it
  /// none.
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

  /// Compliance of the shear constraints, the diagonals of each quad.
  ///
  /// **Soft, and not zero.** Woven cloth follows a ball by shearing its
  /// threads, so a stiff shear stood a sheet off the top of the ball in a
  /// tent and set it shaking; none let every quad fold into a rhombus.
  /// Measured on a 1.8 m square over a 0.55 m ball, 5e-2 keeps the corners
  /// 8 to 24 cm above the floor they cannot reach, and still lets the sheet
  /// lie on the sphere. See `ClothMesh.shearPairs`.
  final double shearCompliance;

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
  /// landed. A unitless coefficient.
  final double friction;

  /// Whether the sheet keeps its own layers apart.
  ///
  /// **Without it a sheet passes through itself.** An 80×80 square dropped
  /// on a ball folds a corner under itself where it meets the floor, and the
  /// two layers interpenetrate; drawn, that is a flat grey triangle and
  /// patches that flicker between the layers. With it every particle is a
  /// sphere of [selfCollisionThickness] that the others are pushed out of,
  /// except the ones already that close in the rest shape
  /// (`ClothMesh.restPositions`).
  ///
  /// **On by default, because it is cheap next to the rest of the step.**
  /// Measured on an 80×80 sheet at 12 substeps and 4 iterations: 33.6 ms a
  /// step without it and 35.9 with it while the sheet falls onto a ball,
  /// 37.4 and 40.6 once it lies folded on the floor, where it has pairs to
  /// push. The close pairs are only gathered again once a particle has moved
  /// far enough to need it; see `stepCloth`. Turn it off for a sheet that
  /// cannot reach itself, a flag or a curtain, to save that.
  final bool selfCollision;

  /// How close two particles that are not neighbours in the rest shape may
  /// come, in metres; `null`, the default, is the mesh's own mean rest edge
  /// (`ClothMesh.meanRestEdge`).
  ///
  /// **One spacing, because the drawn surface is triangles, not points.**
  /// Two layers held a spacing apart cannot have a triangle of one pass
  /// between the corners of the other; held half a spacing apart they can,
  /// and the fold still shows through. It also means the direct neighbours
  /// along rows and columns, exactly one spacing apart at rest, are left to
  /// the structural constraints, and the diagonals (1.41 spacings) are
  /// pushed only once a quad shears past sixty degrees.
  final double? selfCollisionThickness;

  /// How much of two touching particles' relative slide is taken out each
  /// time they are pushed apart, from 0 (layers slide freely over each
  /// other) to 1 (they move as one).
  ///
  /// **A little, so a fold settles.** Two layers lying on each other are
  /// pushed apart every iteration, and with nothing taking out the motion
  /// along them they keep sliding. Measured on the folded 80×80 sheet, 0.1
  /// brings the fastest particle down to 0.02 m/s after ten seconds where
  /// none leaves it at 0.04; both keep the layers apart equally well.
  final double selfCollisionFriction;
}

/// A uniform wind field, applied per triangle as drag along its own normal.
final class WindSettings {
  /// Still standard air with a drag of 0.3 newtons per square metre per
  /// metre per second, waiting for a velocity.
  const WindSettings({
    this.velocityX = 0,
    this.velocityY = 0,
    this.velocityZ = 0,
    this.drag = 0.3,
    this.airDensity = standardAirDensity,
  });

  /// A copy with the given fields replaced.
  WindSettings copyWith({
    double? velocityX,
    double? velocityY,
    double? velocityZ,
    double? drag,
    double? airDensity,
  }) => WindSettings(
    velocityX: velocityX ?? this.velocityX,
    velocityY: velocityY ?? this.velocityY,
    velocityZ: velocityZ ?? this.velocityZ,
    drag: drag ?? this.drag,
    airDensity: airDensity ?? this.airDensity,
  );

  /// The density of the air the wind is, kg/m³: [standardAirDensity]
  /// unless the world says otherwise (`ClothSettings.inWorld`).
  final double airDensity;

  /// The drag the solver applies, newtons per square metre per metre per
  /// second: [drag], which is quoted in standard air,
  /// scaled by how dense this air is against it. A flat plate's drag is
  /// proportional to the air's density, so the same wind on a mountain top
  /// pushes a sheet less, and on the Moon not at all. Exactly [drag] in
  /// standard air.
  double get effectiveDrag => drag * (airDensity / standardAirDensity);

  /// The air's velocity along X, in metres per second.
  final double velocityX;

  /// The air's velocity along Y, in metres per second.
  final double velocityY;

  /// The air's velocity along Z, in metres per second.
  final double velocityZ;

  /// Newtons per square metre per metre-per-second of air moving through the
  /// cloth along its normal: how much of the wind-relative normal velocity
  /// becomes force, in standard air ([effectiveDrag] is it in this
  /// [airDensity]). Zero turns wind off regardless of
  /// [velocityX]/[velocityY]/[velocityZ].
  ///
  /// A force since 0.7.4. It was applied as a velocity before, which made it
  /// several hundred times stronger than its value and dependent on the
  /// substep count; a scene tuned against that needs a drag in the ones to
  /// tens where it had tenths.
  final double drag;

  /// Whether the wind does nothing: [drag] is zero. A still wind with drag
  /// is not none, since it damps a moving cloth.
  bool get isNone => drag == 0;
}
