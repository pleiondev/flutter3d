/// The commands over one track's own [KeyTable] — `anim-04`'s own row,
/// closing the gap entry 49 left: `SetKey`, `MoveKeys`, `DeleteKeys`,
/// `SetInterpolation`, `SetTangent`, wiring the editing primitive into a
/// project's own undo stack.
///
/// **Addressed by clip index and track index, not by object id and
/// [AnimationPath].** Entry 49 left the choice open; this file takes the
/// first, for the same reason every other list-position command in this
/// package already does — [RemoveJoint] by skeleton and joint index,
/// [ReorderModifier] by slot — rather than introducing a second addressing
/// scheme only these five commands would use. A caller that only knows an
/// object and a path finds the pair by scanning [ProjectClip.tracks] once,
/// the same lookup [KeyShape] already does for its own `weights` track.
///
/// **Every command reads the whole track through [KeyTable
/// .fromAnimationTrack], mutates the table, and writes the whole track back
/// through [KeyTable.toAnimationTrack].** [KeyTable] is the cheap-to-edit
/// half of this pair and [AnimationTrack] the cheap-to-sample half; an
/// edit command is exactly the boundary where the cost of rebuilding the
/// flat array is worth paying once, per command, rather than on every frame
/// a track is sampled.
///
/// **A count that would leave a track without its own state is refused, not
/// silently applied.** [DeleteKeys] refuses rather than leave a track with
/// zero keyframes — [KeyTable.toAnimationTrack] throws for that, the same
/// way [AnimationTrack]'s own constructor does, and a caller here gets a
/// sentence instead of a crash. [SetKey]/[SetTangent] refuse a
/// `values`/`inTangent`/`outTangent` whose own length does not match the
/// track's `componentCount`, for the identical reason: past that point the
/// mismatch is a `RangeError` out of [KeyTable.toAnimationTrack] rather
/// than a sentence naming what disagreed.
part of 'command.dart';

/// The track clip [clipIndex] track [trackIndex] names, or the sentence to
/// refuse with.
({ProjectTrack? track, String? refused}) _trackTarget(
  ModelProject project,
  int clipIndex,
  int trackIndex,
) {
  if (clipIndex < 0 || clipIndex >= project.clips.length) {
    return (track: null, refused: 'there is no clip $clipIndex');
  }
  final clip = project.clips[clipIndex];
  if (trackIndex < 0 || trackIndex >= clip.tracks.length) {
    return (
      track: null,
      refused: 'clip $clipIndex has ${clip.tracks.length} tracks; $trackIndex '
          'is not one of them',
    );
  }
  return (track: clip.tracks[trackIndex], refused: null);
}

/// Every element of [json] as a double, in order, or null if [json] is not a
/// list of numbers. Unlike `command.dart`'s own `_doubles`, no fixed length
/// is asked for: a keyframe's own component count is a property of the
/// track it targets, not known until [modelCommandFromJson] has read which
/// track that is.
List<double>? _doubleListFrom(Object? json) {
  if (json is! List) return null;
  final out = <double>[];
  for (final Object? each in json) {
    if (each is! num) return null;
    out.add(each.toDouble());
  }
  return out;
}

/// The interpolation [json] names, or null when it does not match one — no
/// default, unlike `command.dart`'s own `_placement`/`_space`: every writer
/// of [SetInterpolation] names one explicitly, so an absent or unknown word
/// is a file this build cannot honestly guess at rather than an ordinary
/// omission.
AnimationInterpolation? _interpolationFrom(Object? json) =>
    AnimationInterpolation.values
        .where((AnimationInterpolation each) => each.name == json)
        .firstOrNull;

/// The [AnimationPath] [json] names, or null when it does not match one —
/// the same "no default" reasoning as [_interpolationFrom], for the same
/// reason: every writer of [PoseJoint] names one explicitly.
AnimationPath? _pathFrom(Object? json) => AnimationPath.values
    .where((AnimationPath each) => each.name == json)
    .firstOrNull;

