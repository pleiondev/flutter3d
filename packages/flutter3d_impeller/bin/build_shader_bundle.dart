// Compiles this package's own shader bundle, fast, with no full `flutter
// build` — `dart run flutter3d_impeller:build_shader_bundle`.
//
// **Why this exists beside `hook/build.dart`.** `flutter analyze` does not
// run build hooks — verified by removing the compiled bundle and watching
// `flutter analyze` fail on its own `assets:` entry with `asset_does_not_
// exist`, rather than assumed — so a checkout with no bundle yet fails
// analysis before any real build ever gets the chance to trigger the hook.
// CI's own reason for the manual `tool/build_shaders.sh` step this replaces
// was exactly that. This calls the same real logic the hook does
// (`lib/src/shader_bundle_build.dart`), just from a CLI a CI step or a
// developer can run directly, without `tool/build_shaders.sh`'s wider
// surface (cross-package includes, a discoverable manifest, the binding
// table) that engine development still wants and this package's own single,
// fixed bundle does not.
import 'dart:io';

import 'package:flutter3d_impeller/src/shader_bundle_build.dart';

Future<void> main(List<String> arguments) async {
  try {
    await buildShaderBundle(packageRoot: Directory.current);
  } on ShaderBundleBuildException catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
  }
}
