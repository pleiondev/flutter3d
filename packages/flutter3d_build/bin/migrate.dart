/// `flutter3d migrate`, under the name `dart run flutter3d_build:migrate`
/// reaches: an alias, and nothing else. The command is `runFlutter3d`.
library;

import 'dart:io';

import 'package:flutter3d_build/cli.dart' show runFlutter3d;

Future<void> main(List<String> arguments) async {
  exitCode = await runFlutter3d(<String>['migrate', ...arguments]);
}
