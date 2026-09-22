/// A weight-paint brush stroke — `anim-10`'s own row, closed for real: the
/// brush that calls `flutter3d_mesh`'s already-built one-vertex primitives
/// (`paintWeight`/`assignSelection`/`mirrorWeights`/`normalizeVertexWeights`/
/// `pruneVertexWeights`, `packages/flutter3d_mesh/lib/src/skin/vertex_weights.dart`)
/// per hit, the sampling and BVH picking that file's own doc comment names as
/// this row's job and not theirs — and [PaintWeights], the [ModelCommand]
/// wrapping it, so a stroke is one undo step rather than an edit nothing can
/// take back.
///
/// **Hit-tested against the mesh's own CURRENT posed shape, not its bind
/// pose.** A bent elbow's skin has already moved away from where the rest
/// pose put it, and a brush aimed at the elbow has to find vertices where
/// they now are. Posed position is computed the same way `anim-15`'s
/// `IkConstraint` and `anim-20`'s `ShapeDriver` already read "the current
/// pose" — straight off [worldTransformOf] and [ModelObject.transform],
/// with no live engine `Pose`/`SkinBlend` involved, because
/// `flutter3d_model_core` cannot depend on the windowed engine package
/// those live in. Blending itself (`jointWorld * inverseBindMatrix *
/// restPosition`, summed by each vertex's own stored weights) is the same
/// arithmetic the engine's own skinned vertex shader runs, just walked once
/// per stroke in Dart instead of once per frame on a GPU.
///
/// **No BVH.** `mesh_bvh.dart`'s own `MeshBvh` answers face queries against
/// whatever positions it was built from, and rebuilding it from posed
/// (rather than bind-pose) positions for every stroke — or re-deriving a
/// vertex set from its face query — is more machinery than this row's own
/// acceptance asks for: nothing here names a vertex-count budget, and a
/// plain scan over the mesh's own (typically low thousands of) vertices is
/// simple and provably correct where feeding posed positions through a
/// structure built for bind-pose faces would not obviously be. A row that
/// actually needs the speed can reach for the BVH later; this one does not.
///
/// **`PaintWeights` closes `anim-10` exactly as its own wording already
/// promised: "a stroke is one Cmd-Z."** The one drag is one [EditMesh]
/// journal step — [paintWeights] brackets it with one [EditMesh.beginStep]
/// before the first sample and one [EditMesh.endStep] after the last, the
/// same low-level bracketing every mesh command in `mesh_commands.dart`
/// keeps through its own `_asMeshStep` — and a hundred of these run inside
/// one [ModelHistory] transaction collapse into the one undo step that
/// transaction leaves behind, `history.dart`'s own doc comment describing
/// exactly this shape.
///
/// **"A limit from the profile, renormalised on every stroke."** After the
/// samples land (and after [mirror], when one is given), every vertex the
/// stroke touched is pruned to [PaintWeights.maxInfluences] — the project's
/// own [ProjectProfile.maxInfluences] by default — through
/// [pruneVertexWeights], which renormalizes what is left as part of its own
/// contract; there is no separate renormalize call needed after it. Only
/// when [PaintWeights.normalize] is false is this whole pass skipped,
/// leaving a stroke's raw weights exactly as painted — [paintWeight]'s own
/// four-slot cap still applies underneath either way, since that is
/// `mesh-60`'s own storage limit, not this row's.
part of 'command.dart';

/// One brush hit within a drag: where it landed, in the same space
/// [worldTransformOf] answers in, and how far its influence reaches.
final class BrushSample {
  const BrushSample({required this.center, required this.radius});

  final Vector3 center;

  /// Vertices farther than this from [center] (in their own current, posed
  /// position) are untouched by this sample.
  final double radius;

  Map<String, Object?> toJson() => <String, Object?>{
    'center': <double>[center.x, center.y, center.z],
    'radius': radius,
  };

  /// A [BrushSample] from its own [toJson], or null when a field is missing
  /// or the wrong shape.
  static BrushSample? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    return switch (json) {
      {'center': final Object? centerJson, 'radius': final num radius} =>
        switch (_doubles(centerJson, 3)) {
          final List<double> center => BrushSample(
            center: Vector3(center[0], center[1], center[2]),
            radius: radius.toDouble(),
          ),
          null => null,
        },
      _ => null,
    };
  }
}

/// How a sample changes a vertex's weight at `paintWeights`' own `joint`.
///
/// A `final class` with `static const` instances rather than an `enum` —
/// the same choice `BlendMode`/`DriverAxis` already make in this package,
/// and for the same reason: a fixed, small domain that does not want a
/// fourth case added by accident.
final class PaintWeightsMode {
  const PaintWeightsMode._(this.name);

