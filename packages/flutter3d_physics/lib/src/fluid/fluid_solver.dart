import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'buoyancy.dart';
import 'fluid_medium.dart';
import 'free_surface.dart';
import 'jet.dart';
import 'particle_fluid.dart';
import 'pipe.dart';

/// The parts of a `FluidWorld` that are stepped through time, from the run's
/// physics: a backend's `fluid`, the core where the run is on it
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
///
/// **Extended outside this package: an `abstract base class` with defaults**
/// (decision 5 of `tasks/1.0-api-review.md`), so a member added in a minor
/// arrives with a default body and every implementation keeps compiling.
///
/// **Every member defaults to the Dart reference**, so a solver that does one
/// thing on its own hardware overrides that one and inherits the rest.
abstract base class FluidSolver {
  /// A solver that does every step in Dart until a subclass overrides it.
  const FluidSolver();

  /// Moves [motion]'s particles on by its substeps.
  void moveParticles(ParticleMotion motion) => moveParticlesInDart(motion);

  /// Flies [flight]'s parcels on by one step.
  void flyParcels(ParcelFlight flight) => flyParcelsInDart(flight);

  /// Rings [ringing]'s modes on by one step.
  void ringModes(ModeRinging ringing) => ringModesInDart(ringing);

  /// Drives [flow]'s pipes on by one step.
  void flowPipes(PipeFlow flow) => flowPipesInDart(flow);

  /// Pushes [push]'s floating bodies for one step.
  void pushBodies(FloatPush push) => pushBodiesInDart(push);
}

/// The reference: each solver in Dart, in double precision, as the pieces
/// stepped themselves before there was a core to step them.
final class DartFluid extends FluidSolver {
  /// The reference; it holds no state, so one constant serves every world.
  const DartFluid();
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
  /// The particles in [state] and everything their solve reads; no walls
  /// unless given. Copies nothing: [state] is moved in place.
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

  /// The particles' spacing at rest, in metres; the kernel reaches twice
  /// that.
  final double spacing;

  /// Density passes per substep.
  final int iterations;

  /// How many substeps, and how long each is.
  final int substeps;

  /// How long each substep is, in seconds.
  final double dt;

  /// The gravity the particles feel, in metres per second squared, in the
  /// world.
  final Vector3 gravity;

  /// Akinci's cohesion coefficient, for a work of cohesion of 2σ: in newton
  /// cubic metres per kilogram squared, as a force over two particles'
  /// masses and the cohesion spline (per cubic metre).
  final double cohesion;

  /// The density kernel summed over the rest lattice: what a density
  /// estimate is divided by. Per cubic metre, as the poly6 kernel is.
  final double latticeSum;

  /// Σ|∇C|² over the rest lattice: what the artificial pressure is a share
  /// of a constraint's worth over.
  final double restStiffness;

  /// The walls these particles could reach this step.
  final List<JetObstacle> walls;

  /// How many particles [state] holds.
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
  /// The parcels in [parcels] and what their flight reads; no walls unless
  /// given. Copies nothing: [parcels] is moved in place.
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

  /// How long the parcels fly for, in seconds.
  final double dt;

  /// The gravity the parcels fall under, in metres per second squared, in
  /// the world.
  final Vector3 gravity;

  /// The stream's liquid, which the cling speed answers for.
  final FluidMedium medium;

  /// The walls the parcels could reach this step, which they run along.
  final List<JetObstacle> walls;

  /// How many parcels [parcels] holds.
  int get count => parcels.length ~/ parcelFloats;

  /// Doubles a parcel takes in [parcels].
  static const int parcelFloats = 17;

  /// Where each part of a parcel is in its record: position xyz, velocity
  /// xyz, the position it started the step at xyz (written), its volume,
  /// the step it left the lip in, its age, how far its ripples have grown,
  /// one when it is on a wall and nought when not, and its own liquid's
  /// density, surface tension and viscosity.
  static const int position = 0;

  /// Offset of the velocity xyz, in metres per second.
  static const int velocity = 3;

  /// Offset of the position xyz the parcel started the step at, in metres;
  /// written by the flight.
  static const int previous = 6;

