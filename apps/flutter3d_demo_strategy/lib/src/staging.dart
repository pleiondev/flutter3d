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

import 'package:flutter/foundation.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_game_strategy/bridge.dart';
import 'package:flutter3d_game_strategy/flutter3d_game_strategy.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import 'level_document.dart';

/// The side the person holding the mouse plays.
///
/// A named constant rather than a nought written out at each use, because it is
/// written in three places that have to agree — what the fog is drawn through,
/// what the camera opens over, and whose units a click may pick out — and a
/// disagreement between any two of them is a screen showing one side's map
/// while commanding another's.
const int viewerSide = 0;

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

  /// The crowd side [viewerSide] opened the match with.
  ///
  /// **The opening crowd, and nothing more than that.** It was once also what a
  /// click ordered about, which made it wrong twice over: a hall builds workers
  /// while the match runs and none of them are in here, and nothing takes a
  /// unit out of it. Who is under orders is a question about the screen rather
  /// than about the document, and `CommandPost` in `command.dart` is what holds
  /// the answer. What this is still good for is a test that wants the crowd the
  /// map staged.
  List<Unit> get mine => start.mine;
}

/// Builds a run from [map] and puts a picture over it.
///
/// [workers] overrides how many stand in each block; the map's own count is
/// what the game plays, and a smaller crowd is for a test drawing its frames in
/// software.
Future<Staged> stage({
  required GraphicsDevice device,
  required StrategyMap map,
  int? workers,
}) async {
  final StrategyStart start = openMatch(map, workers: workers);
  final _RealModels models = await _RealModels.load(device);

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
    viewer: viewerSide,
    unitMesh: models.worker,
    buildingMesh: models.hall,
    buildingMeshSize: models.hallSize,
  );

  final Heightfield ground = map.ground;
  final Vector3 opening = _opening(map.level);
  final camera = MapCamera(ground: ground)
    ..pan(opening.x - ground.width / 2.0, opening.z - ground.depth / 2.0);

  return Staged(start: start, visuals: visuals, camera: camera);
}

/// `worker.glb` and `hall.glb`, loaded once and handed to [StrategyVisuals]
/// in place of its own [CuboidShape] defaults.
///
/// **A model missing is a demo that still runs**, the same choice the racing
/// game's own roadside makes for its buildings: [StrategyVisuals] treats a
/// null override exactly like a caller who never knew this class could take
/// one, so a failed load below is a game drawn in boxes rather than a game
/// that does not start.
final class _RealModels {
  const _RealModels({this.worker, this.hall, this.hallSize});

  final DeviceMesh? worker;
  final DeviceMesh? hall;
  final Vector3? hallSize;

  static Future<_RealModels> load(GraphicsDevice device) async {
    final DeviceMesh? worker = await _loadWorker(device);
    final (DeviceMesh, Vector3)? hall = await _loadHall(device);
    return _RealModels(worker: worker, hall: hall?.$1, hallSize: hall?.$2);
  }

  /// A crowd unit, already scaled and grounded by
  /// `tool/prepare_models.py` — see [StrategyVisuals.new]'s own doc for what
  /// "grounded" buys here.
  static Future<DeviceMesh?> _loadWorker(GraphicsDevice device) async {
    try {
      final document = await decodeModelInIsolate(
        ModelLoadRequest(source: BundleAssetSource('assets/models/worker.glb')),
      );
      final ModelSurface surface = document.surfaces.single;
      return DeviceMesh.upload(
        device,
        surface.mesh.transformed(surface.transform),
      );
    } catch (error) {
      debugPrint('strategy: worker.glb did not load ($error)');
      return null;
    }
  }

  /// A hall, uploaded once and stretched per instance in `bridge.dart` — its
  /// footprint comes from the level document, not from this file.
  static Future<(DeviceMesh, Vector3)?> _loadHall(GraphicsDevice device) async {
    try {
      final document = await decodeModelInIsolate(
        ModelLoadRequest(source: BundleAssetSource('assets/models/hall.glb')),
      );
      final ModelSurface surface = document.surfaces.single;
      final MeshData mesh = surface.mesh.transformed(surface.transform);
      final Aabb3 bounds = mesh.computeBounds();
      final Vector3 size = bounds.max - bounds.min;
      return (DeviceMesh.upload(device, mesh), size);
    } catch (error) {
      debugPrint('strategy: hall.glb did not load ($error)');
      return null;
    }
  }
}

/// Where the view opens, in world space.
///
/// Over the viewer's hall and as far down the map as its crowd, rather than at
/// the middle of the ground — which is what a map camera aims at by default,
/// and which drew a picture of empty hillside with the game just out of frame.
Vector3 _opening(Level level) {
  final EntityDef hall = level
      .ofType(StrategyEntities.camp)
      .firstWhere((EntityDef it) => (it.integer('side') ?? 0) == viewerSide);
  final Iterable<EntityDef> crowd = level
      .ofType(StrategyEntities.worker)
      .where((EntityDef it) => (it.integer('side') ?? 0) == viewerSide);
  return Vector3(
    hall.position.x,
    0.0,
    crowd.isEmpty ? hall.position.z : crowd.first.position.z,
  );
}
