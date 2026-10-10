/// `flutter3d convert`, under the name `dart run flutter3d_build:convert`
/// reaches: an alias, and nothing else. The command is `runFlutter3d`.
///
/// Until 1.0 this name ran the one-model converter, whose `-o` named a file
/// and which took `--classes`. That converter is `runConvert` in
/// `package:flutter3d_build`, for a build script that wants either.
library;

import 'dart:io';

import 'package:flutter3d_build/cli.dart' show runFlutter3d;

Future<void> main(List<String> arguments) async {
  exitCode = await runFlutter3d(<String>['convert', ...arguments]);
}
