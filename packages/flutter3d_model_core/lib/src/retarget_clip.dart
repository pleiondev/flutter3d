/// A project's own clips, retargeted through the rig algorithms in `rig/` —
/// the adapter that lets retargeting know nothing about a project.
///
/// **The document depends on the algorithm, not the other way round.** The
/// files under `rig/` read a rig as nodes and tracks; this file is the one
/// place a [ModelProject]'s objects, skeletons and clips are turned into those
/// and back. They were a package of their own once, and that package imported
/// this one for `ModelProject`, so `RigJob` had to be split across the two to
/// dodge the cycle.
library;

import 'project.dart';
import 'project_animation.dart';
import 'rig/bone_map.dart' show BoneMap;
import 'rig/retarget.dart' show RetargetRig, RigNode, RigTrack, retargetTracks;

/// [skeleton] in [project] as the rig algorithms read a rig: every joint, every
/// object a joint hangs from, and every object in [alsoNodes] — the objects a
/// clip's own tracks move, which a bone map may name whether or not they are
/// joints.
RetargetRig retargetRigOf(
  ModelProject project,
  ProjectSkeleton skeleton, {
  Iterable<int> alsoNodes = const <int>[],
}) {
  final nodes = <int, RigNode>{};
  // Up the parents until a node already taken or the root, so a chain many
  // joints share is read once. A walk, so `id` is the state it walks with.
  void take(int? id) {
    while (id != null && !nodes.containsKey(id)) {
      final ModelObject? object = project[id];
      if (object == null) return;
      nodes[id] = RigNode(
        id: object.id,
        name: object.name,
        restLocal: object.transform,
        parent: object.parent,
      );
      id = object.parent;
    }
  }

  skeleton.joints.forEach(take);
  alsoNodes.forEach(take);
  return RetargetRig(nodes: nodes.values, joints: skeleton.joints);
}

/// Retargets [sourceClip] — a clip whose tracks address [sourceSkeleton]'s own
/// joints in [sourceProject] — onto [targetSkeleton]'s joints in
/// [targetProject], through [boneMap].
///
/// `anim-17`'s own row: `retargetTracks` (in `rig/`) does the work and
/// says how — rest-relative rotations, height-scaled translations, a two-bone
/// foot lock under [lockFeet] — and this reads the two skeletons out of their
/// projects and puts the answer back into a [ProjectClip] under the source
/// clip's own name and extras.
ProjectClip retargetClip({
  required ProjectClip sourceClip,
  required ModelProject sourceProject,
  required ProjectSkeleton sourceSkeleton,
  required ModelProject targetProject,
  required ProjectSkeleton targetSkeleton,
  required BoneMap boneMap,
  bool lockFeet = true,
  double groundY = 0.0,
  double footTolerance = 1e-3,
}) {
  final List<RigTrack> retargeted = retargetTracks(
    tracks: <RigTrack>[
      for (final ProjectTrack track in sourceClip.tracks)
        RigTrack(nodeId: track.objectId, track: track.track),
    ],
    source: retargetRigOf(
      sourceProject,
      sourceSkeleton,
      alsoNodes: <int>[
        for (final ProjectTrack track in sourceClip.tracks) track.objectId,
      ],
    ),
    target: retargetRigOf(targetProject, targetSkeleton),
    boneMap: boneMap,
    lockFeet: lockFeet,
    groundY: groundY,
    footTolerance: footTolerance,
  );
  return ProjectClip(
    name: sourceClip.name,
    tracks: <ProjectTrack>[
      for (final RigTrack track in retargeted)
        ProjectTrack(objectId: track.nodeId, track: track.track),
    ],
    extras: sourceClip.extras,
  );
}
