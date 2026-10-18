/// `RigJob`: the rig-baking operations, run through the same request/result
/// shape `job.dart`'s own `JobRequest` established — `anim-25`'s own row, the
/// `core` half its cross-reference note calls "state of jobs, result as a
/// command" (`doc/model-editor-plan.md`, the `anim-25` line under
/// "перекрёстные ссылки").
///
/// **All five in one place.** `bindWeights` and `retargetTracks` are the rig
/// algorithms in `rig/`, so their job kinds sit here beside `bakeIk`,
/// `bakeShapeDrivers` and `bakeRootMotion`, applied through the very same
/// [ApplyClipResult]/[ApplyJobResult] commands. They used to live in a package
/// of their own, which imported this one for `ModelProject`, so a job kind
/// here could not import the algorithm back without a cycle; the algorithms
/// read a rig as nodes and tracks now, and live in this package.
///
/// **No isolate crossing for the clip bakes, unlike [JobRequest]'s own
/// `editInIsolate`.** [JobRequest] crosses because a mesh bake is a per-vertex
/// cost that can run to real time over a mesh with real geometry; [bakeIk],
/// [bakeShapeDrivers], [retargetClip] and [ExtractRootMotion]'s own extraction
/// are each `O(keyframe count)` — hundreds, not hundreds of thousands — the
/// same size class `texture_bake.dart`'s own `bakeTextureGraph` (chunked, not
/// isolated) already draws its own line at, one function away from that file's
/// `bakeTextureFull` (isolated, for the size class that needs it). `run()`
/// still returns a `Future`, so a caller's own `Job` (`ui-25`) wraps it in
/// exactly the same one-opaque-chunk shape [JobRequest.run] already uses.
/// [BindWeightsJobRequest] is the one rig bake that does cross: it is
/// per-vertex.
library;

import 'dart:typed_data';

import 'package:flutter3d_mesh/flutter3d_mesh.dart'
    show EditMesh, editInIsolate, toVertexAttributes;
import 'package:vector_math/vector_math.dart' show Vector3;

import 'command.dart';
import 'ik_constraint.dart';
import 'job.dart';
import 'project.dart';
import 'project_animation.dart';
import 'retarget_clip.dart';
import 'rig/bind_weights.dart'
    show
        BoneSegment,
        bindWeights,
        maxSkinInfluences,
        normalizeSkinWeights,
        pruneSkinWeights;
import 'rig/bone_map.dart' show BoneMap;
import 'shape_driver.dart';

/// `bakeIk` (`anim-15`'s own row) through the job/runner shape `anim-25`
/// asks every rig bake to share.
///
/// [project] and [clip] are plain, already-immutable values — a
/// [ModelProject] is "replaced rather than mutated" by its own class
/// comment, so holding one here carries none of the risk `JobRequest`'s own
/// [meshBytes] conversion exists to avoid for the very different, journal-
/// mutable [EditMesh].
final class BakeIkJobRequest {
  /// A request baking [constraint] into [clip], clip [clipIndex] of [project],
  /// at [fps] frames per second.
  const BakeIkJobRequest({
    required this.project,
    required this.clipIndex,
    required this.clip,
    required this.constraint,
    required this.fps,
  });

  /// The project the clip's joints are read from, as it was when the request
  /// was built.
  final ModelProject project;

  /// Which of [project]'s own clips [clip] was read from — where
  /// [ApplyClipResult] writes the answer back.
  final int clipIndex;

  /// The clip baked, as it was read from [project].
  final ProjectClip clip;

  /// The two-bone constraint whose solution replaces the root and middle
  /// joints' rotation tracks.
  final IkConstraint constraint;

  /// In frames per second.
  final double fps;

  /// Returns [clip] with the constraint baked in, sampled every `1/fps`
  /// seconds.
  Future<ProjectClip> run() async =>
      bakeIk(project: project, clip: clip, constraint: constraint, fps: fps);
}

/// [project]'s own clip [clipIndex], captured alongside [constraint] and
/// [fps] as a [BakeIkJobRequest] — null when [clipIndex] names no clip.
BakeIkJobRequest? bakeIkJobRequestFor(
  ModelProject project,
  int clipIndex,
  IkConstraint constraint, {
  required double fps,
}) {
  if (clipIndex < 0 || clipIndex >= project.clips.length) return null;
  return BakeIkJobRequest(
    project: project,
    clipIndex: clipIndex,
    clip: project.clips[clipIndex],
    constraint: constraint,
    fps: fps,
  );
}

