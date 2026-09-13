// Converts a model into the engine's .f3d container — from any project that
// depends on this package, not only from a checkout of this repository.
//
//   dart run flutter3d:convert assets_src/Box.glb
//   dart run flutter3d:convert assets_src -o build/assets
//   dart run flutter3d:convert --help
//
// `ap-03` in doc/asset-pipeline-plan.md: the thin wrapper the plan asks for.
// The actual conversion — decoding, writing `.f3d`, the round-trip check —
// lives in `package:flutter3d_build`, alongside `ap-05`'s build hook, which
// calls the very same function this file does.
import 'dart:io';

import 'package:flutter3d_build/flutter3d_build.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await runConvert(arguments);
}
