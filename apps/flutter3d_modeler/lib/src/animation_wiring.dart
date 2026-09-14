/// `S2`'s own pure helpers between the timeline widgets and the document —
/// small enough to test as plain functions rather than through a pumped
/// screen, the same reason `properties_sections.dart`'s own table is its
/// own file.
library;

import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Key;

/// [TimelinePanel.onSetKey]'s own tap — track [trackIndex] of [clip], at
/// [time] seconds — resolved into the one [PoseJoint] it means: the joint
/// and path read off the track the tap actually landed in, the frame
/// [KeyTable.frameOfTime] snaps [time] to at [fps].
///
/// Null when [trackIndex] does not name a real row — a tap the caller should
/// never see reach here, since [TimelinePanel] itself only reports a row it
/// found, but checked rather than trusted: an index a stale rebuild left
/// pointing past a track list that has since shrunk is exactly the shape of
/// bug a `RangeError` three frames later is the wrong way to discover.
PoseJoint? poseJointForSetKey({
  required ProjectClip clip,
  required int clipIndex,
  required int trackIndex,
  required double time,
  required double fps,
}) {
  if (trackIndex < 0 || trackIndex >= clip.tracks.length) return null;
  final ProjectTrack track = clip.tracks[trackIndex];
  return PoseJoint(
    joint: track.objectId,
    path: track.track.path,
    clipIndex: clipIndex,
    frame: KeyTable.frameOfTime(time, fps),
  );
}

/// The skeleton [held] rides, or null when it has none —
/// [ModelObject.skeletonIndex] into [ModelProject.skeletons], the same
/// lookup `properties_panel.dart`'s own animation section already does to
/// hand [AnimationPanel.skeleton] its value.
ProjectSkeleton? heldSkeletonOf(ModelProject project, ModelObject? held) {
  final int? index = held?.skeletonIndex;
  if (index == null || index >= project.skeletons.length) return null;
  return project.skeletons[index];
}

/// Screen 07's own status line — "Bones N · actions N · influences M per
/// vertex" — for the animation mode's [PropertiesSection.animation] pane.
/// [bones] is the held object's own skeleton size, 0 with nothing rigged
/// selected; [actions] is `project.clips.length`; [maxInfluences] is
/// `project.profile.maxInfluences`, not a literal 4 — the format's own cap
/// is a profile setting, and a status line that hard-coded today's default
/// would go on saying "4" the day a profile changed it.
String animationModeSummary({
  required int bones,
  required int actions,
  required int maxInfluences,
}) => 'Bones $bones · actions $actions · influences $maxInfluences per vertex';
