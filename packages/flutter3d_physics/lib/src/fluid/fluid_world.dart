import 'package:flutter3d_matter/flutter3d_matter.dart' show WorldProperties;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show SimulationProfile;
import 'package:vector_math/vector_math.dart';

import '../physics_backend.dart';
import '../rigid_body.dart';
import 'buoyancy.dart';
import 'fluid_air.dart';
import 'fluid_solver.dart';
import 'gravity_field.dart';
import 'jet.dart';
import 'liquid_body.dart';
import 'particle_fluid.dart';
import 'pipe.dart';
import 'puddle.dart';
import 'shape_solves.dart';

/// Liquids in a world: the vessels, the pipes between them, and the streams
/// running from one to another, stepped together at a fixed step.
///
/// **The world's gravity, not its own.** [gravity] is a vector the world
/// shares — pass the one a `Dynamics` uses, and a crate and a glass of water
/// fall the same way; set it to the Moon's and every slosh, spill and stream
/// on it is the Moon's. Where gravity differs from place to place, a
/// [field] says it, and each vessel, drop and parcel of a stream falls by
/// the gravity where it is.
///
/// **The world's air.** [air] is the world's (`WorldProperties`' temperature,
/// pressure, humidity and wind, [FluidAir.of]): drops fall against a
/// sphere's drag at their own size, streams bend in a crosswind, and open
/// liquid evaporates into it — a vessel up its column and out of its mouth,
/// a puddle off its surface, a drop off its sphere. Only the solvent
/// leaves, so a solution grows stronger, and what left is counted in
/// [evaporated].
///
/// **A fixed step**, like the rest of this package: [advance] takes however
/// long a frame was and runs as many whole steps as fit, carrying the rest
/// over, so a run is the same run on any frame rate.
///
/// **On the run's physics.** The parts of it stepped through time — the
/// waves, the streams in the air, the spilt particles, the liquid in the
/// pipes and the bodies floating in it — are [solver]'s, which is the run's
/// backend's unless the world is given another: the core where the run is
/// on it, the Dart reference where it is not
/// ([FluidSolver]). What is where, and how much, is kept here either way,
/// and so are the air and the drops in flight, the same on every backend.
final class FluidWorld {
  /// A world of liquids falling by [gravity], stepped every [step] seconds,
  /// its spilt liquid as particles [particleSpacing] apart landing on
  /// [floor], in the air of [world] (the standard world's when not given)
  /// or [air] said outright.
  FluidWorld({
    required this.gravity,
    this.step = 1.0 / 240.0,
    this.particleSpacing = 0.002,
    this.floor,
    FluidSolver? solver,
    PhysicsBackend backend = const DartPhysics(),
    this.profile = SimulationProfile.deterministic,
    WorldProperties? world,
    FluidAir? air,
    this.field,
    this.shapes = LiquidShapeSolver.immediate,
  }) : solver = solver ?? backend.fluid,
       air = air ?? (world == null ? FluidAir.standard : FluidAir.of(world)) {
    if (profile.isBitExact && !shapes.answersAtOnce) {
      throw ArgumentError.value(
        shapes,
        'shapes',
        'answers later than it is asked, so when a vessel gets its modes '
            'depends on the machine; ${profile.name} must replay to the bit',
      );
    }
  }

  /// Where the vessels' menisci and their surfaces' modes are worked out:
  /// at once by default. A solver that works them out elsewhere keeps a
  /// cross-section not met before from stopping a frame, and is refused
  /// under a bit-exact profile, since when an answer arrives is the
  /// machine's.
  final LiquidShapeSolver shapes;

  /// What the steps promise about their numbers. Under a profile that
  /// allows adaptive steps, what floats is pushed by its own equation
  /// integrated through the step (`FloatingBody.push`), in Dart whatever
  /// the [solver]; the waves, the streams, the pipes and the particles step
  /// as they do under the deterministic profile, which is the default.
  final SimulationProfile profile;

  /// Metres per second squared, shared with whoever else falls.
  final Vector3 gravity;

  /// Gravity that differs from place to place, when there is some: then
  /// each vessel, drop and parcel of a stream feels [GravityField.at] where
  /// it is, and [gravity] is not read. Null, every one feels [gravity].
  final GravityField? field;

  /// The air: what drops and streams fall through and what open liquid
  /// evaporates into.
  final FluidAir air;

  /// Seconds per step.
  final double step;

  /// What steps the waves, the streams, the particles, the pipes and what
  /// floats:
  /// the `backend`'s fluid when the world was made (the Dart reference
  /// unless it was given another), unless it was given a solver.
  final FluidSolver solver;

  final List<LiquidBody> bodies = [];

  /// Rigid bodies the liquids push on: buoyed up, slowed, and taking up
  /// room in whatever vessel they are in.
  final List<FloatingBody> floating = [];

  /// Adds [body] to [floating].
  void float(RigidBody body) => floating.add(FloatingBody(body));
  final List<Pipe> pipes = [];

  /// The stream from each vessel's lip, while there is one.
  final Map<LiquidBody, Jet> jets = {};

  /// How far apart the particles drops and splashes become sit at rest, in
  /// metres.
  final double particleSpacing;

  /// What spilt liquid lands on, if anything: a bench, a floor.
  final List<JetObstacle>? floor;

