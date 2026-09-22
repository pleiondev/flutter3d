part of 'command.dart';

/// Writes a finished [SimulationCache] into the object it answers for — the
/// one command that ever does, the same role [ApplyJobResult] already plays
/// for a modifier bake.
///
/// **Refused rather than applied when [baseVersion] has moved on**, for the
/// exact reason [ApplyJobResult]'s own doc comment gives: a bake can run for
/// real time, long enough for something else to edit the same object first,
/// and writing the answer in regardless would silently discard that edit.
/// Refusing leaves the document and the history exactly as they were —
/// `pro-sim-03`'s own "document/history untouched by a job that hasn't been
/// applied" — so whoever asked for the bake can ask again against the
/// object as it now stands.
final class ApplySimulationCache extends ModelCommand {
  const ApplySimulationCache({
    required this.objectId,
    required this.baseVersion,
    required this.cache,
  });

  final int objectId;
  final int baseVersion;
  final SimulationCache cache;

  /// [bake]'s own [BakeClothJobRequest.buildCache], as the command that
  /// writes it in — however many frames actually baked, cancelled partway or
  /// not.
  factory ApplySimulationCache.of(BakeClothJobRequest bake) =>
      ApplySimulationCache(
        objectId: bake.objectId,
        baseVersion: bake.baseVersion,
        cache: bake.buildCache(),
      );

  @override
  String get name => 'applySimulationCache';

  @override
  String get says => 'bake the simulation cache';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'objectId': objectId,
    'baseVersion': baseVersion,
    'cache': cache.toJson(),
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final object = project[objectId];
    if (object == null) return Outcome.refused('there is no object $objectId');
    if (object.version != baseVersion) {
      return Outcome.refused(
        'object $objectId has changed since this bake started (it is now '
        'version ${object.version}, the bake started at $baseVersion); its '
        'result no longer answers what the object currently is',
      );
    }
    return Outcome.done(
      project.withObject(object.copyWith(simulationCache: cache)),
    );
  }
}

/// Up to [maxKeys] frames of [cache], evenly spaced across it (both ends
/// included), as [ShapeKey]s — `pro-sim-05`'s own option (a).
///
/// **A chosen frame's positions travel verbatim, not resampled.** Blending
/// its key to weight 1 at the moment that frame played is then exactly
/// [cache]'s own answer for that frame, not a viewer's interpolation of two
/// neighbours agreeing with it approximately — the same "no data invented"
/// choice [ShapeKey.grownTo] states for a vertex it has never heard of.
///
/// [cache.frameCount] frames at or under [maxKeys] keeps every one of them,
/// named for its own index, rather than throwing any away to make room for a
/// spacing nothing needs.
List<ShapeKey> simulationCacheToShapeKeys(
  SimulationCache cache, {
  int maxKeys = 8,
}) {
  if (maxKeys <= 0) {
    throw ArgumentError.value(maxKeys, 'maxKeys', 'must be at least one');
  }
  final frameCount = cache.frameCount;
  if (frameCount == 0) return const <ShapeKey>[];
  final keyCount = frameCount < maxKeys ? frameCount : maxKeys;
  return <ShapeKey>[
    for (var k = 0; k < keyCount; k++)
      ShapeKey(
        'sim_${_evenlySpacedFrame(k, keyCount, frameCount)}',
        cache.frame(_evenlySpacedFrame(k, keyCount, frameCount)),
      ),
  ];
}

/// The [k]th of [keyCount] frames spread evenly across `[0, frameCount - 1]`,
/// both ends included — `k` itself when [keyCount] already covers every
/// frame, so the identity case introduces no rounding at all.
int _evenlySpacedFrame(int k, int keyCount, int frameCount) =>
    keyCount == frameCount
    ? k
    : (k * (frameCount - 1) / (keyCount - 1)).round();

/// Turns [id]'s own baked [ModelObject.simulationCache] into up to [maxKeys]
/// shape keys on the same object, appended to whatever [ShapeSet] it already
/// has — `pro-sim-05`'s own row, the export path a shape key already has:
/// [shapeKeyMorphTargets] is what `toModelDocument` calls on every key a
/// [ShapeSet] carries, cloth-baked or sculpted by hand, so nothing downstream
/// of this command has to know which one it was.
///
/// **Refused rather than silently skipped when the counts disagree.** A
/// shape key is indexed exactly like [EditMesh]'s own vertices — the same
/// contract [AddShapeFromMesh] keeps — so a cache baked for a mesh that has
/// since gained or lost vertices would blend a stranger's positions onto
/// this one's topology; refusing says why instead of drawing it wrong.
final class BakeSimulationToShapes extends ModelCommand {
  const BakeSimulationToShapes({required this.id, this.maxKeys = 8});

  final int id;
  final int maxKeys;

  @override
  String get name => 'bakeSimulationToShapes';

  @override
  String get says => 'turn the simulation cache into shape keys';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'id': id,
    'maxKeys': maxKeys,
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final object = project[id];
    if (object == null) return Outcome.refused('there is no object $id');
    final cache = object.simulationCache;
    if (cache == null) {
      return Outcome.refused(
        '"${object.name}" has no baked simulation to turn into shape keys',
      );
    }
    if (object.geometry is! EditedGeometry) {
      return Outcome.refused(
        '"${object.name}" has no mesh to hold a shape key',
      );
    }
    final mesh = (object.geometry as EditedGeometry).mesh;
    if (cache.vertexCount != mesh.vertexSlotCount) {
      return Outcome.refused(
        'the simulation cache has ${cache.vertexCount} vertices and '
        '"${object.name}"\'s mesh has ${mesh.vertexSlotCount}',
      );
    }

    final newKeys = simulationCacheToShapeKeys(cache, maxKeys: maxKeys);
    final shapes = object.shapeSet;
    return Outcome.done(
      project.withObject(
        object.copyWith(
          shapeSet: shapes.copyWith(
            keys: <ShapeKey>[...shapes.keys, ...newKeys],
            weights: <double>[...shapes.weights, for (final _ in newKeys) 0.0],
          ),
        ),
      ),
    );
  }
}
