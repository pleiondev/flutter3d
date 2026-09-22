/// One history step for a whole auto-rig result — `doc-36d`'s own row.
///
/// **`buildSkeleton` (`rig_template.dart`, `anim-21`/`anim-33d`) hands back a
/// [BuiltRig]: fresh joint objects and a [ProjectSkeleton], neither one yet
/// in any [ModelProject].** Writing those in by hand — a loop of
/// [ModelProject.added], a `copyWith` for the skeleton list, a second
/// `copyWith` for [ModelObject.skeletonIndex] — used to happen inline in
/// `flutter3d_model_mcp`'s own `autoRig` recipe, through [ReplaceDocument];
/// [ReplaceDocument] is deliberately outside [modelCommandNames] (see its own
/// class comment in `command.dart`), so that whole result never reached the
/// undo journal as itself — undoing an auto-rig undid the *entire* recipe's
/// document swap, and an agent's own transcript never named the step at all.
/// [SetRig] is that same result, given the ordinary [ModelCommand] shape
/// every other row here already has: a real journal entry, a real `says`,
/// and — the reason it exists rather than three separate commands run in one
/// [ModelHistory] transaction — one place that gets to refuse the whole rig
/// atomically rather than adding half of it and then failing.
///
/// **[jointObjects] arrive with their ids already chosen**, the same way
/// [BuiltRig.objects] already carries them: [buildSkeleton]'s own
/// `firstObjectId` parameter is `project.nextId` at the moment a caller
/// built the rig, not a value this command invents. [apply] appends them
/// verbatim, in order — each one's own [ModelObject.parent] already names an
/// earlier entry in the same list, or the controller object first in it, or
/// nothing — and only ever refuses when one of those ids is already taken,
/// which is `apply`'s own first check, before anything else about this
/// command is read.
///
/// **[skinObjectId] and [weights] are two separate, independently optional
/// things.** A caller may bind an existing skinned mesh to the freshly-built
/// skeleton with no weights at all (the ordinary `autoRig` case today: the
/// bind-weights half is a separate background job, `RigJob`, that answers
/// later through its own [ApplyJobResult]) — [skinObjectId] alone, and
/// [apply] does nothing more than [BindSkin] already does. When [weights] is
/// given too, [apply] refuses it the exact way [ApplyJobResult] refuses
/// stale mesh bytes — [skinObjectId]'s own [ModelObject.version] has to
/// still equal [SkinWeightsBlob.baseVersion] — because a bind-weights job
/// captures the object it started from exactly the way any other job does,
/// and time may have passed between that capture and this command reaching
/// [ModelHistory.run].
part of 'command.dart';

/// A bind-weights job's own answer, flattened: eight `Float32`s per vertex
/// slot — the local joint index (into the *new* skeleton's own
/// [ProjectSkeleton.joints]) at four slots, then the weight at each of those
/// same four slots — the same shape [EditMesh.setSkin]'s own
/// [VertexAttributes] already carries, laid end to end across every vertex
/// slot in order rather than boxed one [VertexAttributes] at a time, since
/// that is the form a job answers in and [toJson] can base64 whole.
///
/// **[baseVersion] is [ApplyJobResult]'s own staleness rule, carried here
/// instead of duplicated as a second field on [SetRig] itself.** See this
/// file's own library comment for what [SetRig.apply] does with it.
final class SkinWeightsBlob {
  const SkinWeightsBlob({required this.baseVersion, required this.data});

  /// The skinned object's own [ModelObject.version] when the job that built
  /// [data] started reading it.
  final int baseVersion;

  /// Length is always eight times the vertex-slot count of the mesh this was
  /// captured from; [SetRig.apply] refuses a blob whose length disagrees
  /// with [SetRig.skinObjectId]'s own mesh rather than writing past it or
  /// leaving the tail of a longer mesh untouched.
  final Float32List data;

  Map<String, Object?> toJson() => <String, Object?>{
    'baseVersion': baseVersion,
    'data': base64Encode(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    ),
  };

  /// A [SkinWeightsBlob] from its own [toJson], or null when a field is
  /// missing or the wrong shape.
  static SkinWeightsBlob? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    return switch (json) {
      {'baseVersion': final int baseVersion, 'data': final String encoded} =>
        SkinWeightsBlob(
          baseVersion: baseVersion,
          data: Float32List.sublistView(base64Decode(encoded)),
        ),
      _ => null,
    };
  }
}

/// One history step for a whole auto-rig result. See this file's own library
/// comment for the shape and what each field is for.
final class SetRig extends ModelCommand {
  const SetRig({
    required this.jointObjects,
    required this.skeleton,
    this.skinObjectId,
    this.weights,
    required this.label,
  });

  /// Every joint (and, when [RigBuildOptions.controllers] asked for one, the
  /// rig controller ahead of them) [buildSkeleton] built, ids already
  /// chosen — see this file's own library comment.
  final List<ModelObject> jointObjects;

  /// The skeleton [jointObjects] belong to, appended to
  /// [ModelProject.skeletons] as one new entry.
  final ProjectSkeleton skeleton;

