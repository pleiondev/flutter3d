/// Runs `pro-sim-01`'s cloth solver forward, frame by frame, into a
/// [SimulationCache] — `pro-sim-03`'s own row, built on `pro-job-01`'s job
/// shape.
///
/// **A value that runs itself one chunk at a time, not a `Job` itself.**
/// `apps/flutter3d_modeler`'s own generic `Job` (`ui-25`'s runner) is what a
/// `JobButton` drives — `chunkCount`, `runChunk`, `progress`, `cancel` — and
/// this package has no window to hand one to.
/// [BakeClothJobRequest.runChunk] has exactly the shape a `Job`'s own
/// `runChunk` field wants, `Future<void> Function(int index)`, so a caller
/// with a `Job` on hand builds one with `chunkCount: bake.frameCount` and
/// `runChunk: bake.runChunk` and never has to adapt anything; a caller
/// without one — this package's own tests, or a command-line bake — calls
/// [runChunk] in a plain loop and gets the exact same cancellation-safety
/// contract for free.
///
/// **[buildCache] reads what actually ran, not what was asked for.** `Job`'s
/// own doc comment already says a cancelled job's `combine` is never called;
/// [buildCache] is why that is fine here — it is not `combine`, it is a
/// method on the request itself, so it answers correctly whether every frame
/// ran, some did, or `cancel` came before the first one — the whole reason
/// cancelling at frame 50 leaves exactly 50 frames cached, not zero.
library;

import 'dart:typed_data';

import 'package:flutter3d_cloth/flutter3d_cloth.dart';

import 'simulation_cache.dart';

/// Bakes [mesh] forward [frameCount] frames of [dt] seconds each, one
/// `stepCloth` call per frame — cheap enough, at the scale this cache is
/// meant for, to fit inside a `Job` chunk's own per-step time budget on the
/// web without batching several frames into one chunk.
final class BakeClothJobRequest implements SimulationBakeRequest {
  BakeClothJobRequest({
    required this.objectId,
    required this.baseVersion,
    required ClothMesh mesh,
    required this.settings,
    required this.dt,
    required this.frameCount,
    this.obstacles = const <ClothObstacle>[],
  }) : _mesh = mesh,
       vertexCount = mesh.particleCount,
       assert(frameCount > 0, 'a bake of zero frames has nothing to cache');

  /// Which object this will answer for, once [ApplySimulationCache] writes
  /// the finished [SimulationCache] in.
  @override
  final int objectId;

  /// [ModelObject.version] at the moment this was built. [ApplySimulationCache]
  /// refuses a [SimulationCache] whose own bake started at a [baseVersion]
  /// the object has since moved past — the same contract [ApplyJobResult]
  /// already keeps for a modifier bake.
  @override
  final int baseVersion;

  final ClothSettings settings;

  /// Seconds one frame advances the solver by.
  final double dt;

  /// How many frames this bake is aiming for — [buildCache] may hold fewer,
  /// never more.
  @override
  final int frameCount;

  final List<ClothObstacle> obstacles;

  /// [ClothMesh.particleCount] at the moment this was built — every captured
  /// frame is this many vertices long.
  @override
  final int vertexCount;

  final ClothMesh _mesh;
  final List<Float32List> _frames = <Float32List>[];

  /// How many frames [runChunk] has actually captured so far — grows by one
  /// each call, so this is always the true count, including for a bake a
  /// `Job.cancel` stopped partway.
  int get bakedFrameCount => _frames.length;

  /// Chunk [index]'s whole job: advance the solver one frame, then snapshot
  /// its own vertex positions. [index] itself is unused — the solver only
  /// knows how to step forward from wherever it already is — but the
  /// parameter is here because this is handed to `Job<T>` as its own
  /// `runChunk` verbatim.
  Future<void> runChunk(int index) async {
    stepCloth(_mesh, settings, dt, obstacles: obstacles);
    _frames.add(Float32List.fromList(_mesh.positions));
  }

  /// [_frames] as a [SimulationCache], whatever [runChunk] has captured so
  /// far — see the class comment for why this is safe to call after a
  /// cancelled bake, not only a finished one.
  SimulationCache buildCache() =>
      SimulationCache(vertexCount: vertexCount, frames: _frames);

  /// Every chunk [runChunk] has not run yet, then [buildCache] — the whole
  /// bake at once, for a caller with no `Job` to drive it a chunk at a time.
  @override
  Future<SimulationCache> bake() async {
    for (var index = bakedFrameCount; index < frameCount; index++) {
      await runChunk(index);
    }
    return buildCache();
  }
}