/// [transform]'s own [path] component, decomposed from the local matrix —
/// or null for [AnimationPath.weights], which [PoseJoint] does not key; see
/// [KeyShape] for that.
List<double>? _poseComponent(Matrix4 transform, AnimationPath path) {
  if (path == AnimationPath.weights) return null;
  final translation = Vector3.zero();
  final rotation = Quaternion.identity();
  final scale = Vector3.zero();
  transform.decompose(translation, rotation, scale);
  return switch (path) {
    AnimationPath.translation => <double>[
      translation.x,
      translation.y,
      translation.z,
    ],
    AnimationPath.rotation => <double>[
      rotation.x,
      rotation.y,
      rotation.z,
      rotation.w,
    ],
    AnimationPath.scale => <double>[scale.x, scale.y, scale.z],
    AnimationPath.weights => null,
  };
}

/// Keys [joint]'s own current [path] component — translation, rotation or
/// scale, read off its live local transform rather than taken as an
/// argument — onto clip [clipIndex] at [frame]. `anim-05`'s own row: an
/// auto-key, for a gizmo drag that poses a joint and then asks the pose it
/// already reached to be remembered.
///
/// **Three calls at the same [frame], wrapped in one
/// [ModelHistory.transaction], read back as one key and one step — from two
/// mechanisms neither of which PoseJoint has to implement itself.**
/// [KeyTable.setKey] already replaces the key at a repeated time rather than
/// adding a second one, which is the "one key"; [ModelHistory.transaction]
/// already folds every command run inside it into the step the first one
/// opened, which is the "one step". A joint moved three times mid-drag with
/// [frame] unchanged between calls is exactly that shape — the last call's
/// pose is the one that survives, the same way it would if only that call
/// had ever run.
final class PoseJoint extends ModelCommand {
  const PoseJoint({
    required this.joint,
    required this.path,
    required this.clipIndex,
    required this.frame,
  });

  final int joint;
  final AnimationPath path;
  final int clipIndex;
  final int frame;

  @override
  String get name => 'poseJoint';

  @override
  String get says => 'key a joint\'s pose';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'joint': joint,
    'path': path.name,
    'clipIndex': clipIndex,
    'frame': frame,
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final object = project[joint];
    if (object == null) return Outcome.refused('there is no object $joint');
    if (clipIndex < 0 || clipIndex >= project.clips.length) {
      return Outcome.refused('there is no clip $clipIndex');
    }
    final values = _poseComponent(object.transform, path);
    if (values == null) {
      return Outcome.refused(
        'PoseJoint keys translation, rotation or scale, not ${path.name} — '
        'see KeyShape for morph weights',
      );
    }

    final clip = project.clips[clipIndex];
    final existingIndex = clip.tracks.indexWhere(
      (ProjectTrack t) => t.objectId == joint && t.track.path == path,
    );
    final table = existingIndex >= 0
        ? KeyTable.fromAnimationTrack(clip.tracks[existingIndex].track)
        : KeyTable(componentCount: values.length);
    final time = KeyTable.timeOfFrame(frame, project.profile.fps);
    table.setKey(time, values);

    final newTrack = ProjectTrack(
      objectId: joint,
      track: table.toAnimationTrack(nodeIndex: 0, path: path),
    );
    final tracks = List<ProjectTrack>.of(clip.tracks);
    if (existingIndex >= 0) {
      tracks[existingIndex] = newTrack;
    } else {
      tracks.add(newTrack);
    }
    final clips = List<ProjectClip>.of(project.clips)
      ..[clipIndex] = ProjectClip(
        name: clip.name,
        extras: clip.extras,
        tracks: tracks,
      );

    return Outcome.done(project.copyWith(clips: clips));
  }
}

/// [project], with clip [clipIndex] track [trackIndex] replaced by
/// [newTrack] — every other track and clip left exactly as they were.
ModelProject _withTrack(
  ModelProject project,
  int clipIndex,
  int trackIndex,
  AnimationTrack newTrack,
) {
  final clip = project.clips[clipIndex];
  final tracks = List<ProjectTrack>.of(clip.tracks)
    ..[trackIndex] = ProjectTrack(
      objectId: clip.tracks[trackIndex].objectId,
      track: newTrack,
    );
  final clips = List<ProjectClip>.of(project.clips)
    ..[clipIndex] = ProjectClip(name: clip.name, extras: clip.extras, tracks: tracks);
  return project.copyWith(clips: clips);
}

