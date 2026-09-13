/// `par-03`'s own row: writes agent skills for someone building a game *on*
/// flutter3d into their own project.
///
///     dart run tool/skills/bin/skills.dart <project-directory>
///
/// **Not `dart run flutter3d:skills`.** That name is the terminal command
/// the row in `doc/tooling-plan.md` actually asks for, and it needs
/// `flutter3d_build` — `ap-10` — which is not a package that exists in this
/// tree yet. This is the mechanism the real command will call once it does:
/// the content and the writer are here, tested, and idempotent; only the
/// namespaced entry point is missing.
library;

import 'dart:io';

import 'package:skills/skills.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln(
      'usage: dart run tool/skills/bin/skills.dart <project-directory>',
    );
    exitCode = 64; // EX_USAGE
    return;
  }

  final projectRoot = Directory(arguments.single);
  if (!projectRoot.existsSync()) {
    stderr.writeln('no such directory: ${arguments.single}');
    exitCode = 66; // EX_NOINPUT
    return;
  }

  for (final file in writeEngineUserSkills(projectRoot)) {
    stdout.writeln(file.path);
  }
}
