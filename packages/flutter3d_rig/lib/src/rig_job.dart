/// `anim-25`'s own `RetargetClipJobRequest` — the one `RigJob` kind that has
/// to live in this package rather than in `flutter3d_model_core`, since
/// `retargetClip` is a `flutter3d_rig` function and `flutter3d_model_core`
/// cannot import it without a dependency cycle (this package already
/// depends on that one, not the other way around). See
/// `flutter3d_model_core/lib/src/rig_job.dart` for the other three kinds
/// (`bakeIk`, `bakeDrivers`, `bakeRootMotion`), which need no such split.
///
/// `bindWeights`'s own job kind, [BindWeightsJobRequest] below — landed as
/// the follow-up this library's own history names: `anim-22` (this
/// package's real `bindWeights`) and `anim-25` (this file) first landed from
/// two independent worktrees at the same time, against two different
/// assumed shapes for the same function, and reconciling them needed
/// `EditMesh`'s own per-vertex write path (`EditMesh.setSkin`/
/// `weight_ops.dart`'s `toVertexAttributes`), which neither draft used.
library;

import 'dart:typed_data';

import 'package:flutter3d_mesh/flutter3d_mesh.dart'
    show EditMesh, editInIsolate, toVertexAttributes;
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

import 'bind_weights.dart';
import 'bone_map.dart';
import 'retarget.dart';

/// `retargetClip` (`anim-17`'s own row) through the same job shape —
/// answers with a [ProjectClip], which a caller applies through
/// `flutter3d_model_core`'s own `ApplyClipResult(clip: result)` (append —
/// a retarget always lands as a new clip on the target project, never a
/// replacement of the source it read).
///
/// **Runs on the calling isolate, unlike `flutter3d_model_core`'s own
/// mesh-bearing job kinds.** [ModelProject] is a plain, already-immutable
/// value (its own class comment: "replaced rather than mutated"), so
/// holding [sourceProject]/[targetProject] here carries none of the risk
/// the byte conversion exists to avoid for the very different,
/// journal-mutable `EditMesh`, and a clip's own tracks are orders of
/// magnitude smaller than a mesh's own vertices — the same size distinction
/// `flutter3d_model_core`'s own `rig_job.dart` draws for its three kinds.
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

/// `bindWeights` (`anim-22`'s own row) through the job/runner shape
/// `anim-25` asks every rig bake to share — the one kind of the five that
/// crosses an isolate the way `flutter3d_model_core`'s own [JobRequest]
/// does, rather than running on the calling isolate the way
/// [RetargetClipJobRequest] above does: `bindWeights` is `O(vertex count ×
/// bone count)`, the same per-vertex size class [JobRequest]'s own
/// [meshBytes] conversion exists for, not the `O(keyframe count)` size
/// class this file's clip bakes are.
///
/// [meshBytes] is [EditMesh.toBytes] at the moment this was built, the same
/// value type [JobRequest] itself carries across for the same reason.
/// [bones] answers [BoneSegment] per bone, in the local index
/// [WeightPair.joint] already means everywhere else in this engine — a
/// caller builds it from whatever it has (a skeleton's own joint world
/// transforms, an authored rig, a test fixture); nothing here derives it,
/// the same way [RetargetClipJobRequest] above takes an already-built
/// [BoneMap] rather than inferring one.
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
/// walks a [TriangleBvh] built over triangles, not [EditMesh]'s n-gons.
List<int> _triangulate(EditMesh mesh) {
  final triangles = <int>[];
  for (var face = 0; face < mesh.faceSlotCount; face++) {
    if (!mesh.isFaceAlive(face)) continue;
    final loop = mesh.verticesOf(face);
    for (var i = 1; i < loop.length - 1; i++) {
      triangles..add(loop[0])..add(loop[i])..add(loop[i + 1]);
    }
  }
  return triangles;
}

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
