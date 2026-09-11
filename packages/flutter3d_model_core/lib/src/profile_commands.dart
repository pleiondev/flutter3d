/// The command that changes a project's own rig limits — `anim-32`'s own
/// row: `maxInfluences ∈ {1..4}`, `maxJoints ≤ 64`, refused with a text
/// explaining why rather than silently clamped.
///
/// A `part` of `command.dart` for the reason every other command file gives:
/// [ModelCommand] is sealed, and a journal writer's exhaustive `switch` is
/// only exhaustive if the compiler can see every case inside one library.
part of 'command.dart';

/// Changes [ModelProject.profile]'s own `maxJoints`/`maxInfluences`,
/// refusing a value the shader or the vertex storage cannot represent.
///
/// **Not a general profile editor.** The profile's other fields —
/// `maxTriangles`, `maxTextureSize`, the two `require...` flags — have no
/// hard ceiling below what their own type already allows; only these two
/// numbers correspond to a fixed piece of machinery downstream
/// (`Skeleton.maxJoints`, `VertexAttributes`'s own four slots) that a wrong
/// value cannot merely disappoint, the way an over-triangle-budget model
/// still loads. Widen this the day a second field earns the same refusal.
final class SetProfileLimits extends ModelCommand {
  const SetProfileLimits({this.maxJoints, this.maxInfluences});

  /// The shader's own hard ceiling — see [ProjectProfile.maxJoints]'s own
  /// doc comment for why 64 is repeated here rather than read from the
  /// engine constant this package cannot depend on.
  static const int hardMaxJoints = 64;

  /// `VertexAttributes` stores four joint/weight pairs; a fifth has nowhere
  /// to go, whatever a profile promises.
  static const int hardMaxInfluences = 4;

  final int? maxJoints;
  final int? maxInfluences;

  @override
  String get name => 'setProfileLimits';

  @override
  String get says => 'change the rig limits';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    if (maxJoints != null) 'maxJoints': maxJoints,
    if (maxInfluences != null) 'maxInfluences': maxInfluences,
  };

  @override
  Map<String, ParamHint> get hints => const <String, ParamHint>{
    'maxJoints': IntHint(min: 1, max: hardMaxJoints),
    'maxInfluences': IntHint(min: 1, max: hardMaxInfluences),
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final joints = maxJoints ?? project.profile.maxJoints;
    final influences = maxInfluences ?? project.profile.maxInfluences;
    if (joints < 1 || joints > hardMaxJoints) {
      return Outcome.refused(
        'maxJoints must be between 1 and $hardMaxJoints — the skinning '
        'shader holds $hardMaxJoints',
      );
    }
    if (influences < 1 || influences > hardMaxInfluences) {
      return Outcome.refused(
        'maxInfluences must be between 1 and $hardMaxInfluences — a '
        'vertex stores $hardMaxInfluences',
      );
    }
    return Outcome.done(
      project.copyWith(
        profile: project.profile.copyWith(
          maxJoints: joints,
          maxInfluences: influences,
        ),
      ),
    );
  }
}
