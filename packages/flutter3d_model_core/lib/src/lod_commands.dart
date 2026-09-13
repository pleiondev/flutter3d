/// The commands over one object's own [LodSpec] list — `pro-lod-03`'s own
/// row.
///
/// A `part` of `command.dart` for the reason every other command file
/// gives: [ModelCommand] is sealed, and a journal writer's exhaustive
/// `switch` is only exhaustive if the compiler can see every case inside
/// one library.
///
/// **What is not here.** The actual simplified meshes these specs describe
/// are `LodMeshCache`'s own job (`lod_cache.dart`), not this file's: a
/// command changes what a project *says*, a cache is free to have opinions
/// about how expensive answering that is. None of the three below touches
/// a cache directly, for the same reason [Rename] does not reach into
/// `ModifierEvaluationCache` — a pure function over [ModelProject] has no
/// handle to one.
part of 'command.dart';

/// The object [id] names, or the sentence to refuse with.
({ModelObject? object, String? refused}) _lodTarget(
  ModelProject project,
  int id,
) {
  final object = project[id];
  if (object == null) {
    return (object: null, refused: 'there is no object $id');
  }
  return (object: object, refused: null);
}

/// Appends a new level of detail to [id]'s own list.
///
/// Order is left exactly as given — a caller that wants finest-first, the
/// order `package:flutter3d`'s own `LodGroup` sorts into regardless, can
/// simply add them that way; nothing here re-sorts on its behalf.
final class AddLod extends ModelCommand {
  const AddLod({
    required this.id,
    required this.ratio,
    required this.maxScreenFraction,
  });

  final int id;
  final double ratio;
  final double maxScreenFraction;

  @override
  String get name => 'addLod';

  @override
  String get says => 'add a level of detail';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'id': id,
    'ratio': ratio,
    'maxScreenFraction': maxScreenFraction,
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final (:object, :refused) = _lodTarget(project, id);
    if (object == null) return Outcome.refused(refused!);
    if (ratio <= 0.0 || ratio > 1.0) {
      return Outcome.refused(
        'a level of detail\'s ratio has to be between 0 and 1; $ratio is not',
      );
    }
    if (maxScreenFraction <= 0.0) {
      return Outcome.refused(
        'a level of detail\'s screen fraction has to be positive; '
        '$maxScreenFraction is not',
      );
    }
    return Outcome.done(
      project.withObject(
        object.copyWith(
          lods: <LodSpec>[
            ...object.lods,
            LodSpec(ratio: ratio, maxScreenFraction: maxScreenFraction),
          ],
        ),
      ),
    );
  }
}

/// Changes one of [id]'s own levels of detail's target ratio, leaving its
/// screen threshold alone.
///
/// **Bumps [ModelObject.version] like every other edit, and that alone is
/// what invalidates `LodMeshCache`'s entry for this level.** The cache
/// keys on version, so the next `meshFor` call after this one finds no
/// cached answer for the version this object now carries and regenerates
/// with the new ratio. Nothing here has to reach into a cache to say so —
/// the same way [Rename] does not have to tell `ModifierEvaluationCache`
/// that nothing it holds went stale.
final class SetLodRatio extends ModelCommand {
  const SetLodRatio({
    required this.id,
    required this.lodIndex,
    required this.ratio,
  });

  final int id;
  final int lodIndex;
  final double ratio;

  @override
  String get name => 'setLodRatio';

  @override
  String get says => "change a level of detail's ratio";

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'id': id,
    'lodIndex': lodIndex,
    'ratio': ratio,
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final (:object, :refused) = _lodTarget(project, id);
    if (object == null) return Outcome.refused(refused!);
    if (lodIndex < 0 || lodIndex >= object.lods.length) {
      return Outcome.refused(
        '"${object.name}" has ${object.lods.length} levels of detail; '
        '$lodIndex is not one of them',
      );
    }
    if (ratio <= 0.0 || ratio > 1.0) {
      return Outcome.refused(
        'a level of detail\'s ratio has to be between 0 and 1; $ratio is not',
      );
    }
    final lods = List<LodSpec>.of(object.lods);
    lods[lodIndex] = lods[lodIndex].copyWith(ratio: ratio);
    return Outcome.done(project.withObject(object.copyWith(lods: lods)));
  }
}

/// Forces every one of [id]'s own cached LOD meshes to regenerate on the
/// next ask, whatever `ModelObject.version` currently says — for after a
/// change to the simplification algorithm itself, which a version bump
/// alone already covers for the ordinary case of an edited base mesh.
///
/// **Touches nothing about the object beyond its own version.** The ratios
/// and thresholds a project actually holds are unaffected — this is not
/// "throw the LODs away and start over" — since a version bump is all a
/// pure command over [ModelProject] can offer: the meshes themselves live
/// in `LodMeshCache`, a stateful cache this command has no handle to, the
/// same separation `ReadinessCache` and `ModifierEvaluationCache` already
/// keep from the commands that might make their own answers stale.
final class RegenerateLods extends ModelCommand {
  const RegenerateLods(this.id);

  final int id;

  @override
  String get name => 'regenerateLods';

  @override
  String get says => 'regenerate the levels of detail';

  @override
  Map<String, Object?> get arguments => <String, Object?>{'id': id};

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final (:object, :refused) = _lodTarget(project, id);
    if (object == null) return Outcome.refused(refused!);
    if (object.lods.isEmpty) {
      return Outcome.refused(
        '"${object.name}" has no levels of detail to regenerate',
      );
    }
    return Outcome.done(
      project.withObject(object.copyWith(lods: List<LodSpec>.of(object.lods))),
    );
  }
}
