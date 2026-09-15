/// [boneSegmentsOf]: a [RetargetRig] read as [BoneSegment]s, for a caller
/// about to call [bindWeights] — `anim-33d`'s own row, screen 16's auto-rig
/// wiring `bindWeightsJobRequestFor` to whatever composition
/// `RigBuildOptions` just built.
///
/// `rig_job.dart` one directory up builds `BindWeightsJobRequest` — the
/// actual job, holding a `ModelProject`'s own mesh bytes — and this file
/// builds the one plain piece that job needs without knowing what a project
/// is: bone segments, out of a rig the algorithms under `src/rig/` already
/// read in their own vocabulary, [RetargetRig]. It stays on this side of
/// that line for the reason `retarget.dart`'s own class comment gives: "the
/// document depends on the algorithm, the algorithm depends on the
/// vocabulary of animation".
library;

import 'package:vector_math/vector_math.dart';

import 'bind_weights.dart';
import 'retarget.dart';

/// [rig]'s own [RetargetRig.joints], as [BoneSegment]s — one per joint, in
/// that same order, the same local addressing [WeightPair.joint] already
/// means everywhere in this engine (`bind_weights.dart`'s own [BoneSegment]
/// class comment). [BoneSegment.head] is a joint's own parent's world
/// position; [BoneSegment.tail] is the joint's own; [BoneSegment.name] is
/// the joint's own [RigNode.name], for [mirrorSkinWeights]' own lookup.
///
/// **A joint's own parent need not itself be one of [rig]'s own joints.**
/// [RetargetRig]'s own class comment already names why a rig carries more
/// nodes than joints — "an armature root, an empty the whole rig is
/// parented to" — and `anim-33d`'s own `RigBuildOptions.controllers` is
/// exactly that case: a socket parent `rig_template.dart`'s own
/// `buildSkeleton` hangs a template's root joint from without ever listing
/// it as a joint itself. Walking up through [rig] itself (not through
/// `rig.joints`) for a joint's own world position already reads straight
/// through a parent like that, the same way `retargetTracks`' own height
/// and foot-lock math already does; a joint with no parent at all (the
/// true root, rig controller or not) gets a degenerate, zero-length
/// segment — [BoneSegment.head] equal to its own [BoneSegment.tail] — the
/// same fallback [bindWeights]' own `_closestPointOnSegment` already
/// treats as "closest point is the point itself".
///
/// A caller with a `ModelProject` and `ProjectSkeleton` builds [rig] first
/// through `flutter3d_model_core`'s own `retargetRigOf` (`retarget_clip
/// .dart`) — the existing adapter `retargetClip` already uses for the same
/// project-to-rig step — then calls this, then hands the result to
/// `bindWeightsJobRequestFor` as its own `bones` argument.
List<BoneSegment> boneSegmentsOf(RetargetRig rig) {
  final worldCache = <int, Matrix4>{};
  Matrix4 worldOf(int id) => worldCache.putIfAbsent(id, () {
    final node = rig[id];
    if (node == null) return Matrix4.identity();
    final parentWorld = node.parent == null
        ? Matrix4.identity()
        : worldOf(node.parent!);
    return parentWorld.multiplied(node.restLocal);
  });

  return <BoneSegment>[
    for (final id in rig.joints) _segmentOf(rig, id, worldOf),
  ];
}

BoneSegment _segmentOf(RetargetRig rig, int id, Matrix4 Function(int) worldOf) {
  final node = rig[id];
  final tail = worldOf(id).getTranslation();
  final parentId = node?.parent;
  final head = parentId == null ? tail : worldOf(parentId).getTranslation();
  return BoneSegment(head, tail, name: node?.name);
}
