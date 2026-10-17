import 'package:flutter3d_sim/flutter3d_sim.dart' show EntityDef, Level;

/// The `edu_step` entities [sequenceName] names, in the order it names them.
///
/// What a lesson viewer plays and a step panel lists: an `edu_sequence`
/// entity's `steps` property resolved to the steps themselves. A name in
/// `steps` that no entity carries is skipped rather than thrown for, the
/// same choice `Level.named` makes for a dangling reference elsewhere in the
/// format: a viewer reading a document with a typo in it shows the steps
/// that do exist rather than refusing all of them. A name that is no
/// sequence resolves to no steps.
List<EntityDef> orderedSteps(Level level, String sequenceName) {
  final sequence = level.named(sequenceName);
  if (sequence == null || sequence.type != 'edu_sequence') {
    return const <EntityDef>[];
  }
  final names = sequence.properties['steps'];
  if (names is! List) return const <EntityDef>[];
  return <EntityDef>[
    for (final raw in names)
      if (raw is String)
        if (level.named(raw) case final EntityDef step) step,
  ];
}

/// The steps of [level]'s first `edu_sequence`, in its order; none when the
/// level names no sequence. What a viewer that plays one lesson per level
/// opens with.
List<EntityDef> firstLessonSteps(Level level) {
  for (final entity in level.entities) {
    if (entity.type == 'edu_sequence') {
      final name = entity.name;
      return name == null ? const <EntityDef>[] : orderedSteps(level, name);
    }
  }
  return const <EntityDef>[];
}
