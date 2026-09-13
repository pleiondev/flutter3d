import 'dart:io';

import 'skill_content.dart';

/// Writes every [engineUserSkills] entry to
/// `<projectRoot>/.claude/skills/<slug>/SKILL.md`.
///
/// **Deliberately unconditional.** [engineUserSkills] is a compile-time
/// constant, so the bytes it produces for a given [projectRoot] are the same
/// on every call — overwriting rather than checking-then-writing is what
/// makes a repeat run's own diff empty, which is `par-03`'s own acceptance
/// line, rather than a guarantee this function has to construct by hand.
///
/// Returns the files written, in [engineUserSkills]'s own order.
List<File> writeEngineUserSkills(Directory projectRoot) {
  final written = <File>[];
  for (final skill in engineUserSkills) {
    final file = File(
      '${projectRoot.path}/.claude/skills/${skill.slug}/SKILL.md',
    );
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(skill.body);
    written.add(file);
  }
  return written;
}
