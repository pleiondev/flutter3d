// Fewer lights for a level, judged by the pictures they make — from any
// project that depends on this package.
//
//   dart run flutter3d_build:lights --optimize assets/levels/crypt.json
//   dart run flutter3d_build:lights --optimize crypt.json --poses walk.json
//   dart run flutter3d_build:lights --optimize crypt.json --dry-run \
//       --preview build/lights
//
// The optimizer itself lives in `flutter3d_editor_core`'s `light_opt/`, the
// one core the editor's button and its agent server call too; this file only
// reads and writes the files around it.
import 'dart:io';

// Not through the package's library, which the build hook imports: the hook
// has no use for a software renderer and should not compile one.
import 'package:flutter3d_build/src/lights.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await runLights(arguments);
}
