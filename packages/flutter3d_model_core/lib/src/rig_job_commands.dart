/// Writes a background rig job's own baked [ProjectClip] into the project —
/// `anim-25`'s own generic half of "job state, result as a command", the
/// row's own cross-reference note for what `core` contributes to `RigJob`.
///
/// **Covers every job kind that answers with a whole clip rather than a
/// whole mesh.** [ApplyJobResult] (`job_commands.dart`) already covers the
/// one job kind — `bindWeights` — that answers with mesh bytes instead;
/// this is its counterpart for `retargetClip` (append — [clipIndex] null),
/// and `bakeIk`/`bakeDrivers` (replace the clip they read from —
/// [clipIndex] given).
///
/// **In [modelCommandNames] and [modelCommandFromJson] since `tut-14`.**
/// Unlike [ReplaceDocument] — which cannot be journaled at all, a whole
/// project having no honest replay form — this one always *could* be; it
/// only stayed out while wiring an MCP tool for it was later,
/// app-integration work. That work is the `applyClipResult` tool in
/// `flutter3d_model_mcp`'s own `model_tools.dart` now, so a cold
/// `CommandJournal` replay past a retarget/IK-bake/shape-driver-bake step
/// no longer refuses for want of a name this build did not know.
part of 'command.dart';

final class ApplyClipResult extends ModelCommand {
  const ApplyClipResult({required this.clip, this.clipIndex});

  final ProjectClip clip;

  /// Null appends [clip] as a new one; given, replaces the clip already at
  /// that index.
  final int? clipIndex;

  @override
  String get name => 'applyClipResult';

  @override
  String get says =>
      clipIndex == null ? 'add the baked clip' : 'update the baked clip';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'clipIndex': clipIndex,
    'clip': _clipToJson(clip),
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final index = clipIndex;
    if (index == null) {
      return Outcome.done(
        project.copyWith(clips: <ProjectClip>[...project.clips, clip]),
      );
    }
    if (index < 0 || index >= project.clips.length) {
      return Outcome.refused('there is no clip $index');
    }
    final clips = List<ProjectClip>.of(project.clips)..[index] = clip;
    return Outcome.done(project.copyWith(clips: clips));
  }
}

Map<String, Object?> _trackToJson(AnimationTrack track) => <String, Object?>{
  'nodeIndex': track.nodeIndex,
  'path': track.path.name,
  'interpolation': track.interpolation.name,
  'times': track.times.toList(),
  'values': track.values.toList(),
  'componentCount': track.componentCount,
};

Map<String, Object?> _projectTrackToJson(ProjectTrack track) =>
    <String, Object?>{
      'objectId': track.objectId,
      'track': _trackToJson(track.track),
    };

Map<String, Object?> _clipToJson(ProjectClip clip) => <String, Object?>{
  'name': clip.name,
  'tracks': <Object?>[
    for (final track in clip.tracks) _projectTrackToJson(track),
  ],
  'extras': clip.extras,
};

/// The exact inverse of [_trackToJson] — [_pathFrom], [_interpolationFrom]
/// and [_doubleListFrom] are `keyframe_commands.dart`'s own readers, reused
/// here rather than redone: the same words, the same "no default, an
/// unknown one is null" rule those already keep for [PoseJoint]/[SetKey].
/// [AnimationTrack]'s own constructor throws on a times/values length
/// mismatch — caught here so a journal line, or an agent's own
/// `applyClipResult` call, that disagrees with itself is one more line
/// [modelCommandFromJson] skips rather than a crash.
AnimationTrack? _trackFromJson(Object? json) {
  if (json is! Map<String, Object?>) return null;
  final AnimationPath? path = _pathFrom(json['path']);
  final AnimationInterpolation? interpolation = _interpolationFrom(
    json['interpolation'],
  );
  final List<double>? times = _doubleListFrom(json['times']);
  final List<double>? values = _doubleListFrom(json['values']);
  return switch ((json['nodeIndex'], json['componentCount'])) {
    (final int nodeIndex, final int componentCount)
        when path != null &&
            interpolation != null &&
            times != null &&
            values != null =>
      _builtTrack(
        nodeIndex: nodeIndex,
        path: path,
        interpolation: interpolation,
        times: times,
        values: values,
        componentCount: componentCount,
      ),
    _ => null,
  };
}

AnimationTrack? _builtTrack({
  required int nodeIndex,
  required AnimationPath path,
  required AnimationInterpolation interpolation,
  required List<double> times,
  required List<double> values,
  required int componentCount,
}) {
  try {
    return AnimationTrack(
      nodeIndex: nodeIndex,
      path: path,
      interpolation: interpolation,
      times: Float32List.fromList(times),
      values: Float32List.fromList(values),
      componentCount: componentCount,
    );
  } on ArgumentError {
    return null;
  }
}

ProjectTrack? _projectTrackFromJson(Object? json) {
  if (json is! Map<String, Object?>) return null;
  final AnimationTrack? track = _trackFromJson(json['track']);
  return switch ((json['objectId'], track)) {
    (final int objectId, final AnimationTrack t) => ProjectTrack(
      objectId: objectId,
      track: t,
    ),
    _ => null,
  };
}

/// The exact inverse of [_clipToJson], for [modelCommandFromJson] reading
/// an [ApplyClipResult] back off a journal line or an MCP `applyClipResult`
/// call.
ProjectClip? _clipFromJson(Object? json) {
  if (json is! Map<String, Object?>) return null;
  final Object? tracksJson = json['tracks'];
  if (tracksJson is! List) return null;
  final tracks = <ProjectTrack>[];
  for (final Object? each in tracksJson) {
    final ProjectTrack? track = _projectTrackFromJson(each);
    if (track == null) return null;
    tracks.add(track);
  }
  final Object? extrasJson = json['extras'];
  return ProjectClip(
    name: json['name'] as String?,
    tracks: tracks,
    extras: extrasJson is Map<String, Object?> ? extrasJson : null,
  );
}