/// `bakeShapeDrivers` (`anim-20`'s own row) through the same job shape.
final class BakeDriversJobRequest {
  /// A request baking [drivers] into [clip], clip [clipIndex], as a weights
  /// track of [shapeCount] components on object [shapeTargetObjectId].
  const BakeDriversJobRequest({
    required this.clipIndex,
    required this.clip,
    required this.drivers,
    required this.shapeTargetObjectId,
    required this.shapeCount,
  });

  /// Index of the clip in [ModelProject.clips], where [ApplyClipResult] writes
  /// the answer back.
  final int clipIndex;

  /// The clip baked, as it was read from the project.
  final ProjectClip clip;

  /// The drivers whose combined output becomes the weights track.
  final List<ShapeDriver> drivers;

  /// [ModelObject.id] of the object whose shape keys the drivers set; the baked
  /// track drives it.
  final int shapeTargetObjectId;

  /// How many shape keys the target object has, the width of the weights track;
  /// a driver naming a key past it is skipped.
  final int shapeCount;

  /// Returns [clip] with one weights track added, or [clip] unchanged when no
  /// driver names a joint the clip animates.
  Future<ProjectClip> run() async => bakeShapeDrivers(
    clip: clip,
    drivers: drivers,
    shapeTargetObjectId: shapeTargetObjectId,
    shapeCount: shapeCount,
  );
}

/// [project]'s own clip [clipIndex], captured alongside [drivers] as a
/// [BakeDriversJobRequest] — null when [clipIndex] names no clip.
///
/// [drivers] falls back to [shapeTargetObjectId]'s own persisted
/// [ModelObject.shapeDrivers] when it is null — `anim-34d`'s own row — so a
/// caller that has not looked one up itself still bakes whatever a person
/// already built through [AddShapeDriver] rather than baking nothing. Pass
/// an explicit list, even an empty one, to bake against something other
/// than what the object currently holds.
BakeDriversJobRequest? bakeDriversJobRequestFor(
  ModelProject project,
  int clipIndex,
  List<ShapeDriver>? drivers,
  int shapeTargetObjectId,
  int shapeCount,
) {
  if (clipIndex < 0 || clipIndex >= project.clips.length) return null;
  return BakeDriversJobRequest(
    clipIndex: clipIndex,
    clip: project.clips[clipIndex],
    drivers:
        drivers ??
        project[shapeTargetObjectId]?.shapeDrivers ??
        const <ShapeDriver>[],
    shapeTargetObjectId: shapeTargetObjectId,
    shapeCount: shapeCount,
  );
}

/// `ExtractRootMotion` (`anim-16`'s own row) through the same job shape —
/// see this library's own doc comment for why there is nothing for [run] to
/// compute ahead of time: extraction is already a single cheap,
/// synchronous [ModelCommand]. This exists so `bakeRootMotion` has the same
/// request/run/apply shape its four siblings do; the "job" is the command
/// itself, handed back rather than built fresh by whoever applies it.
final class BakeRootMotionJobRequest {
  /// A request extracting the root motion of [rootJoint] in clip [clipIndex].
  const BakeRootMotionJobRequest({
    required this.clipIndex,
    required this.rootJoint,
  });

  /// Index of the clip in [ModelProject.clips].
  final int clipIndex;

  /// Object id of the joint whose translation track carries the root motion.
  final int rootJoint;

  /// Returns the [ExtractRootMotion] command; there is nothing to compute ahead
  /// of applying it.
  Future<ExtractRootMotion> run() async =>
      ExtractRootMotion(clipIndex: clipIndex, rootJoint: rootJoint);
}

/// [retargetClip] (`anim-17`'s own row) through the same job shape — answers
/// with a [ProjectClip], which a caller applies through `ApplyClipResult(clip:
/// result)` (append — a retarget always lands as a new clip on the target
/// project, never a replacement of the source it read).
final class RetargetClipJobRequest {
  /// A request retargeting [sourceClip] from [sourceSkeleton] onto
  /// [targetSkeleton] through [boneMap], locking the feet to height nought
  /// within a millimetre unless given.
  const RetargetClipJobRequest({
    required this.sourceProject,
    required this.sourceSkeleton,
    required this.sourceClip,
    required this.targetProject,
    required this.targetSkeleton,
    required this.boneMap,
    this.lockFeet = true,
    this.groundY = 0.0,
    this.footTolerance = 1e-3,
  });

