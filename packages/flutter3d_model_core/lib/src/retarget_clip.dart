/// A project's own clips, retargeted through `flutter3d_rig` — the adapter
/// that lets retargeting know nothing about a project.
///
/// **The document depends on the algorithm, not the other way round.**
/// `flutter3d_rig` reads a rig as nodes and tracks; this file is the one place
/// a [ModelProject]'s objects, skeletons and clips are turned into those and
/// back. Before it, the rig package imported this one for `ModelProject`, and
/// `RigJob` had to be split across the two packages to dodge the cycle.
library;

import 'package:flutter3d_rig/flutter3d_rig.dart'
    show BoneMap, RetargetRig, RigNode, RigTrack, retargetTracks;

import 'project.dart';
import 'project_animation.dart';

/// [skeleton] in [project] as `flutter3d_rig` reads a rig: every joint, every
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
/// `anim-17`'s own row: `flutter3d_rig`'s `retargetTracks` does the work and
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
