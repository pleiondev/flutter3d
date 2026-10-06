import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import '../physics_backend.dart';
import 'buoyancy.dart';
import 'fluid_medium.dart';
import 'free_surface.dart';
import 'jet.dart';
import 'particle_fluid.dart';
import 'pipe.dart';

/// The parts of a `FluidWorld` that are stepped through time, from the run's
/// physics: `PhysicsBackend.current.fluid`, the core where the run is on it
/// and [DartFluid] where it is on the reference.
///
/// **Five solvers, and nothing else.** What a world steps is the particles
/// spilt liquid becomes ([ParticleFluid]: position-based fluids against the
/// walls), the parcels of a stream in the air ([Jet]: falling, running along
/// walls, clinging, growing the ripples that part it), the waves on each
/// vessel's surface ([FreeSurface]: every mode a damped oscillator), the
/// liquid in each pipe between vessels ([Pipe]: a column driven by the
/// pressure across it and held back by friction), and the bodies floating
/// in it ([FloatingBody]: lifted by what they displace and slowed by
/// drag). Those are what a backend of its own does. What is left is the
/// same on every backend and stays in Dart: how much liquid is where, what
/// is dissolved in it and which layer it is in, all exact bookkeeping; the
/// shapes the surface can take, where its plane stands and how much of a
/// body is under it, which are geometry, not stepped; and the hand-off
/// between the pieces — a drop caught by a vessel, liquid over a lip or
/// through a pipe — which asks a `LiquidBody` that holds those books.
///
/// **Each call moves its data in place.** The pieces keep their own state
/// as they always have, hand it to a solver as one of the records below for
/// the step, and read it back, so a [ParticleFluid] read between steps is
/// the same object on either backend.
///
/// The two backends are close, not equal: the core works in single
/// precision and sums neighbours in another order, so a pour lands the same
/// liquid in the same glass by a slightly different path; each agrees with
/// itself from run to run.
abstract interface class FluidSolver {
  /// Moves [motion]'s particles on by its substeps.
  void moveParticles(ParticleMotion motion);

  /// Flies [flight]'s parcels on by one step.
  void flyParcels(ParcelFlight flight);

  /// Rings [ringing]'s modes on by one step.
  void ringModes(ModeRinging ringing);

  /// Drives [flow]'s pipes on by one step.
  void flowPipes(PipeFlow flow);

  /// Pushes [push]'s floating bodies for one step.
  void pushBodies(FloatPush push);
}

/// A backend with a fluid of its own: what [PhysicsBackendFluid.fluid] asks
/// a backend for before it falls back to the reference.
///
/// **An interface beside [PhysicsBackend], not a member of it**, as cloth's
/// `ClothPhysics` is: a backend a test writes to count what it was given
/// has no fluid to offer, and should not have to say so.
abstract interface class FluidPhysics {
  /// This backend's fluid solver.
  FluidSolver get fluid;
}

/// Fluid from whatever backend the run is on.
extension PhysicsBackendFluid on PhysicsBackend {
  /// This backend's own fluid solver if it has one ([FluidPhysics]), the
  /// reference ([DartFluid]) if not.
  FluidSolver get fluid => switch (this) {
    final FluidPhysics own => own.fluid,
    _ => const DartFluid(),
  };
}

/// The reference: each solver in Dart, in double precision, as the pieces
/// stepped themselves before there was a core to step them.
final class DartFluid implements FluidSolver {
  const DartFluid();

  @override
  void moveParticles(ParticleMotion motion) => moveParticlesInDart(motion);

  @override
  void flyParcels(ParcelFlight flight) => flyParcelsInDart(flight);

  @override
  void ringModes(ModeRinging ringing) => ringModesInDart(ringing);

  @override
  void flowPipes(PipeFlow flow) => flowPipesInDart(flow);

  @override
  void pushBodies(FloatPush push) => pushBodiesInDart(push);
}

/// Particles of one liquid for [FluidSolver.moveParticles]: [substeps]
/// substeps of [dt] each, every one of them the [ParticleFluid] solve —
/// pushed out of the walls, pre-stabilised, gravity, cohesion and curvature
/// on the velocities, a predicted move in pieces against the walls, the
/// density held, and XSPH's viscosity.
///
/// The constants the kernels are normalised with are worked out once, by
/// the [ParticleFluid] the particles are, and handed over with them, so
/// every backend divides by the same numbers.
final class ParticleMotion {
  ParticleMotion({
    required this.state,
    required this.medium,
    required this.spacing,
    required this.iterations,
    required this.substeps,
    required this.dt,
    required this.gravity,
    required this.cohesion,
    required this.latticeSum,
    required this.restStiffness,
    this.walls = const <JetObstacle>[],
  });

  /// Six doubles a particle — position xyz, velocity xyz — moved in place.
  final Float64List state;

  /// The liquid, for its density and kinematic viscosity.
  final FluidMedium medium;

  /// The particles' spacing at rest; the kernel reaches twice that.
  final double spacing;

  /// Density passes per substep.
  final int iterations;

  /// How many substeps, and how long each is.
  final int substeps;
  final double dt;

  final Vector3 gravity;

  /// Akinci's cohesion coefficient, for a work of cohesion of 2σ.
  final double cohesion;

  /// The density kernel summed over the rest lattice: what a density
  /// estimate is divided by.
  final double latticeSum;

  /// Σ|∇C|² over the rest lattice: what the artificial pressure is a share
  /// of a constraint's worth over.
  final double restStiffness;

  /// The walls these particles could reach this step.
  final List<JetObstacle> walls;

  int get count => state.length ~/ particleFloats;

  /// Doubles a particle takes in [state].
  static const int particleFloats = 6;
}