  /// The object [apply] binds to the freshly-appended skeleton, or null to
  /// build a skeleton with nothing bound to it yet.
  final int? skinObjectId;

  /// [skinObjectId]'s own new skin weights, or null to leave whatever it
  /// already has (or has none of) untouched — see this file's own library
  /// comment for how this interacts with [skinObjectId].
  final SkinWeightsBlob? weights;

  /// What the history offers to undo — there is no one sentence every
  /// auto-rig deserves ("17 joints" reads nothing like "54 joints, fingers
  /// and a face"), so the caller that already knows which rig this is
  /// supplies it, the same way [ReplaceDocument]'s own `says` is a
  /// constructor argument rather than something this command invents.
  final String label;

  @override
  String get name => 'setRig';

  @override
  String get says => label;

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'jointObjects': <Object?>[
      for (final ModelObject object in jointObjects) _jointObjectJson(object),
    ],
    'skeleton': _rigSkeletonJson(skeleton),
    if (skinObjectId != null) 'skinObjectId': skinObjectId,
    if (weights != null) 'weights': weights!.toJson(),
    'label': label,
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    for (final ModelObject jointObject in jointObjects) {
      if (project[jointObject.id] != null) {
        return Outcome.refused(
          'object ${jointObject.id} already exists in this project',
        );
      }
    }

    // A local copy of the public `skinObjectId` field: Dart cannot promote a
    // public field from `int?` to `int` after a null check, only a local.
    final int? skinObjectId = this.skinObjectId;

    ModelObject? skinObjectBefore;
    EditMesh? mesh;
    if (skinObjectId != null) {
      skinObjectBefore = project[skinObjectId];
      if (skinObjectBefore == null) {
        return Outcome.refused('there is no object $skinObjectId to skin');
      }
      final SkinWeightsBlob? blob = weights;
      if (blob != null) {
        // The exact same staleness rule `ApplyJobResult.apply` refuses
        // stale mesh bytes with (`job_commands.dart`) — a bind-weights job
        // captures the object it started from exactly the way any other
        // job does.
        if (skinObjectBefore.version != blob.baseVersion) {
          return Outcome.refused(
            'object $skinObjectId has changed since this job started (it '
            'is now version ${skinObjectBefore.version}, the job started '
            'at ${blob.baseVersion}); its result no longer answers what '
            'the object currently is',
          );
        }
        final EditedGeometry? edited = switch (skinObjectBefore.geometry) {
          final EditedGeometry it => it,
          _ => null,
        };
        if (edited == null) {
          return Outcome.refused(
            '"${skinObjectBefore.name}" has no mesh to skin — bake it to a '
            'mesh first',
          );
        }
        mesh = edited.mesh;
        final expected = mesh.vertexSlotCount * 8;
        if (blob.data.length != expected) {
          return Outcome.refused(
            'the skin weights blob has ${blob.data.length} numbers; '
            '"${skinObjectBefore.name}" needs $expected (8 per vertex)',
          );
        }
      }
    }

    var next = project;
    if (jointObjects.isNotEmpty) {
      var maxId = next.nextId - 1;
      for (final ModelObject jointObject in jointObjects) {
        if (jointObject.id > maxId) maxId = jointObject.id;
      }
      next = ModelProject(
        profile: next.profile,
        objects: <ModelObject>[...next.objects, ...jointObjects],
        materials: next.materials,
        images: next.images,
        nextId: maxId + 1,
        skeletons: next.skeletons,
        clips: next.clips,
        lighting: next.lighting,
      );
    }

    final skeletonIndex = next.skeletons.length;
    next = next.copyWith(
      skeletons: <ProjectSkeleton>[...next.skeletons, skeleton],
    );

    EditMesh? touched;
    if (skinObjectId != null) {
      final target = next[skinObjectId]!;
      final SkinWeightsBlob? blob = weights;
      if (blob != null && mesh != null) {
        final liveMesh = mesh;
        liveMesh.beginStep();
        for (var v = 0; v < liveMesh.vertexSlotCount; v++) {
          final base = v * 8;
          liveMesh.setSkin(
            v,
            VertexAttributes(
              joints: Vector4(
                blob.data[base],
                blob.data[base + 1],
                blob.data[base + 2],
                blob.data[base + 3],
              ),
              weights: Vector4(
                blob.data[base + 4],
                blob.data[base + 5],
                blob.data[base + 6],
                blob.data[base + 7],
              ),
            ),
          );
        }
        liveMesh.endStep();
        touched = liveMesh;
        next = next.withObject(
          target.copyWith(
            skeletonIndex: skeletonIndex,
            geometry: EditedGeometry(liveMesh),
          ),
        );
      } else {
        next = next.withObject(target.copyWith(skeletonIndex: skeletonIndex));
      }
    }

    return Outcome.done(next, meshTouched: touched);
  }
}

