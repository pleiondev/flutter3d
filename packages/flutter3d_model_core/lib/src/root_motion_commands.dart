/// Extracting a root joint's own translation out of a clip, and baking it
/// back in — `anim-16`'s own row: a walk cycle's root moving forward every
/// frame is the right picture for "in the animation" and the wrong one for
/// "by code," where a character controller reads how far the root moved
/// each frame and drives the actual object with that instead of letting the
/// clip carry it there itself.
///
/// **What is not here.** The engine's own `AnimationPlayer.rootMotionDelta`
/// — the runtime side that reads what these commands write and hands a
/// character controller a delta each frame — is a separate, later piece;
/// these two commands are the document-side half, over `ProjectClip` alone.
part of 'command.dart';

/// The key [ExtractRootMotion]/[BakeRootMotionIntoClip] store a clip's own
/// unflattened root translation under, inside [ProjectClip.extras] — the
/// `flutter3dRootMotion` an export "by code" reads instead of baking the
/// motion into the clip itself.
const String kRootMotionExtra = 'flutter3dRootMotion';

/// The translation track for [rootJoint] on clip [clipIndex], and its own
/// index in [ProjectClip.tracks] — or the sentence to refuse with.
({int trackIndex, AnimationTrack? track, String? refused}) _rootMotionTrack(
  ModelProject project,
  int clipIndex,
  int rootJoint,
) {
  if (clipIndex < 0 || clipIndex >= project.clips.length) {
    return (
      trackIndex: -1,
      track: null,
      refused: 'there is no clip $clipIndex',
    );
  }
  final clip = project.clips[clipIndex];
  final trackIndex = clip.tracks.indexWhere(
    (ProjectTrack t) =>
        t.objectId == rootJoint && t.track.path == AnimationPath.translation,
  );
  if (trackIndex < 0) {
    return (
      trackIndex: -1,
      track: null,
      refused:
          'there is no translation track for object $rootJoint on clip '
          '$clipIndex',
    );
  }
  return (
    trackIndex: trackIndex,
    track: clip.tracks[trackIndex].track,
    refused: null,
  );
}

/// Flattens clip [clipIndex]'s own translation track for [rootJoint] to its
/// first key's own value — the root stands still — after saving every key's
/// real value under the clip's own `extras[kRootMotionExtra]`, so
/// [BakeRootMotionIntoClip] can restore them exactly.
///
/// Refused, not a no-op, when the clip already carries extracted motion:
/// extracting twice would overwrite the real motion sitting in `extras`
/// with the already-flattened values this command itself just wrote.
final class ExtractRootMotion extends ModelCommand {
  const ExtractRootMotion({required this.clipIndex, required this.rootJoint});

  final int clipIndex;
  final int rootJoint;

  @override
  String get name => 'extractRootMotion';

  @override
  String get says => 'extract root motion';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'clipIndex': clipIndex,
    'rootJoint': rootJoint,
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final (:trackIndex, :track, :refused) = _rootMotionTrack(
      project,
      clipIndex,
      rootJoint,
    );
    if (track == null) return Outcome.refused(refused!);
    final clip = project.clips[clipIndex];
    if ((clip.extras ?? const <String, Object?>{}).containsKey(
      kRootMotionExtra,
    )) {
      return Outcome.refused(
        'clip $clipIndex already has its root motion extracted',
      );
    }

    final table = KeyTable.fromAnimationTrack(track);
    if (table.keyCount == 0) {
      return Outcome.refused('the translation track has no keys to extract');
    }

    final keys = table.keys;
    final anchor = List<double>.of(keys.first.values);
    final saved = <Object?>[
      for (final key in keys) List<double>.of(key.values),
    ];
    for (final key in keys) {
      table.setKey(
        key.time,
        anchor,
        inTangent: key.inTangent,
        outTangent: key.outTangent,
      );
    }

    return Outcome.done(
      _withRootTrack(
        project,
        clipIndex,
        trackIndex,
        rootJoint,
        table,
        extra: saved,
      ),
    );
  }
}

/// Restores clip [clipIndex]'s own translation track for [rootJoint] from
/// whatever [ExtractRootMotion] last saved under `extras[kRootMotionExtra]`
/// — the exact inverse, key for key — and clears the extra once restored.
///
/// Refused when the clip carries no extracted motion at all, or when the
/// saved key count no longer matches the track's own — a track edited by a
/// keyframe command after extraction is a track this cannot honestly put
/// back together.
final class BakeRootMotionIntoClip extends ModelCommand {
  const BakeRootMotionIntoClip({
    required this.clipIndex,
    required this.rootJoint,
  });

  final int clipIndex;
  final int rootJoint;

  @override
  String get name => 'bakeRootMotionIntoClip';

  @override
  String get says => 'bake root motion back into the clip';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'clipIndex': clipIndex,
    'rootJoint': rootJoint,
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final (:trackIndex, :track, :refused) = _rootMotionTrack(
      project,
      clipIndex,
      rootJoint,
    );
    if (track == null) return Outcome.refused(refused!);

    final clip = project.clips[clipIndex];
    final saved = clip.extras?[kRootMotionExtra];
    if (saved is! List) {
      return Outcome.refused(
        'clip $clipIndex has no extracted root motion to bake back in',
      );
    }

    final table = KeyTable.fromAnimationTrack(track);
    if (saved.length != table.keyCount) {
      return Outcome.refused(
        'the saved root motion has ${saved.length} keys; the track has '
        '${table.keyCount}',
      );
    }

    final keys = table.keys;
    for (var i = 0; i < keys.length; i++) {
      final restored = _doubleListFrom(saved[i]);
      if (restored == null) {
        return Outcome.refused(
          'the saved root motion at key $i is not a list of numbers',
        );
      }
      final key = keys[i];
      table.setKey(
        key.time,
        restored,
        inTangent: key.inTangent,
        outTangent: key.outTangent,
      );
    }

    return Outcome.done(
      _withRootTrack(
        project,
        clipIndex,
        trackIndex,
        rootJoint,
        table,
        extra: null,
      ),
    );
  }
}

/// [project] with clip [clipIndex]'s own translation track for [rootJoint]
/// replaced by [table], and `extras[kRootMotionExtra]` set to [extra] — or
/// removed when [extra] is null.
ModelProject _withRootTrack(
  ModelProject project,
  int clipIndex,
  int trackIndex,
  int rootJoint,
  KeyTable table, {
  required List<Object?>? extra,
}) {
  final clip = project.clips[clipIndex];
  final newTrack = table.toAnimationTrack(
    nodeIndex: 0,
    path: AnimationPath.translation,
  );
  final tracks = List<ProjectTrack>.of(clip.tracks)
    ..[trackIndex] = ProjectTrack(objectId: rootJoint, track: newTrack);

  final extras = Map<String, Object?>.of(
    clip.extras ?? const <String, Object?>{},
  );
  if (extra == null) {
    extras.remove(kRootMotionExtra);
  } else {
    extras[kRootMotionExtra] = extra;
  }

  final clips = List<ProjectClip>.of(project.clips)
    ..[clipIndex] = ProjectClip(
      name: clip.name,
      extras: extras.isEmpty ? null : extras,
      tracks: tracks,
    );
  return project.copyWith(clips: clips);
}