/// A stream's parcels for [FluidSolver.flyParcels]: each falls for [dt]
/// under [gravity], in pieces no longer than its radius against [walls],
/// running along what it meets; held to a wall it has come off while it is
/// slower than [medium]'s cling speed for its thickness; its ripples grown
/// while it is in the air. Where it lands and whether it parts is the
/// [Jet]'s to say, after.
final class ParcelFlight {
  ParcelFlight({
    required this.parcels,
    required this.dt,
    required this.gravity,
    required this.medium,
    this.walls = const <JetObstacle>[],
  });

  /// [parcelFloats] doubles a parcel, laid out as the offsets below say;
  /// the position, velocity, previous position, age, growth and whether it
  /// is on a wall are moved in place.
  final Float64List parcels;

  final double dt;
  final Vector3 gravity;

  /// The stream's liquid, which the cling speed answers for.
  final FluidMedium medium;

  final List<JetObstacle> walls;

  int get count => parcels.length ~/ parcelFloats;

  /// Doubles a parcel takes in [parcels].
  static const int parcelFloats = 17;

  /// Where each part of a parcel is in its record: position xyz, velocity
  /// xyz, the position it started the step at xyz (written), its volume,
  /// the step it left the lip in, its age, how far its ripples have grown,
  /// one when it is on a wall and nought when not, and its own liquid's
  /// density, surface tension and viscosity.
  static const int position = 0;
  static const int velocity = 3;
  static const int previous = 6;
  static const int volume = 9;
  static const int emittedIn = 10;
  static const int age = 11;
  static const int growth = 12;
  static const int onWall = 13;
  static const int density = 14;
  static const int tension = 15;
  static const int viscosity = 16;
}

/// A surface's modes for [FluidSolver.ringModes]: each the damped
/// oscillator it is, stepped exactly for [dt] under gravity [g] over a
/// liquid [depth] deep, then held under Stokes' limit.
///
/// The arrays are the [FreeSurface]'s own: [amplitude] and [rate] are moved
/// in place, and [omega2] and [decay] are written with what each mode rang
/// at, which the force on the vessel reads.
final class ModeRinging {
  ModeRinging({
    required this.k2,
    required this.norms,
    required this.amplitude,
    required this.rate,
    required this.omega2,
    required this.decay,
    required this.dt,
    required this.g,
    required this.depth,
    required this.area,
    required this.medium,
  });

  /// Each mode's wavenumber squared, lowest first.
  final Float64List k2;

  /// The most each mode stands anywhere on the surface, per unit amplitude.
  final Float64List norms;

  final Float64List amplitude;
  final Float64List rate;
  final Float64List omega2;
  final Float64List decay;

  final double dt;
  final double g;
  final double depth;

  /// The surface's area, for the radius of the round vessel it damps as.
  final double area;

  /// The liquid at the surface, for its viscosity and surface tension.
  final FluidMedium medium;

  int get count => k2.length;
}

/// Pipes for [FluidSolver.flowPipes]: the liquid in each, a column of it,
/// accelerated by the pressure across its ends over its inertance — its own
/// length over its section, and the liquid standing over each end over that
/// vessel's surface — and held back, implicitly, by Hagen–Poiseuille's
/// friction and the losses where it enters and leaves. Air cannot be
/// pushed through: an end whose surface is below it gives nothing.
///
/// The pressures are the [Pipe]'s to work out, layer by layer and less the
/// pull of each meniscus; what the new flow carries through is its to move.
final class PipeFlow {
  PipeFlow({required this.pipes, required this.dt});

  /// [pipeFloats] doubles a pipe, laid out as the offsets below say; the
  /// flow is moved in place.
  final Float64List pipes;

  final double dt;

  int get count => pipes.length ~/ pipeFloats;

  /// Doubles a pipe takes in [pipes].
  static const int pipeFloats = 11;

  /// Where each part of a pipe is in its record: the flow, cubic metres a
  /// second from its first vessel to its second; the pressure at its first
  /// end less the pressure at its second; how deep each end is under its
  /// vessel's surface; each vessel's surface area; the pipe's bore and
  /// length; the liquid's density and viscosity; and the loss where it
  /// enters and leaves, in velocity heads.
  static const int flow = 0;
  static const int drive = 1;
  static const int headFrom = 2;
  static const int headTo = 3;
  static const int areaFrom = 4;
  static const int areaTo = 5;
  static const int radius = 6;
  static const int length = 7;
  static const int density = 8;
  static const int viscosity = 9;
  static const int minorLoss = 10;
}

/// Floating bodies for [FluidSolver.pushBodies]: each push, in order, lifts
/// a body by the weight of the liquid it displaces for [dt] and slows it
/// by the drag of the part of it under, implicitly, with White's sphere
/// coefficient at the Reynolds number of the sphere of its frontal area.
///
/// How much of a body is under is the [FloatingBody]'s to work out: it is
/// geometry, a cap or a cut, not stepped.
final class FloatPush {
  FloatPush({
    required this.bodies,
    required this.pushes,
    required this.gravity,
    required this.dt,
  });

  /// [bodyFloats] doubles a body: its velocity xyz, moved in place, and its
  /// inverse mass.
  final Float64List bodies;

  /// [pushFloats] doubles a push: which body, its shape's kind
  /// ([sphere], [box], [capsule], or [other] for one with no inside), the
  /// shape's sizes — a radius; half extents; a radius and half height —
  /// the volume of it under, and the liquid's density and viscosity.
  final Float64List pushes;

  final Vector3 gravity;
  final double dt;

  int get count => pushes.length ~/ pushFloats;

  static const int bodyFloats = 4;
  static const int pushFloats = 8;

  static const int sphere = 0;
  static const int box = 1;
  static const int capsule = 2;
  static const int other = 3;
}
