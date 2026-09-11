/// What a rig has to answer for before it is trusted — `anim-13`'s own row,
/// the [ExportReadiness]-shaped counterpart for skinning and animation
/// rather than for geometry, materials and textures.
///
/// **Nothing here reimplements a check either**, the same discipline
/// [ExportReadiness] itself states: the weight math is `mesh-60`'s
/// [weightsOf], read back rather than re-derived, and a joint's own
/// transform is read straight off the [ModelObject] that is the joint —
/// there is no second copy of either.
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:vector_math/vector_math.dart';

import 'project.dart';
import 'project_animation.dart';
import 'readiness.dart';

/// Everything wrong with [project]'s skeletons and clips, measured against
/// [profile].
///
/// **What is not here.** `anim-15`'s `IkConstraint` is not built yet, so
/// there is nothing an "unbaked IK" check could read — the row names it
/// among what a rig has to answer for, and this function will grow that
/// check the day `anim-15` gives it something to look at, not before.
List<ExportIssue> rigIssues(ModelProject project, ProjectProfile profile) {
  final objectsById = <int, ModelObject>{
    for (final object in project.objects) object.id: object,
  };
  final issues = <ExportIssue>[];

  for (var i = 0; i < project.skeletons.length; i++) {
    issues.addAll(_skeletonIssues(i, project.skeletons[i], profile, objectsById));
  }

  for (final clip in project.clips) {
    for (final track in clip.tracks) {
      if (!objectsById.containsKey(track.objectId)) {
        issues.add(
          ExportIssue(
            ExportSeverity.error,
            'clip "${clip.name ?? 'unnamed'}" has a track naming object '
            '${track.objectId}, which the project does not have',
          ),
        );
      }
    }
  }

  return issues;
}

List<ExportIssue> _skeletonIssues(
  int skeletonIndex,
  ProjectSkeleton skeleton,
  ProjectProfile profile,
  Map<int, ModelObject> objectsById,
) {
  final issues = <ExportIssue>[];
  final name = skeleton.name ?? 'unnamed';

  // A skeleton over the shader's own hard cap will not build at all —
  // `Skeleton`'s own constructor throws. Over the profile's own, softer
  // budget still builds; it is the target device that will not carry it.
  if (skeleton.jointCount > 64) {
    issues.add(
      ExportIssue(
        ExportSeverity.error,
        'skeleton "$name" has ${skeleton.jointCount} joints; the shader '
        'holds 64',
      ),
    );
  } else if (skeleton.jointCount > profile.maxJoints) {
    issues.add(
      ExportIssue(
        ExportSeverity.warning,
        'skeleton "$name" has ${skeleton.jointCount} joints, over this '
        "profile's ${profile.maxJoints}",
      ),
    );
  }

  for (var i = 0; i < skeleton.jointCount; i++) {
    final joint = objectsById[skeleton.joints[i]];
    if (joint == null) continue; // an object this points at was deleted.
    final translation = Vector3.zero();
    final rotation = Quaternion.identity();
    final scale = Vector3.zero();
    joint.transform.decompose(translation, rotation, scale);
    const tolerance = 1e-4;
    if ((scale.x - scale.y).abs() > tolerance ||
        (scale.y - scale.z).abs() > tolerance) {
      issues.add(
        ExportIssue(
          ExportSeverity.warning,
          'skeleton "$name" joint "${joint.name}" has a non-uniform scale '
          '(${scale.x}, ${scale.y}, ${scale.z}); skinning treats a joint as '
          'rotation and translation only',
          object: joint,
        ),
      );
    }
  }

  final used = <int>{};
  var zeroSum = 0;
  var unnormalized = 0;
  var overInfluence = 0;
  var outOfRange = 0;

  for (final object in objectsById.values) {
    if (object.skeletonIndex != skeletonIndex) continue;
    if (object.geometry case EditedGeometry(:final EditMesh mesh)) {
      for (var v = 0; v < mesh.vertexSlotCount; v++) {
        if (!mesh.isVertexAlive(v)) continue;
        final pairs = weightsOf(mesh, v);
        if (pairs.isEmpty) {
          zeroSum++;
          continue;
        }
        final sum = pairs.fold<double>(0, (s, p) => s + p.weight);
        if ((sum - 1.0).abs() > 1e-4) unnormalized++;
        if (pairs.length > profile.maxInfluences) overInfluence++;
        for (final pair in pairs) {
          if (pair.joint < 0 || pair.joint >= skeleton.jointCount) {
            outOfRange++;
          } else {
            used.add(pair.joint);
          }
        }
      }
    }
  }

  if (zeroSum > 0) {
    issues.add(
      ExportIssue(
        ExportSeverity.warning,
        'skeleton "$name" has $zeroSum vertices with no weight at all; '
        'they will not move with the rig',
      ),
    );
  }
  if (unnormalized > 0) {
    issues.add(
      ExportIssue(
        ExportSeverity.warning,
        'skeleton "$name" has $unnormalized vertices whose weights do not '
        'sum to one',
      ),
    );
  }
  if (overInfluence > 0) {
    issues.add(
      ExportIssue(
        ExportSeverity.warning,
        'skeleton "$name" has $overInfluence vertices with more than '
        "this profile's ${profile.maxInfluences} influences",
      ),
    );
  }
  if (outOfRange > 0) {
    issues.add(
      ExportIssue(
        ExportSeverity.error,
        'skeleton "$name" has $outOfRange weights naming a joint index '
        "outside this skin's ${skeleton.jointCount} joints",
      ),
    );
  }
  final unused = skeleton.jointCount - used.length;
  if (unused > 0) {
    issues.add(
      ExportIssue(
        ExportSeverity.warning,
        'skeleton "$name" has $unused joints no vertex is weighted to',
      ),
    );
  }

  return issues;
}