  final String name;

  /// Accumulates onto whatever a vertex already has, via [paintWeight] —
  /// several overlapping dabs in one stroke add up rather than each
  /// overwriting the last.
  static const PaintWeightsMode paint = PaintWeightsMode._('paint');

  /// Replaces a vertex's whole influence list with this one joint at full
  /// `paintWeights`' own `strength`, via [assignSelection] — a hard "this belongs
  /// to this bone now" rather than a blend. Falloff plays no part here: a
  /// vertex either is or is not this stroke's, and a partial assign would
  /// leave a vertex whose weights sum to less than one, which is the exact
  /// defect [assignSelection] itself exists to avoid.
  static const PaintWeightsMode assign = PaintWeightsMode._('assign');

  @override
  String toString() => 'PaintWeightsMode.$name';
}

/// Mirrors every vertex a stroke touched across a plane once the stroke
/// itself is done — the same parameters [mirrorWeights] already takes,
/// carried here as one value instead of four loose ones.
final class PaintMirror {
  const PaintMirror({
    required this.axis,
    required this.jointMirror,
    this.plane = 0.0,
    this.tolerance = 1e-4,
  });

  /// `0`=x, `1`=y, `2`=z — [mirrorWeights]' own convention.
  final int axis;

  /// [ModelObject.id]s a mirrored vertex's joints are remapped through; an
  /// id absent here keeps its own joint, the same default [mirrorWeights]
  /// gives a spine or a head bone straddling the plane.
  final Map<int, int> jointMirror;

  final double plane;
  final double tolerance;

  Map<String, Object?> toJson() => <String, Object?>{
    'axis': axis,
    'jointMirror': jointMirror.map(
      (int key, int value) => MapEntry(key.toString(), value),
    ),
    'plane': plane,
    'tolerance': tolerance,
  };

  /// A [PaintMirror] from its own [toJson], or null when a field is missing
  /// or the wrong shape — [MirrorJoints]' own `jointMirror` reader, repeated
  /// here rather than shared, since the two commands' readers live in
  /// different `switch` shapes and neither is worth a third file just to
  /// hold one map decode.
  static PaintMirror? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    return switch (json) {
      {
        'axis': final int axis,
        'jointMirror': final Map<String, Object?> jointMirrorJson,
      } =>
        PaintMirror(
          axis: axis,
          jointMirror: jointMirrorJson.map(
            (String key, Object? value) =>
                MapEntry(int.parse(key), value! as int),
          ),
          plane: (json['plane'] as num?)?.toDouble() ?? 0.0,
          tolerance: (json['tolerance'] as num?)?.toDouble() ?? 1e-4,
        ),
      _ => null,
    };
  }
}

/// [vertex]'s own current, posed position: [mesh]'s bind-pose position for
/// it, skinned through [jointWorldTransforms] (one per entry of
/// [skeleton]'s own [ProjectSkeleton.joints], already resolved once for the
/// whole stroke rather than re-walked per vertex) and [skeleton]'s own
/// [ProjectSkeleton.inverseBindMatrices].
///
/// A vertex nothing has ever skinned reads as fully bound to joint 0 —
/// [weightsOf]'s own default — so it still poses with the rest of the mesh
/// rather than sitting frozen at its bind-pose position.
Vector3 _posedPositionOf(
  EditMesh mesh,
  int vertex,
  ProjectSkeleton skeleton,
  List<Matrix4> jointWorldTransforms,
) {
  final rest = mesh.positionOf(vertex);
  final pairs = weightsOf(mesh, vertex);
  if (pairs.isEmpty) return rest;

  final blended = Vector3.zero();
  for (final pair in pairs) {
    if (pair.joint < 0 || pair.joint >= skeleton.joints.length) continue;
    final skin = Matrix4.copy(jointWorldTransforms[pair.joint])
      ..multiply(skeleton.inverseBindMatrices[pair.joint]);
    blended.addScaled(skin.transformed3(Vector3.copy(rest)), pair.weight);
  }
  return blended;
}

