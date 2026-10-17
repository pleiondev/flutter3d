/// The `flutter3d` command: one entry point for the tools this package has.
///
///     dart pub global activate flutter3d_build
///     flutter3d convert Assets/Prefabs/Crate.prefab -o assets_src/imported
///     flutter3d doctor
///     flutter3d help convert
///
/// The command is `runFlutter3d` in `package:flutter3d_build/cli.dart`. The
/// other files here are its subcommands under the names
/// `dart run flutter3d_build:<command>` reaches, each an alias of one line.
library;

import 'dart:io';

import 'package:flutter3d_build/cli.dart' show runFlutter3d;

Future<void> main(List<String> arguments) async {
  exitCode = await runFlutter3d(arguments);
}
