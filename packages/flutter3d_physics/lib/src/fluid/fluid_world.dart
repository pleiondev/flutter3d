import 'package:vector_math/vector_math.dart';

import '../rigid_body.dart';
import 'atmosphere.dart';
import 'buoyancy.dart';
import 'gravity_field.dart';
import 'jet.dart';
import 'liquid_body.dart';
import 'particle_fluid.dart';
import 'pipe.dart';
import 'puddle.dart';

/// Liquids in a world: the vessels, the pipes between them, and the streams
/// running from one to another, stepped together at a fixed step.
///
/// **The world's gravity, not its own.** [gravity] is a vector the world
/// shares — pass the one a `Dynamics` uses, and a crate and a glass of water
/// fall the same way; set it to the Moon's and every slosh, spill and stream
/// on it is the Moon's.
///
/// **A fixed step**, like the rest of this package: [advance] takes however
/// long a frame was and runs as many whole steps as fit, carrying the rest
/// over, so a run is the same run on any frame rate.

final class FluidWorld {
  FluidWorld({
    required this.gravity,
    this.step = 1.0 / 240.0,
    this.particleSpacing = 0.002,
    this.floor,
    Atmosphere? atmosphere,
    this.field,
  }) : atmosphere = atmosphere ?? Atmosphere.standard();

  /// Gravity that differs from place to place, when there is some: then
  /// each vessel, drop and parcel of a stream feels [GravityField.at] where
  /// it is, and [gravity] is not read. Null, every one feels [gravity].
  final GravityField? field;

  /// The gravity at [point].
  Vector3 gravityAt(Vector3 point) => field?.at(point) ?? gravity;

  /// The air: what drops and streams fall through and what open liquid
  /// evaporates into. Room air by default, as a bench stands in.
  final Atmosphere atmosphere;

  /// Cubic metres of liquid gone to vapour, from vessels, puddles and
  /// drops: counted, so that every cubic metre poured in is still found.
  double get evaporated =>
      _evaporated + particles.values.fold(0.0, (s, p) => s + p.evaporated);
  double _evaporated = 0.0;

  /// Metres per second squared, shared with whoever else falls.
  final Vector3 gravity;

  /// Seconds per step.
  final double step;

  final List<LiquidBody> bodies = [];

  /// Rigid bodies the liquids push on: buoyed up, slowed, and taking up
  /// room in whatever vessel they are in.
  final List<FloatingBody> floating = [];

  /// Adds [body] to [floating].
  void float(RigidBody body) => floating.add(FloatingBody(body));
  final List<Pipe> pipes = [];

  /// The stream from each vessel's lip, while there is one.
  final Map<LiquidBody, Jet> jets = {};

  /// How far apart the particles drops and splashes become sit at rest.
  final double particleSpacing;

  /// What spilt liquid lands on, if anything: a bench, a floor.
  final List<JetObstacle>? floor;

  /// Liquid out of every vessel and stream, as particles, one fluid per
  /// medium: what streams broke into, what splashed, what lies spilt.
  final Map<String, ParticleFluid> particles = {};

  /// The puddles on each flat [floor]: what lands there lies there, as a
  /// drop or a puddle, not as particles.
  late final List<PuddleSurface> spills = [
    for (final o in floor ?? const <JetObstacle>[])
      if (o is PlaneObstacle) PuddleSurface(o),
  ];

  /// Every cubic metre the world holds: in vessels, in the air, as
  /// particles, in puddles, and gone to vapour as the liquid it was.
  double get volume =>
      bodies.fold(0.0, (s, b) => s + b.volume) +
      jets.values.fold(0.0, (s, j) => s + j.inFlight) +
      particles.values.fold(0.0, (s, p) => s + p.volume) +
      spills.fold(0.0, (s, p) => s + p.volume) +
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
    for (final liquid in bodies) {
      var displaced = 0.0;
      for (final f in floating) {
        displaced += f.push(liquid, dt, gravityAt(f.body.position));
      }
      liquid.displaced = displaced;
    }
    for (final pipe in pipes) {
      pipe.step(dt, gravity: gravityAt(pipe.from.position));
    }
    for (final body in bodies) {
      final here = gravityAt(body.position);
      final spill = body.step(dt, gravity: here);
      final jet = jets[body];
      if (spill.flow > 0.0 || jet != null) {
        final stream = jets.putIfAbsent(body, () => Jet(medium: body.medium));
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
        gravityAt: field?.at,
        obstacles: walls,
        receivers: [...bodies, ...spills],
        air: atmosphere,
      )) {
        particles
            .putIfAbsent(
              drop.medium.name,
              () =>
                  ParticleFluid(medium: drop.medium, spacing: particleSpacing),
            )
            .inject(
              drop.volume,
              drop.position,
              drop.velocity,
              concentrations: drop.concentrations,
            );
      }
      if (!jet.flowing) finished.add(source);
    });
    finished.forEach(jets.remove);
    final everywhere = <JetObstacle>[
      for (final body in bodies) InsideWalls(body),
      for (final body in bodies)
        if (body.wallThickness > 0.0)
          OutsideWalls(body, thickness: body.wallThickness),
      ...?floor,
    ];
    for (final fluid in particles.values) {
      fluid.step(
        dt,
        gravity: field == null || fluid.count == 0
            ? gravity
            : gravityAt(fluid.positions.first),
        gravityAt: field?.at,
        obstacles: everywhere,
        receivers: [...bodies, ...spills],
        air: atmosphere,
      );
    }
    for (final body in bodies) {
      _evaporated += body.evaporate(dt, atmosphere);
    }
    for (final spill in spills) {
      _evaporated += spill.evaporate(dt, atmosphere);
    }
    for (final spill in spills) {
      spill.step(
        dt,
        gravity: gravityAt(spill.surface.normal * spill.surface.offset),
      );
    }
  }
}