/// Every live vertex's own [_posedPositionOf], resolved once before a stroke
/// starts writing anything.
///
/// **A snapshot, not a live read — deliberately, and not merely for speed.**
/// [paintWeight] changes a vertex's own stored weights, which is exactly
/// what [_posedPositionOf] reads to place that vertex. Recomputing a
/// vertex's position from its own still-being-painted weights partway
/// through a drag lets a stroke pull its own targets out from under itself:
/// a vertex freshly given some share of a joint that has not moved gets
/// dragged partway toward that joint's own position, which can carry it
/// clean out of a later sample's radius in the same drag — a stroke that
/// starts by finding a vertex and ends by having painted past it. Freezing
/// every position before the first write means every sample in one drag
/// judges "who is under the brush" against the same, real, pre-stroke
/// shape.
Map<int, Vector3> _posedPositions(
  EditMesh mesh,
  ProjectSkeleton skeleton,
  List<Matrix4> jointWorldTransforms,
) => <int, Vector3>{
  for (var v = 0; v < mesh.vertexSlotCount; v++)
    if (mesh.isVertexAlive(v))
      v: _posedPositionOf(mesh, v, skeleton, jointWorldTransforms),
};

/// Paints [joint]'s influence over every vertex [samples] touches, hit-tested
/// against each vertex's current posed position — the low-level brush
/// [PaintWeights] runs inside one journal step: `paintWeights(joint,
/// samples, strength, mode, mirror, normalize, maxInfluences)`.
///
/// [joint] is a [ModelObject.id], the same addressing `IkConstraint` and
/// `ShapeDriver` already use — not the local, vertex-attribute-slot index
/// [WeightPair.joint] stores; this looks that index up itself via
/// `skeleton.joints.indexOf(joint)`. Does nothing when [joint] does not
/// belong to [skeleton], or [samples] is empty.
///
/// [normalize] (default false, here — [PaintWeights] itself defaults to
/// true) gates one pass over every touched vertex after painting and
/// mirroring: [pruneVertexWeights] to [maxInfluences] when one is given —
/// which renormalizes what is left as part of its own contract — or a bare
/// [normalizeVertexWeights] when it is not.
///
/// The whole drag is one journal step on [mesh]: nothing here refuses
/// midway, so there is nothing to roll back, but the batching itself is
/// still real — a hundred overlapping samples in one drag cost one undo
/// entry, not a hundred.
void paintWeights({
  required ModelProject project,
  required EditMesh mesh,
  required ProjectSkeleton skeleton,
  required int joint,
  required List<BrushSample> samples,
  required double strength,
  PaintWeightsMode mode = PaintWeightsMode.paint,
  PaintMirror? mirror,
  bool normalize = false,
  int? maxInfluences,
}) {
  final localJoint = skeleton.joints.indexOf(joint);
  if (localJoint < 0 || samples.isEmpty) return;

  final jointWorldTransforms = <Matrix4>[
    for (final id in skeleton.joints) worldTransformOf(project, id),
  ];
  final posedPositions = _posedPositions(mesh, skeleton, jointWorldTransforms);

  final touched = <int>{};

  mesh.beginStep();
  for (final sample in samples) {
    if (sample.radius <= 0) continue;
    for (final entry in posedPositions.entries) {
      final v = entry.key;
      final distance = (entry.value - sample.center).length;
      if (distance > sample.radius) continue;

      if (mode == PaintWeightsMode.assign) {
        assignSelection(mesh, <int>[v], localJoint, strength);
      } else {
        final falloff = 1.0 - (distance / sample.radius);
        paintWeight(mesh, v, localJoint, strength * falloff);
      }
      touched.add(v);
    }
  }
  if (mirror != null && touched.isNotEmpty) {
    // Every live vertex, not just [touched]: `mirrorWeights` finds each
    // vertex's own mirror image by searching within whatever list it is
    // given, and a touched vertex's partner is not itself touched by a
    // stroke on only one side of the mesh — passing [touched] alone would
    // leave a stroke on the left hand finding no right hand to copy onto.
    final everyVertex = <int>[
      for (var v = 0; v < mesh.vertexSlotCount; v++)
        if (mesh.isVertexAlive(v)) v,
    ];
    mirrorWeights(
      mesh,
      everyVertex,
      axis: mirror.axis,
      jointMirror: mirror.jointMirror,
      plane: mirror.plane,
      tolerance: mirror.tolerance,
    );
  }
  if (normalize) {
    for (final v in touched) {
      if (maxInfluences != null) {
        pruneVertexWeights(mesh, v, maxInfluences);
      } else {
        normalizeVertexWeights(mesh, v);
      }
    }
  }
  mesh.endStep();
}

/// A weight-paint brush stroke, as one undo step — `anim-10`'s own row,
/// closed exactly as its own wording promised: "a stroke is one Cmd-Z."
///
/// See this library's own doc comment for [paintWeights], the low-level
/// brush this runs inside one journal step, and for what [normalize] and
/// [maxInfluences] do together once the stroke itself is painted.
final class PaintWeights extends ModelCommand {
  const PaintWeights({
    required this.objectId,
    required this.skeletonIndex,
    required this.joint,
    required this.samples,
    required this.strength,
    this.mode = PaintWeightsMode.paint,
    this.mirror,
    this.normalize = true,
    this.maxInfluences,
  });

