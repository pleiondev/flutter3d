/// `RigJob`: the rig-baking operations, run through the same request/result
/// shape `job.dart`'s own `JobRequest` established — `anim-25`'s own row, the
/// `core` half its cross-reference note calls "state of jobs, result as a
/// command" (`doc/model-editor-plan.md`, the `anim-25` line under
/// "перекрёстные ссылки").
///
/// **All five in one place.** `bindWeights` and `retargetTracks` are
/// `flutter3d_rig`'s algorithms and this package depends on that one, so their
/// job kinds sit here beside `bakeIk`, `bakeShapeDrivers` and `bakeRootMotion`,
/// applied through the very same [ApplyClipResult]/[ApplyJobResult] commands.
/// They used to live in `flutter3d_rig`, because that package imported this
/// one for `ModelProject` and a job kind here could not import the algorithm
/// back without a cycle; `flutter3d_rig` reads a rig as nodes and tracks now,
/// and the split had nothing left to protect.
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
import 'package:flutter3d_rig/flutter3d_rig.dart'
    show
        BoneMap,
        BoneSegment,
        bindWeights,
        kMaxSkinInfluences,
        normalizeSkinWeights,
        pruneSkinWeights;
import 'package:vector_math/vector_math.dart' show Vector3;

import 'command.dart';
import 'ik_constraint.dart';
import 'job.dart';
import 'project.dart';
import 'project_animation.dart';
import 'retarget_clip.dart';
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
  const BakeIkJobRequest({
    required this.project,
    required this.clipIndex,
    required this.clip,
    required this.constraint,
    required this.fps,
  });

  final ModelProject project;

  /// Which of [project]'s own clips [clip] was read from — where
  /// [ApplyClipResult] writes the answer back.
  final int clipIndex;

  final ProjectClip clip;
  final IkConstraint constraint;
  final double fps;

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
  const BakeDriversJobRequest({
    required this.clipIndex,
    required this.clip,
    required this.drivers,
    required this.shapeTargetObjectId,
    required this.shapeCount,
  });

  final int clipIndex;
  final ProjectClip clip;
  final List<ShapeDriver> drivers;
  final int shapeTargetObjectId;
  final int shapeCount;

  Future<ProjectClip> run() async => bakeShapeDrivers(
    clip: clip,
    drivers: drivers,
    shapeTargetObjectId: shapeTargetObjectId,
    shapeCount: shapeCount,
  );
}

/// [project]'s own clip [clipIndex], captured alongside [drivers] as a
/// [BakeDriversJobRequest] — null when [clipIndex] names no clip.
BakeDriversJobRequest? bakeDriversJobRequestFor(
  ModelProject project,
  int clipIndex,
  List<ShapeDriver> drivers,
  int shapeTargetObjectId,
  int shapeCount,
) {
  if (clipIndex < 0 || clipIndex >= project.clips.length) return null;
  return BakeDriversJobRequest(
    clipIndex: clipIndex,
    clip: project.clips[clipIndex],
    drivers: drivers,
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
  const BakeRootMotionJobRequest({
    required this.clipIndex,
    required this.rootJoint,
  });

  final int clipIndex;
  final int rootJoint;

  Future<ExtractRootMotion> run() async =>
      ExtractRootMotion(clipIndex: clipIndex, rootJoint: rootJoint);
}

/// [retargetClip] (`anim-17`'s own row) through the same job shape — answers
/// with a [ProjectClip], which a caller applies through `ApplyClipResult(clip:
/// result)` (append — a retarget always lands as a new clip on the target
/// project, never a replacement of the source it read).
final class RetargetClipJobRequest {
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

  final ModelProject sourceProject;
  final ProjectSkeleton sourceSkeleton;
  final ProjectClip sourceClip;
  final ModelProject targetProject;
  final ProjectSkeleton targetSkeleton;
  final BoneMap boneMap;
  final bool lockFeet;
  final double groundY;
  final double footTolerance;

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
  double groundY = 0.0,
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
  const BindWeightsJobRequest({
    required this.objectId,
    required this.baseVersion,
    required this.meshBytes,
    required this.bones,
    this.falloffPower = 2.0,
    this.useVisibility = true,
    this.epsilon = 1e-4,
    this.maxInfluences = kMaxSkinInfluences,
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

  final List<BoneSegment> bones;
  final double falloffPower;
  final bool useVisibility;
  final double epsilon;
  final int maxInfluences;
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
  double falloffPower = 2.0,
  bool useVisibility = true,
  double epsilon = 1e-4,
  int maxInfluences = kMaxSkinInfluences,
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