  /// Offset of the parcel's volume, in cubic metres.
  static const int volume = 9;

  /// Offset of the length of the step the parcel left the lip in, in
  /// seconds: its volume over this and its speed is its section.
  static const int emittedIn = 10;

  /// Offset of the parcel's age, in seconds since it left the lip.
  static const int age = 11;

  /// Offset of how far its ripples have grown, in e-foldings.
  static const int growth = 12;

  /// Offset of the wall flag: one while the parcel is on a wall, nought
  /// when not.
  static const int onWall = 13;

  /// Offset of its liquid's density, in kilograms per cubic metre.
  static const int density = 14;

  /// Offset of its liquid's surface tension, in newtons per metre.
  static const int tension = 15;

  /// Offset of its liquid's dynamic viscosity, in pascal seconds.
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
  /// The [FreeSurface]'s mode arrays and what ringing them reads. Copies
  /// nothing: the arrays are moved and written in place.
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

  /// Each mode's amplitude, the surface's height projected on its shape;
  /// moved in place.
  final Float64List amplitude;

  /// How fast each [amplitude] changes, per second; moved in place.
  final Float64List rate;

  /// Each mode's angular frequency squared, in radians squared per second
  /// squared, as it rang this step; written.
  final Float64List omega2;

  /// Each mode's damping rate, per second, as it rang this step; written.
  final Float64List decay;

  /// How long to ring the modes for, in seconds.
  final double dt;

  /// Gravity's pull, in metres per second squared.
  final double g;

  /// How deep the liquid under the surface is, in metres.
  final double depth;

  /// The surface's area, for the radius of the round vessel it damps as.
  final double area;

  /// The liquid at the surface, for its viscosity and surface tension.
  final FluidMedium medium;

  /// How many modes ring.
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
  /// The pipes in [pipes], run for [dt] seconds. Copies nothing: each
  /// flow is moved in place.
  PipeFlow({required this.pipes, required this.dt});

  /// [pipeFloats] doubles a pipe, laid out as the offsets below say; the
  /// flow is moved in place.
  final Float64List pipes;

  /// How long the flow runs for, in seconds.
  final double dt;

  /// How many pipes [pipes] holds.
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

  /// Offset of the pressure at the first end less the second's, in
  /// pascals.
  static const int drive = 1;

  /// Offset of the first end's depth under its vessel's surface, in metres.
  static const int headFrom = 2;

  /// Offset of the second end's depth under its vessel's surface, in
  /// metres.
  static const int headTo = 3;

  /// Offset of the first vessel's surface area, in square metres.
  static const int areaFrom = 4;

  /// Offset of the second vessel's surface area, in square metres.
  static const int areaTo = 5;

  /// Offset of the pipe's bore radius, in metres.
  static const int radius = 6;

  /// Offset of the pipe's length, in metres.
  static const int length = 7;

  /// Offset of the liquid's density, in kilograms per cubic metre.
  static const int density = 8;

  /// Offset of the liquid's dynamic viscosity, in pascal seconds.
  static const int viscosity = 9;

  /// Offset of the entry and exit loss, a unitless count of velocity heads.
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
  /// The bodies in [bodies] and the [pushes] on them, for [dt] seconds
  /// under [gravity]. Copies nothing: velocities are moved in place.
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

  /// The gravity the liquid feels, in metres per second squared, in the
  /// world: the lift is against it.
  final Vector3 gravity;

  /// How long the pushes act for, in seconds.
  final double dt;

  /// How many pushes [pushes] holds.
  int get count => pushes.length ~/ pushFloats;

  /// Doubles a body takes in [bodies].
  static const int bodyFloats = 4;

  /// Doubles a push takes in [pushes].
  static const int pushFloats = 8;

  /// The shape kind of a sphere: its one size is the radius.
  static const int sphere = 0;

  /// The shape kind of a box: its sizes are the half extents.
  static const int box = 1;

  /// The shape kind of a capsule: its sizes are the radius and the half
  /// height.
  static const int capsule = 2;

  /// The shape kind of any other collider: it has no sizes and no frontal
  /// area, so it is lifted by the volume under but not dragged.
  static const int other = 3;
}
