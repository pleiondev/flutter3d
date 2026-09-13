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
/// **Deliberately not in [modelCommandNames] or [modelCommandFromJson], the
/// same as [ReplaceDocument] — for a different reason of its own.**
/// [ReplaceDocument] cannot be journaled at all (a whole project has no
/// honest replay form); this one *could* be, but wiring an MCP tool an
/// agent could call it under is later, app-integration work, the same
/// scope line `paint_weights.dart`'s own "Not a `ModelCommand`" note
/// already drew for a different row in this same family. It stays a real
/// [ModelCommand] regardless, so it gets [Outcome]/history/undo the same
/// way [ApplyJobResult] does — a caller applies it through [ModelHistory]
/// exactly like any other command, it is just not one `flutter3d_model_mcp`
/// exposes yet.
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