  /// The project the source clip and skeleton come from.
  final ModelProject sourceProject;

  /// The skeleton the source clip animates.
  final ProjectSkeleton sourceSkeleton;

  /// The clip retargeted.
  final ProjectClip sourceClip;

  /// The project the retargeted clip is built for.
  final ModelProject targetProject;

  /// The skeleton the retargeted clip animates.
  final ProjectSkeleton targetSkeleton;

  /// Which source bone drives which target bone; a source bone it does not map
  /// is dropped.
  final BoneMap boneMap;

  /// Whether each humanoid foot is snapped back to [groundY] by two-bone IK
  /// after retargeting. True by default.
  final bool lockFeet;

  /// In metres.
  final double groundY;

  /// In metres.
  final double footTolerance;

  /// Returns the retargeted clip, for [ApplyClipResult] to append.
  Future<ProjectClip> run() async => retargetClip(
    sourceClip: sourceClip,
    sourceProject: sourceProject,
    sourceSkeleton: sourceSkeleton,
    targetProject: targetProject,
    targetSkeleton: targetSkeleton,
    boneMap: boneMap,
    lockFeet: lockFeet,
    groundY: groundY,
    footTolerance: footTolerance,
  );
}

/// [sourceProject]'s own skeleton [sourceSkeletonIndex] and clip
/// [sourceClipIndex], retargeted onto [targetProject]'s own skeleton
/// [targetSkeletonIndex] through [boneMap] — captured as a
/// [RetargetClipJobRequest], or null when any of the three indices names
/// nothing.
RetargetClipJobRequest? retargetClipJobRequestFor({
  required ModelProject sourceProject,
  required int sourceSkeletonIndex,
  required int sourceClipIndex,
  required ModelProject targetProject,
  required int targetSkeletonIndex,
  required BoneMap boneMap,
  bool lockFeet = true,

  /// In metres.
  double groundY = 0.0,

  /// In metres.
  double footTolerance = 1e-3,
}) {
  if (sourceSkeletonIndex < 0 ||
      sourceSkeletonIndex >= sourceProject.skeletons.length) {
    return null;
  }
  if (sourceClipIndex < 0 || sourceClipIndex >= sourceProject.clips.length) {
    return null;
  }
  if (targetSkeletonIndex < 0 ||
      targetSkeletonIndex >= targetProject.skeletons.length) {
    return null;
  }
  return RetargetClipJobRequest(
    sourceProject: sourceProject,
    sourceSkeleton: sourceProject.skeletons[sourceSkeletonIndex],
    sourceClip: sourceProject.clips[sourceClipIndex],
    targetProject: targetProject,
    targetSkeleton: targetProject.skeletons[targetSkeletonIndex],
    boneMap: boneMap,
    lockFeet: lockFeet,
    groundY: groundY,
    footTolerance: footTolerance,
  );
}

/// `bindWeights` (`anim-22`'s own row) through the job/runner shape — the one
/// rig bake that crosses an isolate the way [JobRequest] does: `bindWeights`
/// is `O(vertex count × bone count)`, the same per-vertex size class
/// [JobRequest]'s own [meshBytes] conversion exists for, not the `O(keyframe
/// count)` size class the clip bakes above are.
///
/// [meshBytes] is [EditMesh.toBytes] at the moment this was built, the same
/// value type [JobRequest] itself carries across for the same reason.
/// [bones] answers [BoneSegment] per bone, in the local index a skin weight's
/// joint already means everywhere else in this engine — a caller builds it
/// from whatever it has (a skeleton's own joint world transforms, an authored
/// rig, a test fixture); nothing here derives it, the same way
/// [RetargetClipJobRequest] takes an already-built [BoneMap] rather than
/// inferring one.
///
/// [run] chains the same three passes the plan calls the "ordinary
/// pipeline" — raw [bindWeights], then [pruneSkinWeights], then
/// [normalizeSkinWeights] — and writes the result into the mesh through
/// [EditMesh.setSkin]/`toVertexAttributes`, one journal step for the whole
/// mesh rather than one per vertex.
final class BindWeightsJobRequest {
  /// A request binding [bones] to [meshBytes] for object [objectId] at version
  /// [baseVersion]: inverse-square falloff with visibility, at most
  /// [maxSkinInfluences] influences, unless given.
  const BindWeightsJobRequest({
    required this.objectId,
    required this.baseVersion,
    required this.meshBytes,
    required this.bones,
    this.falloffPower = 2.0,
    this.useVisibility = true,
    this.epsilon = 1e-4,
    this.maxInfluences = maxSkinInfluences,
    this.pruneThreshold = 1e-3,
  });

