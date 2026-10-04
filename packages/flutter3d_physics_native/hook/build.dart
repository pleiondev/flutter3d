// Compiles the physics core in `csrc/` into the code asset the bindings in
// `lib/src/bindings.dart` load — P9.
//
// With the C compiler the target already uses: Xcode's clang on Apple
// platforms, the NDK's on Android, MSVC or clang on Windows, the system's on
// Linux. The flags are the deterministic mode's: no fused multiply-add
// contraction and no fast math, so the same inputs step to the same bits on
// every platform. The WebAssembly module is not built here — hooks build
// for the native targets — but by `tool/build_wasm.dart`, from the same
// sources with the same flags.
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

/// The core's sources, as `tool/build_wasm.dart` and the C tests list them.
const List<String> coreSources = <String>[
  'csrc/src/f3d_world.c',
  'csrc/src/f3d_motion.c',
  'csrc/src/f3d_heat.c',
  'csrc/src/f3d_snapshot.c',
  'csrc/src/f3d_collide.c',
  'csrc/src/f3d_narrow.c',
  'csrc/src/f3d_solve.c',
  'csrc/src/f3d_tree.c',
  'csrc/src/f3d_convex.c',
  'csrc/src/f3d_hull.c',
  'csrc/src/f3d_mesh.c',
  'csrc/src/f3d_joint.c',
  'csrc/src/f3d_memory_libc.c',
];

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final msvc = input.config.code.targetOS == OS.windows;
    await CBuilder.library(
      name: 'f3d_physics',
      assetName: 'src/bindings.dart',
      sources: coreSources,
      includes: const <String>['csrc/include', 'csrc/src'],
      std: 'c11',
      flags: msvc
          // MSVC contracts nothing without /fp:fast; /fp:precise says so.
          ? const <String>['/fp:precise']
          : const <String>['-ffp-contract=off', '-fno-fast-math'],
    ).run(
      input: input,
      output: output,
      // The builder's own messages, which a hook can only print.
      // ignore: avoid_print
      logger: Logger('')..onRecord.listen((record) => print(record.message)),
    );
  });
}
