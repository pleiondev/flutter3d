/// `RigJob`: the three rig-baking operations whose underlying functions
/// already live in this package, run through the same request/result shape
/// `job.dart`'s own `JobRequest` established — `anim-25`'s own row, the
/// `core` half its cross-reference note calls "state of jobs, result as a
/// command" (`doc/model-editor-plan.md`, the `anim-25` line under
/// "перекрёстные ссылки").
///
/// **Two of the five named operations are not here.** `bindWeights` and
/// `retargetClip` live in `flutter3d_rig`, not this package — and cannot
/// live here: `flutter3d_rig` depends on `flutter3d_model_core`, not the
/// other way around, so a file in *this* package cannot import either
/// function without a dependency cycle. `flutter3d_rig/lib/src/rig_job.dart`
/// holds their own job kinds, built the same way as these three and applied
/// through the very same [ApplyClipResult]/[ApplyJobResult] commands this
/// package exports — the split is a package boundary, not a different
/// design.
///
/// **No isolate crossing here, unlike [JobRequest]'s own `editInIsolate`.**
/// [JobRequest] crosses because a mesh bake is a per-vertex cost that can
/// run to real time over a mesh with real geometry; [bakeIk], [bakeShapeDrivers]
/// and [ExtractRootMotion]'s own extraction are each `O(keyframe count)` —
/// hundreds, not hundreds of thousands — the same size class
/// `texture_bake.dart`'s own `bakeTextureGraph` (chunked, not isolated)
/// already draws its own line at, one function away from that file's
/// `bakeTextureFull` (isolated, for the size class that needs it). `run()`
/// still returns a `Future`, so a caller's own `Job` (`ui-25`) wraps it in
/// exactly the same one-opaque-chunk shape [JobRequest.run] already uses.
library;

import 'command.dart';
import 'ik_constraint.dart';
import 'project.dart';
import 'project_animation.dart';
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
