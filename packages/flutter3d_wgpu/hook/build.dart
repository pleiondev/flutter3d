// Compiles the compute sidecar's C surface in `csrc/` into the code asset
// `lib/src/wgpu_bindings.dart` binds, with wgpu-native linked in.
//
// wgpu-native is the pinned release `tool/hook/wgpu_native.dart` fetches,
// the one `flutter3d_physics_native` links into its GPU passes too, from a
// copy of the same file under its own `tool/hook/`. With the
// C compiler the target already uses: Xcode's clang on Apple platforms, the
// NDK's on Android, MSVC or clang on Windows, the system's on Linux. Where
// there is no wgpu-native for the target, or no network to fetch it, the
// hook says so and builds nothing: the sidecar then refuses to open, and a
// frame places its compute steps on the CPU.
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

import '../tool/hook/wgpu_native.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final code = input.config.code;
    final target = wgpuNativeTarget(code);
    if (target == null) {
      logger.info('no wgpu-native for ${code.targetOS}: no compute sidecar');
      return;
    }
    final wgpu = await fetchWgpuNative(
      target,
      input.outputDirectoryShared,
      logger.warning,
    );
    if (wgpu == null) return;
    await CBuilder.library(
      name: 'f3d_wgpu',
      assetName: 'src/wgpu_bindings.dart',
      sources: const <String>['csrc/f3d_wgpu.c'],
      includes: <String>['csrc', '${wgpu.path}/include'],
      std: 'c11',
      libraries: const <String>['wgpu_native'],
      libraryDirectories: <String>['${wgpu.path}/lib'],
      flags: wgpuNativeSystemLibraries(code.targetOS),
    ).run(input: input, output: output, logger: logger);
  });
}

/// The builder's own messages, which a hook can only print.
final Logger logger = Logger('')
  // ignore: avoid_print
  ..onRecord.listen((record) => print(record.message));
