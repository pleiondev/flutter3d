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
    // This package's own root, resolved through the package config of
    // whatever project invoked us — **not** `Directory.current`, which was a
    // real bug: `buildShaderBundle` writes to `<packageRoot>/assets/shaders/`,
    // so run the way the comment above recommends (from a consuming project,
    // to unblock its `flutter analyze`) it wrote the bundle into *that
    // project's* `assets/`, where nothing loads it, and left the one
    // `ShaderLibrary.fromAsset` actually reads untouched. Run from a
    // checkout this resolves to the same directory `cd`-ing here used to
    // give; run from a consumer it resolves into the pub cache, where the
    // archive's own bundle already sits and `buildShaderBundle` says so and
    // compiles nothing.
    await buildShaderBundle(
      packageRoot: resolvePackageRoot('flutter3d_impeller', Directory.current),
    );
  } on ShaderBundleBuildException catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
  }
}