/// A joint (or rig controller) [ModelObject] as [SetRig] writes it down —
/// only what [buildSkeleton] ever actually gives one: a bare [SocketGeometry],
/// a transform, a name and a parent. Every other [ModelObject] field
/// ([ModelObject.materialSlots], [ModelObject.modifiers] and the rest) is
/// left at its default, which is what every joint [buildSkeleton] has ever
/// built already carries.
Map<String, Object?> _jointObjectJson(ModelObject object) => <String, Object?>{
  'id': object.id,
  'name': object.name,
  'transform': object.transform.storage.toList(),
  'parent': object.parent,
};

/// The inverse of [_jointObjectJson] — null (this file's own "no half-built
/// command" rule) for anything whose geometry was not written as a bare
/// socket, since a joint built any other way is outside what [SetRig] was
/// ever asked to carry.
ModelObject? _jointObjectFromJson(Object? json) {
  if (json is! Map<String, Object?>) return null;
  return switch ((json['id'], json['name'], _doubles(json['transform'], 16))) {
    (final int id, final String objectName, final List<double> transform) =>
      ModelObject(
        id: id,
        name: objectName,
        geometry: const SocketGeometry(),
        transform: Matrix4.fromList(transform),
        parent: json['parent'] as int?,
      ),
    _ => null,
  };
}

/// Every [_jointObjectFromJson] in [json], or null on the first one that
/// does not read back.
List<ModelObject>? _jointObjectsFrom(Object? json) {
  if (json is! List) return null;
  final out = <ModelObject>[];
  for (final Object? each in json) {
    final object = _jointObjectFromJson(each);
    if (object == null) return null;
    out.add(object);
  }
  return out;
}

/// [ProjectSkeleton]/[IkConstraint], written down the same way
/// `project_format.dart`'s own (private to that file, and so unreachable
/// from here) `_skeletonJson`/`_ikConstraintJson` already do — repeated
/// rather than shared, the same call [PaintMirror.fromJson]'s own doc
/// comment already makes for a smaller map: the two readers live in
/// different libraries and neither is worth a third file just to hold this.
Map<String, Object?> _rigSkeletonJson(
  ProjectSkeleton skeleton,
) => <String, Object?>{
  'name': skeleton.name,
  'joints': <int>[...skeleton.joints],
  'inverseBindMatrices': <Object?>[
    for (final Matrix4 m in skeleton.inverseBindMatrices)
      <double>[...m.storage],
  ],
  'skeletonRoot': skeleton.skeletonRoot,
  'constraints': <Object?>[
    for (final IkConstraint c in skeleton.constraints) _rigIkConstraintJson(c),
  ],
};

Map<String, Object?> _rigIkConstraintJson(IkConstraint c) => <String, Object?>{
  'rootJointId': c.rootJointId,
  'midJointId': c.midJointId,
  'effectorJointId': c.effectorJointId,
  'target': <double>[c.target.x, c.target.y, c.target.z],
  'pole': <double>[c.pole.x, c.pole.y, c.pole.z],
};

List<int>? _intListFrom(Object? json) {
  if (json is! List) return null;
  final out = <int>[];
  for (final Object? each in json) {
    if (each is! int) return null;
    out.add(each);
  }
  return out;
}

List<Matrix4>? _matrixListFrom(Object? json) {
  if (json is! List) return null;
  final out = <Matrix4>[];
  for (final Object? each in json) {
    final matrix = _doubles(each, 16);
    if (matrix == null) return null;
    out.add(Matrix4.fromList(matrix));
  }
  return out;
}

/// Absent reads as no constraints at all — a skeleton [SetRig] built before
/// [RigBuildOptions.ikChains] ever asked for any.
List<IkConstraint>? _rigIkConstraintsFrom(Object? json) {
  if (json == null) return const <IkConstraint>[];
  if (json is! List) return null;
  final out = <IkConstraint>[];
  for (final Object? each in json) {
    if (each case {
      'rootJointId': final int rootJointId,
      'midJointId': final int midJointId,
      'effectorJointId': final int effectorJointId,
      'target': final Object? targetJson,
      'pole': final Object? poleJson,
    }) {
      final target = _doubles(targetJson, 3);
      final pole = _doubles(poleJson, 3);
      if (target == null || pole == null) return null;
      out.add(
        IkConstraint(
          rootJointId: rootJointId,
          midJointId: midJointId,
          effectorJointId: effectorJointId,
          target: Vector3(target[0], target[1], target[2]),
          pole: Vector3(pole[0], pole[1], pole[2]),
        ),
      );
    } else {
      return null;
    }
  }
  return out;
}

ProjectSkeleton? _rigSkeletonFromJson(Object? json) {
  if (json is! Map<String, Object?>) return null;
  final List<int>? joints = _intListFrom(json['joints']);
  final List<Matrix4>? matrices = _matrixListFrom(json['inverseBindMatrices']);
  if (joints == null || matrices == null || matrices.length != joints.length) {
    return null;
  }
  final List<IkConstraint>? constraints = _rigIkConstraintsFrom(
    json['constraints'],
  );
  if (constraints == null) return null;
  return ProjectSkeleton(
    joints: joints,
    inverseBindMatrices: matrices,
    skeletonRoot: json['skeletonRoot'] as int?,
    name: json['name'] as String?,
    constraints: constraints,
  );
}
