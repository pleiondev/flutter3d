/// Writes the project fixture for the version this build writes.
///
///     dart run tool/mint_fixture.dart
///
/// **Run once, when a version is first written, and never again for that
/// version.** A fixture's whole job is to be a file from the past: it is what
/// says that a project saved by an older build still opens. A fixture re-minted
/// by today's writer says only that today's writer agrees with itself, which
/// every other test in the suite already covers. So this refuses to overwrite
/// one — when `kProjectVersion` moves, a new file joins the directory and the
/// old ones stay exactly as they are.
library;

import 'dart:io';

import 'package:flutter3d_model_core/flutter3d_model_core.dart';

import '../test/fixture_project.dart';

void main() {
  final path = 'test/fixtures/v$kProjectVersion/workshop.f3dproj';
  final file = File(path);
  if (file.existsSync()) {
    stderr.writeln(
      '$path is already there, and a fixture is never re-minted: it is the '
      'file an older build wrote, and rewriting it with this one would make '
      'the migration test agree with itself. Delete it by hand if you are '
      'certain.',
    );
    exitCode = 1;
    return;
  }
  file.parent.createSync(recursive: true);
  final bytes = writeProject(fixtureProject());
  file.writeAsBytesSync(bytes);
  stdout.writeln('$path: ${bytes.length} bytes');
}