  /// Flat surfaces where what lands lies as puddles, each one body
  /// ([PuddleSurface]), rather than as particles: a stream, a drop or a
  /// particle that reaches one joins the puddle it lands in.
  final List<PuddleSurface> puddles = [];

  /// Liquid out of every vessel and stream, as particles, one fluid per
  /// medium: what streams broke into, what splashed, what lies spilt.
  final Map<String, ParticleFluid> particles = {};

  /// The gravity at [point], m/s²: [field]'s there, or [gravity].
  Vector3 gravityAt(Vector3 point) => field?.at(point) ?? gravity;

  /// Cubic metres of liquid gone to vapour, from vessels, puddles and
  /// drops: counted, so that every cubic metre poured in is still found.
  double get evaporated =>
      _evaporated + particles.values.fold(0.0, (s, p) => s + p.evaporated);
  double _evaporated = 0.0;

  /// Every cubic metre the world holds: in vessels, in the air, as
  /// particles and drops, in puddles, what was particles until
  /// `ParticleFluid.retire` took it out to lie where it settled, and what
  /// has gone to vapour as the liquid it was.
  double get volume =>
      bodies.fold(0.0, (s, b) => s + b.volume) +
      jets.values.fold(0.0, (s, j) => s + j.inFlight) +
      particles.values.fold(0.0, (s, p) => s + p.volume + p.retired) +
      puddles.fold(0.0, (s, p) => s + p.volume) +
      evaporated;

  double _carried = 0.0;
  int _ran = 0;

  /// Seconds handed to [advance] so far, the part not yet stepped included:
  /// the time of whatever the caller places for the frame it is on, as
  /// `LiquidBody.place`'s `time` wants it. Bodies added at the start share
  /// this clock.
  double get time => _ran * step + _carried;

  /// Runs as many whole steps as [elapsed] seconds hold, plus what was left
  /// over from the last call; returns how many it ran.
  int advance(double elapsed) {
    _carried += elapsed;
    var ran = 0;
    while (_carried >= step) {
      _carried -= step;
      _stepOnce(step);
      ran++;
      _ran++;
    }
    return ran;
  }

  void _stepOnce(double dt) {
    for (final body in bodies) {
      if (!identical(body.shapes, shapes)) body.shapes = shapes;
    }
    final receivers = <JetReceiver>[...bodies, ...puddles];
    for (final liquid in bodies) {
      var displaced = 0.0;
      for (final f in floating) {
        displaced += f.push(
          liquid,
          dt,
          gravityAt(f.body.position),
          solver: solver,
          profile: profile,
        );
      }
      liquid.displaced = displaced;
    }
    for (final pipe in pipes) {
      pipe.step(dt, gravity: gravityAt(pipe.from.position), solver: solver);
    }
    for (final body in bodies) {
      final here = gravityAt(body.position);
      final spill = body.step(dt, gravity: here, solver: solver);
      final jet = jets[body];
      if (spill.flow > 0.0 || jet != null) {
        final stream = jets.putIfAbsent(
          body,
          () => Jet(medium: body.medium, solver: solver),
        );
        final across = here.cross(spill.velocity);
        stream.emit(
          flow: spill.flow,
          dt: dt,
          point: spill.point,
          velocity: spill.velocity,
          width: spill.width,
          across: across.length2 > 0.0 ? across : Vector3(1, 0, 0),
          medium: spill.medium,
          concentrations: spill.concentrations,
        );
      }
    }
    final finished = <LiquidBody>[];
    jets.forEach((source, jet) {
      // Every glass's inside but the one it is leaving, which it is
      // already over the edge of; every outside, its own included, which
      // a slow pour runs down.
      final walls = <JetObstacle>[
        for (final body in bodies)
          if (!identical(body, source)) InsideWalls(body),
        for (final body in bodies)
          if (body.wallThickness > 0.0)
            OutsideWalls(body, thickness: body.wallThickness),
      ];
      for (final drop in jet.step(
        dt,
        gravity: gravityAt(source.position),
        obstacles: walls,
        receivers: receivers,
        air: air,
      )) {
        particles
            .putIfAbsent(
              drop.medium.name,
              () => ParticleFluid(
                medium: drop.medium,
                spacing: particleSpacing,
                solver: solver,
              ),
            )
            .inject(
              drop.volume,
              drop.position,
              drop.velocity,
              concentrations: drop.concentrations,
            );
      }
      if (!jet.isFlowing) finished.add(source);
    });
    finished.forEach(jets.remove);
    final everywhere = <JetObstacle>[
      for (final body in bodies) InsideWalls(body),
      for (final body in bodies)
        if (body.wallThickness > 0.0)
          OutsideWalls(body, thickness: body.wallThickness),
      ...?floor,
    ];
    final field = this.field;
    for (final fluid in particles.values) {
      final positions = fluid.positions;
      fluid.step(
        dt,
        gravity: field == null || positions.isEmpty
            ? gravity
            : field.at(positions.first),
        obstacles: everywhere,
        receivers: receivers,
        air: air,
        gravityAt: field?.at,
      );
    }
    for (final body in bodies) {
      _evaporated += body.evaporate(dt, air);
    }
    for (final surface in puddles) {
      _evaporated += surface.evaporate(dt, air);
      surface.step(
        dt,
        gravity: gravityAt(surface.surface.normal * surface.surface.offset),
      );
    }
  }
}