/// Writes (or replaces) the keyframe at [time] on clip [clipIndex] track
/// [trackIndex] — [KeyTable.setKey], wired into the undo stack.
final class SetKey extends ModelCommand {
  const SetKey({
    required this.clipIndex,
    required this.trackIndex,
    required this.time,
    required this.values,
    this.inTangent,
    this.outTangent,
  });

  final int clipIndex;
  final int trackIndex;
  final double time;
  final List<double> values;
  final List<double>? inTangent;
  final List<double>? outTangent;

  @override
  String get name => 'setKey';

  @override
  String get says => 'set a keyframe';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'clipIndex': clipIndex,
    'trackIndex': trackIndex,
    'time': time,
    'values': values,
    'inTangent': inTangent,
    'outTangent': outTangent,
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final (:track, :refused) = _trackTarget(project, clipIndex, trackIndex);
    if (track == null) return Outcome.refused(refused!);
    final table = KeyTable.fromAnimationTrack(track.track);
    if (values.length != table.componentCount) {
      return Outcome.refused(
        'this track has ${table.componentCount} components; ${values.length} '
        'values were given',
      );
    }
    if (inTangent != null && inTangent!.length != table.componentCount) {
      return Outcome.refused(
        'this track has ${table.componentCount} components; the in tangent '
        'has ${inTangent!.length}',
      );
    }
    if (outTangent != null && outTangent!.length != table.componentCount) {
      return Outcome.refused(
        'this track has ${table.componentCount} components; the out tangent '
        'has ${outTangent!.length}',
      );
    }
    table.setKey(time, values, inTangent: inTangent, outTangent: outTangent);
    return Outcome.done(
      _withTrack(
        project,
        clipIndex,
        trackIndex,
        table.toAnimationTrack(nodeIndex: 0, path: track.track.path),
      ),
    );
  }
}

/// Shifts the keys at [indices] on clip [clipIndex] track [trackIndex] by
/// [deltaTime] — [KeyTable.moveKeys], wired into the undo stack.
final class MoveKeys extends ModelCommand {
  const MoveKeys({
    required this.clipIndex,
    required this.trackIndex,
    required this.indices,
    required this.deltaTime,
  });

  final int clipIndex;
  final int trackIndex;
  final List<int> indices;
  final double deltaTime;

  @override
  String get name => 'moveKeys';

  @override
  String get says => 'move keyframes';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'clipIndex': clipIndex,
    'trackIndex': trackIndex,
    'indices': indices,
    'deltaTime': deltaTime,
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final (:track, :refused) = _trackTarget(project, clipIndex, trackIndex);
    if (track == null) return Outcome.refused(refused!);
    final table = KeyTable.fromAnimationTrack(track.track);
    for (final i in indices) {
      if (i < 0 || i >= table.keyCount) {
        return Outcome.refused(
          'this track has ${table.keyCount} keys; $i is not one of them',
        );
      }
    }
    table.moveKeys(indices, deltaTime);
    return Outcome.done(
      _withTrack(
        project,
        clipIndex,
        trackIndex,
        table.toAnimationTrack(nodeIndex: 0, path: track.track.path),
      ),
    );
  }
}

/// Removes the keys at [indices] from clip [clipIndex] track [trackIndex] —
/// [KeyTable.deleteKeys], wired into the undo stack. Refused, rather than
/// applied, when [indices] would leave the track with no keys at all: a
/// track drives something for as long as the document exists, and one with
/// nothing to sample is not a smaller track, it is a broken one.
final class DeleteKeys extends ModelCommand {
  const DeleteKeys({
    required this.clipIndex,
    required this.trackIndex,
    required this.indices,
  });

  final int clipIndex;
  final int trackIndex;
  final List<int> indices;

  @override
  String get name => 'deleteKeys';

