/// The one place a run is assembled.
///
/// **One place, and the structure rule `each assembly has one home per
/// application` is what keeps it one.** A test that built its own hillside and
/// its own crowd would agree with every bug this file has; calling [stage] is
/// how a test gets the game rather than a likeness of it.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_strategy/bridge.dart';
import 'package:flutter3d_game_strategy/flutter3d_game_strategy.dart';
import 'package:vector_math/vector_math.dart';

/// Everything a frame needs.
final class Staged {
  /// Holds the halves together.
  const Staged({
    required this.match,
    required this.visuals,
    required this.camera,
    required this.mine,
  });

  /// The sides, the ground under them, and the finishing line.
  final Match match;

  /// What draws them.
  final StrategyVisuals visuals;

  /// The view over the map.
  final MapCamera camera;

  /// The units the person holding the mouse commands.
  ///
  /// The other side has a [Bot] on it, and **the two are given orders through
  /// the same handles** — a [Squad] here, a policy there, both writing to
  /// `Unit.order` and `Unit.job`. That symmetry is the whole reason the bot was
  /// worth writing: a mirror is a load test, a replay test and an opponent at
  /// once, and none of the three works if the bot has a private door.
  final List<Unit> mine;

  /// The crowd and the ground it walks on.
  StrategySimulation get simulation => match.simulation;
}

/// Ground with two ridges and a valley between them.
///
/// Built from a formula rather than loaded, because what this demo is showing
/// is a crowd crossing terrain and a formula is a hillside anybody can read.
/// Deterministic, so two runs of the app are the same map.
Heightfield hills({int samples = 81, double cellSize = 2.0}) {
  final heights = Float32List(samples * samples);
  for (var row = 0; row < samples; row++) {
    for (var column = 0; column < samples; column++) {
      final double x = column / (samples - 1);
      final double z = row / (samples - 1);
      // Amplitude chosen by looking at it: ten metres over a hundred and sixty
      // reads as one tilted plane under a camera fifty degrees off the
      // horizon, because nothing in the picture is nearer than anything else
      // by enough to see. These ridges are steep enough to hide a crowd behind
      // and still gentle enough to walk over — the bake refuses forty degrees,
      // and the steepest here is about twenty-five.
      heights[row * samples + column] =
          math.sin(x * math.pi * 2.0) * 9.0 +
          math.sin(z * math.pi * 3.0 + 1.0) * 6.0 +
          math.sin((x + z) * math.pi * 5.0) * 1.5 +
          14.0;
    }
  }
  return Heightfield(
    columns: samples,
    rows: samples,
    cellSize: cellSize,
    heights: heights,
  );
}

/// Builds a run: a camp per side on one hillside, a bot on every camp but the
/// near one, and the view over that.
///
/// [workers] is what each side starts with; all of them grow from there,
/// because each has a hall that turns a stockpile into more of them. The seams
/// are finite, so the growth is too — which is also what makes the match end.
///
/// [sides] is how many camps get staged, and side nought is always the one the
/// mouse commands; the rest get a policy each. Two is what the demo shows, but
/// the number is a parameter rather than a pair of hand-written corners,
/// because the simulation stopped assuming two and this is the one place that
/// would have gone on doing it.
Staged stage({
  required GraphicsDevice device,
  int workers = 60,
  int sides = 2,
}) {
  final ground = hills();
  final simulation = StrategySimulation(ground: ground, sides: sides);

  final mine = <Unit>[];
  final bots = <Bot>[];
  for (var side = 0; side < sides; side++) {
    // Spread along the hillside's diagonal, from its near corner to its far
    // one. Not mirrored: the ground is a sum of sines and the camps stand on
    // different parts of it, which is fair enough for a demo and would not be
    // for a test — the tests that care use flat ground and a translation.
    final double along = sides == 1 ? 0.0 : side / (sides - 1);
    final Vector3 home = Vector3(36.0 + along * 88.0, 0.0, 36.0 + along * 88.0);
    // The seam sits thirty-six metres from the hall towards the middle of the
    // map, so that no camp is asked to dig off the edge of the ground.
    final Vector3 seam = Vector3(
      home.x,
      0.0,
      home.z + (home.z < ground.depth / 2.0 ? 36.0 : -36.0),
    );

    final base = simulation.build(
      Building(
        centre: home,
        width: 12.0,
        depth: 10.0,
        name: side == 0 ? 'hall' : 'their hall',
        side: side,
      ),
    );
    final deposit = simulation.addResource(
      ResourceNode(at: seam, amount: 1600.0),
    );
    simulation.addProducer(Producer(building: base));

    // A block beside the hall, spaced so nobody starts inside anybody.
    const int across = 10;
    for (var i = 0; i < workers; i++) {
      final unit = simulation.add(
        Unit(
          position: Vector3(
            home.x - 12.0 + (i % across) * 1.1,
            0.0,
            home.z + 8.0 + (i ~/ across) * 1.1,
          ),
          side: side,
        ),
      );
      // Both sides open at work rather than standing about. The far side's bot
      // would have sent its own out within a second anyway; the near side's
      // opening orders are the player's, and clicking the ground cancels them,
      // which is the same exchange either way round.
      unit.job = HarvestJob(node: deposit, dropOff: base);
      if (side == 0) mine.add(unit);
    }

    if (side != 0) bots.add(Bot(side: side, base: base));
  }

  // Drawn through side nought's eyes rather than the simulation's: the far
  // camp is dark until somebody of ours goes and looks at it, and what is drawn
  // of the crowd is only what this side can see.
  final visuals = StrategyVisuals(
    simulation: simulation,
    device: device,
    capacity: workers * sides + 256,
    viewer: 0,
  );

  // Pointed at the near camp rather than at the middle of the map. The default
  // is the centre of the ground, and the camp stands forty metres away — which
  // drew a picture of empty hillside with the game just out of frame.
  final camera = MapCamera(ground: ground)
    ..pan(36.0 - ground.width / 2.0, 44.0 - ground.depth / 2.0);

  return Staged(
    match: Match(
      simulation: simulation,
      bots: bots,
      goal: const MatchGoal(delivered: 1200.0),
    ),
    visuals: visuals,
    camera: camera,
    mine: mine,
  );
}
