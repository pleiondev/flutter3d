/// The one place a run is assembled.
///
/// **One place, and the structure rule `each assembly has one home per
/// application` is what keeps it one.** A test that built its own hillside and
/// its own crowd would agree with every bug this file has; calling [stage] is
/// how a test gets the game rather than a likeness of it.
///
/// **Two halves, and the seam between them is a [GraphicsDevice].** The match
/// comes out of the document — see `level_document.dart`, which needs nothing
/// that draws — and this file puts a picture and a camera over it. That split
/// is not tidiness: a simulation test had to open a software rasteriser to
/// reach the game's own start, and a match played to its end against a policy
/// draws thousands of frames nobody ever looks at.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_strategy/bridge.dart';
import 'package:flutter3d_game_strategy/flutter3d_game_strategy.dart';
import 'package:vector_math/vector_math.dart';

import 'level_document.dart';

/// Everything a frame needs.
final class Staged {
  /// Holds the halves together.
  const Staged({
    required this.start,
    required this.visuals,
    required this.camera,
  });

  /// The match, and the side the mouse commands.
  final StrategyStart start;

  /// What draws them.
  final StrategyVisuals visuals;

  /// The view over the map.
  final MapCamera camera;

  /// The sides, the ground under them, and the finishing line.
  Match get match => start.match;

  /// The crowd and the ground it walks on.
  StrategySimulation get simulation => start.simulation;

  /// The units the person holding the mouse commands.
  ///
  /// The other side has a [Bot] on it, and **the two are given orders through
  /// the same handles** — a [Squad] here, a policy there, both writing to
  /// `Unit.order` and `Unit.job`. That symmetry is the whole reason the bot was
  /// worth writing: a mirror is a load test, a replay test and an opponent at
  /// once, and none of the three works if the bot has a private door.
  List<Unit> get mine => start.mine;
}

/// Builds a run from [map] and puts a picture over it.
///
/// [workers] overrides how many stand in each block; the map's own count is
/// what the game plays, and a smaller crowd is for a test drawing its frames in
/// software.
Staged stage({
  required GraphicsDevice device,
  required StrategyMap map,
  int? workers,
}) {
  final StrategyStart start = openMatch(map, workers: workers);

  // Drawn through side nought's eyes rather than the simulation's: the far
  // camp is dark until somebody of ours goes and looks at it, and what is drawn
  // of the crowd is only what this side can see.
  //
  // Room for the crowd the map starts with and for the ones its halls will
  // make, which is what the seams can pay for and no more.
  final visuals = StrategyVisuals(
    simulation: start.simulation,
    device: device,
    capacity: start.simulation.units.length + 256,
    viewer: 0,
  );

  final Heightfield ground = map.ground;
  final Vector3 opening = _opening(map.level);
  final camera = MapCamera(ground: ground)
    ..pan(opening.x - ground.width / 2.0, opening.z - ground.depth / 2.0);

  return Staged(start: start, visuals: visuals, camera: camera);
}

/// Where the view opens, in world space.
///
/// Over side nought's hall and as far down the map as its crowd, rather than at
/// the middle of the ground — which is what a map camera aims at by default,
/// and which drew a picture of empty hillside with the game just out of frame.
Vector3 _opening(Level level) {
  final EntityDef hall = level
      .ofType(StrategyEntities.camp)
      .firstWhere((EntityDef it) => (it.integer('side') ?? 0) == 0);
  final Iterable<EntityDef> crowd = level
      .ofType(StrategyEntities.worker)
      .where((EntityDef it) => (it.integer('side') ?? 0) == 0);
  return Vector3(
    hall.position.x,
    0.0,
    crowd.isEmpty ? hall.position.z : crowd.first.position.z,
  );
}
