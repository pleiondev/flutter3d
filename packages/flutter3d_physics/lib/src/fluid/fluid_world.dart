import 'package:vector_math/vector_math.dart';

import 'jet.dart';
import 'liquid_body.dart';
import 'pipe.dart';

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
  FluidWorld({required this.gravity, this.step = 1.0 / 240.0});

  /// Metres per second squared, shared with whoever else falls.
  final Vector3 gravity;

  /// Seconds per step.
  final double step;

  final List<LiquidBody> bodies = [];
  final List<Pipe> pipes = [];

  /// The stream from each vessel's lip, while there is one.
  final Map<LiquidBody, Jet> jets = {};

  /// The drops streams have broken into since they were last taken.
  final List<JetDrop> drops = [];

  double _carried = 0.0;

  /// Runs as many whole steps as [elapsed] seconds hold, plus what was left
  /// over from the last call; returns how many it ran.
  int advance(double elapsed) {
    _carried += elapsed;
    var ran = 0;
    while (_carried >= step) {
      _carried -= step;
      _stepOnce(step);
      ran++;
    }
    return ran;
  }

  void _stepOnce(double dt) {
    for (final pipe in pipes) {
      pipe.step(dt, gravity: gravity);
    }
    for (final body in bodies) {
      final spill = body.step(dt, gravity: gravity);
      final jet = jets[body];
      if (spill.flow > 0.0 || jet != null) {
        final stream = jets.putIfAbsent(body, () => Jet(medium: body.medium));
        final across = gravity.cross(spill.velocity);
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
      drops.addAll(
        jet.step(dt, gravity: gravity, obstacles: walls, receivers: bodies),
      );
      if (!jet.flowing) finished.add(source);
    });
    finished.forEach(jets.remove);
  }
}