  /// The object with the mesh a stroke paints onto.
  final int objectId;

  final int skeletonIndex;

  /// [ModelObject.id] of the joint this stroke paints — [skeletonIndex]'s
  /// own joint, not the mesh's local, vertex-attribute-slot index.
  final int joint;

  final List<BrushSample> samples;
  final double strength;
  final PaintWeightsMode mode;
  final PaintMirror? mirror;

  /// Whether every vertex the stroke touched is pruned to [maxInfluences]
  /// and renormalized once painting (and mirroring) is done. True by
  /// default — a real stroke wants the profile's own budget kept, not left
  /// to whatever an export-time check catches later.
  final bool normalize;

  /// The cap [normalize] prunes to, or [ProfileBudget.maxInfluences] when
  /// this is left null — "a limit from the profile," the row's own words.
  final int? maxInfluences;

  @override
  String get name => 'paintWeights';

  @override
  String get says => 'paint weights';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'objectId': objectId,
    'skeletonIndex': skeletonIndex,
    'joint': joint,
    'samples': <Object?>[for (final BrushSample s in samples) s.toJson()],
    'strength': strength,
    'mode': mode.name,
    if (mirror != null) 'mirror': mirror!.toJson(),
    'normalize': normalize,
    if (maxInfluences != null) 'maxInfluences': maxInfluences,
  };

  @override
  Map<String, ParamHint> get hints => const <String, ParamHint>{
    'strength': DoubleHint(min: 0, max: 1, step: 0.05),
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final object = project[objectId];
    if (object == null) return Outcome.refused('there is no object $objectId');
    final EditedGeometry? edited = switch (object.geometry) {
      final EditedGeometry it => it,
      _ => null,
    };
    if (edited == null) {
      return Outcome.refused(
        '"${object.name}" has no mesh to paint weights on — bake it to a '
        'mesh first',
      );
    }
    final (:skeleton, :refused) = _skeletonTarget(project, skeletonIndex);
    if (skeleton == null) return Outcome.refused(refused!);
    if (!skeleton.joints.contains(joint)) {
      return Outcome.refused(
        'object $joint is not a joint of skeleton $skeletonIndex',
      );
    }
    if (samples.isEmpty) {
      return Outcome.refused('paintWeights needs at least one sample');
    }

    paintWeights(
      project: project,
      mesh: edited.mesh,
      skeleton: skeleton,
      joint: joint,
      samples: samples,
      strength: strength,
      mode: mode,
      mirror: mirror,
      normalize: normalize,
      maxInfluences: maxInfluences ?? project.profile.maxInfluences,
    );
    // A new `ModelObject` round the same, in-place-mutated mesh — never
    // `identical` to what [project] held, the same way every mesh command
    // in `mesh_commands.dart` rewraps through `_asMeshStep`. Two things
    // need that: a viewport reads a bumped `ModelObject.version` as "upload
    // this again," and `ModelHistory.endTransaction` reads a project
    // `identical` to its own `before` as "nothing happened" — true for
    // every other command that ever sets `meshTouched`, since each of them
    // also touches the document some other way, but not for a stroke that
    // only ever mutates the mesh in place. Without this, a hundred
    // `PaintWeights` inside one transaction would journal on the mesh for
    // real and then have `endTransaction` throw the whole step away anyway.
    return Outcome.done(
      project.withObject(
        object.copyWith(geometry: EditedGeometry(edited.mesh)),
      ),
      meshTouched: edited.mesh,
    );
  }
}

/// Every [BrushSample.fromJson] in [json], or null on the first one that does
/// not read back — the same "no half-built command" rule every other reader
/// in `command.dart` keeps.
List<BrushSample>? _brushSamplesFrom(List<Object?> json) {
  final out = <BrushSample>[];
  for (final Object? each in json) {
    final sample = BrushSample.fromJson(each);
    if (sample == null) return null;
    out.add(sample);
  }
  return out;
}

/// The mirror [json] describes: `(null, true)` when [json] is null — a
/// stroke with no mirror, the ordinary case — `(mirror, true)` when it reads
/// back, or `(null, false)` when it does not. The `bool` is what lets the
/// caller tell "no mirror" apart from "an unreadable one," which a plain
/// nullable return cannot.
(PaintMirror?, bool) _paintMirrorFrom(Object? json) {
  if (json == null) return (null, true);
  final mirror = PaintMirror.fromJson(json);
  return (mirror, mirror != null);
}
