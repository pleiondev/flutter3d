// Writes what a project needs for the build hook to run on every build —
// from any project that depends on this package, not only from a checkout
// of this repository.
//
//   dart run flutter3d_build:init
//   dart run flutter3d_build:init --check
//   dart run flutter3d_build:init --force
//
// `ap-10` in doc/asset-pipeline-plan.md. The actual writing — hook/build.dart,
// pubspec.yaml, .gitignore — lives in `package:flutter3d_build`, so a test can
// call it against a temporary directory the way `bin/convert.dart`'s own
// logic is tested rather than shelled out to.
import 'dart:io';

import 'package:flutter3d_build/flutter3d_build.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await runInit(arguments);
}
