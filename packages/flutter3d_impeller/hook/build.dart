// `ap-06`: builds this package's own shader bundle automatically, so
// `flutter run`/`flutter build` draws a frame without anybody running
// `tool/build_shaders.sh` by hand first.
//
// **Narrower than the script on purpose.** `tool/build_shaders.sh` serves
// every `flutter3d_*` extension, with `--package-include`, a discoverable
// manifest, and a binding-table printout for engine development. This hook
// exists for one thing: `flutter3d_impeller`'s own canonical bundle, the
// one `LightingModel` names shaders from — a consumer's build needs
// exactly that and nothing configurable, and the manual script stays for
// the day-to-day engine work the acceptance for this point does not ask
// this hook to replace.
//
// **Not `package:flutter_gpu_shaders`.** It depends on `package:data_assets`
// (`hooks ^2.0`, `data_assets ^0.20`) — the experimental half `ap-00`'s
// spike already ruled out on stable. This hook writes an ordinary file
// under `assets/shaders/`, the same convention `ap-05`'s model pipeline
// uses for `flutter3d_generated/`.
//
// **The real logic lives in `lib/src/shader_bundle_build.dart`, not here.**
// This file only adapts it to `package:hooks`' own `BuildInput`/
// `BuildOutputBuilder` — see that file's own doc comment for why, and see
// `bin/build_shader_bundle.dart` for the other caller.
import 'dart:io';

import 'package:flutter3d_impeller/src/shader_bundle_build.dart';
import 'package:hooks/hooks.dart';

void main(List<String> arguments) async {
  await build(arguments, _buildAssets);
}

Future<void> _buildAssets(BuildInput input, BuildOutputBuilder output) async {
  final root = Directory.fromUri(input.packageRoot).path;
  final packageRoot = Directory(
    root.endsWith('/') ? root.substring(0, root.length - 1) : root,
  );

  final List<Uri> dependencies;
  try {
    dependencies = await buildShaderBundle(packageRoot: packageRoot);
  } on ShaderBundleBuildException catch (error) {
    throw BuildError(message: error.message);
  }

  for (final uri in dependencies) {
    output.dependencies.add(uri);
  }
}