  /// Which object this answers for.
  final int objectId;

  /// [ModelObject.version] at the moment this was built — the same refusal
  /// [ApplyJobResult] already gives [JobRequest]'s own result when
  /// something else changed the object while this ran.
  final int baseVersion;

  /// The base mesh, as [EditMesh.toBytes] wrote it when this was built.
  final Uint8List meshBytes;

  /// The bones weighed against, one [BoneSegment] per skin joint in local joint
  /// order.
  final List<BoneSegment> bones;

  /// A unitless exponent on distance.
  final double falloffPower;

  /// Whether a bone the vertex has no line of sight to is dropped, tested
  /// against the mesh's own triangles. True by default.
  final bool useVisibility;

  /// In metres, added to every distance.
  final double epsilon;

  /// Most influences a vertex keeps after pruning, a count; [maxSkinInfluences]
  /// by default.
  final int maxInfluences;

  /// Compared with the raw weight, 1 / (distance in metres + [epsilon]) to the
  /// power [falloffPower].
  final double pruneThreshold;

  /// Binds [bones] to [meshBytes], off this isolate when one is available.
  Future<JobResult> run() async {
    final base = EditMesh.fromBytes(meshBytes);
    final bound = await editInIsolate(base, (EditMesh mesh) {
      final positions = <Vector3>[
        for (var v = 0; v < mesh.vertexSlotCount; v++)
          mesh.isVertexAlive(v) ? mesh.positionOf(v) : Vector3.zero(),
      ];
      final triangles = _triangulate(mesh);
      final normalized = normalizeSkinWeights(
        pruneSkinWeights(
          bindWeights(
            positions: positions,
            triangles: triangles,
            bones: bones,
            falloffPower: falloffPower,
            useVisibility: useVisibility,
            epsilon: epsilon,
          ),
          maxInfluences: maxInfluences,
          threshold: pruneThreshold,
        ),
      );
      mesh.beginStep();
      for (final entry in normalized.entries) {
        if (!mesh.isVertexAlive(entry.key)) continue;
        mesh.setSkin(entry.key, toVertexAttributes(entry.value));
      }
      mesh.endStep();
      return mesh;
    });
    return JobResult(
      objectId: objectId,
      baseVersion: baseVersion,
      meshBytes: bound.toBytes(),
    );
  }
}

/// [mesh]'s own live faces, fan-triangulated into flat vertex-index
/// triples — the same "n − 2" convention [EditedGeometry.triangleCount]
/// documents, needed here because [bindWeights]'s own visibility test
/// walks a triangle BVH, not [EditMesh]'s n-gons.
List<int> _triangulate(EditMesh mesh) => <int>[
  for (var face = 0; face < mesh.faceSlotCount; face++)
    if (mesh.isFaceAlive(face)) ..._fan(mesh.verticesOf(face)),
];

/// [loop] as a fan of triangles around its first corner.
List<int> _fan(List<int> loop) => <int>[
  for (var i = 1; i < loop.length - 1; i++) ...<int>[
    loop[0],
    loop[i],
    loop[i + 1],
  ],
];

/// [project]'s own object [objectId], bound to [bones] as a
/// [BindWeightsJobRequest] — null when [objectId] names no object, or the
/// object has no edited mesh to bind into.
BindWeightsJobRequest? bindWeightsJobRequestFor({
  required ModelProject project,
  required int objectId,
  required List<BoneSegment> bones,

  /// A unitless exponent on distance.
  double falloffPower = 2.0,
  bool useVisibility = true,

  /// In metres, added to every distance.
  double epsilon = 1e-4,
  int maxInfluences = maxSkinInfluences,

  /// Compared with the raw weight, 1 / (distance in metres + [epsilon]) to the
  /// power [falloffPower].
  double pruneThreshold = 1e-3,
}) {
  final object = project[objectId];
  if (object == null) return null;
  final EditMesh? base = switch (object.geometry) {
    final EditedGeometry g => g.mesh,
    _ => null,
  };
  if (base == null) return null;
  return BindWeightsJobRequest(
    objectId: objectId,
    baseVersion: object.version,
    meshBytes: base.toBytes(),
    bones: bones,
    falloffPower: falloffPower,
    useVisibility: useVisibility,
    epsilon: epsilon,
    maxInfluences: maxInfluences,
    pruneThreshold: pruneThreshold,
  );
}