  @override
  String get says => 'delete keyframes';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'clipIndex': clipIndex,
    'trackIndex': trackIndex,
    'indices': indices,
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final (:track, :refused) = _trackTarget(project, clipIndex, trackIndex);
    if (track == null) return Outcome.refused(refused!);
    final table = KeyTable.fromAnimationTrack(track.track);
    for (final i in indices) {
      if (i < 0 || i >= table.keyCount) {
        return Outcome.refused(
          'this track has ${table.keyCount} keys; $i is not one of them',
        );
      }
    }
    final remaining = table.keyCount - indices.toSet().length;
    if (remaining <= 0) {
      return Outcome.refused(
        'deleting ${indices.toSet().length} of this track\'s ${table.keyCount} '
        'keys would leave none, and a track needs at least one',
      );
    }
    table.deleteKeys(indices);
    return Outcome.done(
      _withTrack(
        project,
        clipIndex,
        trackIndex,
        table.toAnimationTrack(nodeIndex: 0, path: track.track.path),
      ),
    );
  }
}

/// Switches clip [clipIndex] track [trackIndex] between linear, step and
/// cubic — [KeyTable.setInterpolation], wired into the undo stack. Every
/// key's own tangents survive the switch, [KeyTable.setInterpolation]'s own
/// guarantee.
final class SetInterpolation extends ModelCommand {
  const SetInterpolation({
    required this.clipIndex,
    required this.trackIndex,
    required this.interpolation,
  });

  final int clipIndex;
  final int trackIndex;
  final AnimationInterpolation interpolation;

  @override
  String get name => 'setInterpolation';

  @override
  String get says => 'change how a track blends between keys';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'clipIndex': clipIndex,
    'trackIndex': trackIndex,
    'interpolation': interpolation.name,
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final (:track, :refused) = _trackTarget(project, clipIndex, trackIndex);
    if (track == null) return Outcome.refused(refused!);
    final table = KeyTable.fromAnimationTrack(track.track)
      ..setInterpolation(interpolation);
    return Outcome.done(
      _withTrack(
        project,
        clipIndex,
        trackIndex,
        table.toAnimationTrack(nodeIndex: 0, path: track.track.path),
      ),
    );
  }
}

/// Sets the key at [index]'s own tangents on clip [clipIndex] track
/// [trackIndex], leaving its time and value untouched — [KeyTable
/// .setTangent], wired into the undo stack. Either tangent left `null`
/// keeps whatever that key already had, [KeyTable.setTangent]'s own rule.
final class SetTangent extends ModelCommand {
  const SetTangent({
    required this.clipIndex,
    required this.trackIndex,
    required this.index,
    this.inTangent,
    this.outTangent,
  });

  final int clipIndex;
  final int trackIndex;
  final int index;
  final List<double>? inTangent;
  final List<double>? outTangent;

  @override
  String get name => 'setTangent';

  @override
  String get says => 'sculpt a keyframe\'s tangent';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'clipIndex': clipIndex,
    'trackIndex': trackIndex,
    'index': index,
    'inTangent': inTangent,
    'outTangent': outTangent,
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final (:track, :refused) = _trackTarget(project, clipIndex, trackIndex);
    if (track == null) return Outcome.refused(refused!);
    final table = KeyTable.fromAnimationTrack(track.track);
    if (index < 0 || index >= table.keyCount) {
      return Outcome.refused(
        'this track has ${table.keyCount} keys; $index is not one of them',
      );
    }
    if (inTangent != null && inTangent!.length != table.componentCount) {
      return Outcome.refused(
        'this track has ${table.componentCount} components; the in tangent '
        'has ${inTangent!.length}',
      );
    }
    if (outTangent != null && outTangent!.length != table.componentCount) {
      return Outcome.refused(
        'this track has ${table.componentCount} components; the out tangent '
        'has ${outTangent!.length}',
      );
    }
    table.setTangent(index, inTangent: inTangent, outTangent: outTangent);
    return Outcome.done(
      _withTrack(
        project,
        clipIndex,
        trackIndex,
        table.toAnimationTrack(nodeIndex: 0, path: track.track.path),
      ),
    );
  }
}
