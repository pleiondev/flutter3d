// Compiles the physics core in `csrc/` into the code asset the calls in
// `lib/src/core/calls_native.g.dart` load — P9.
//
// With the C compiler the target already uses: Xcode's clang on Apple
// platforms, the NDK's on Android, MSVC or clang on Windows, the system's on
// Linux. The flags are the deterministic mode's: no fused multiply-add
// contraction and no fast math, so the same inputs step to the same bits on
// every platform. The WebAssembly module is not built here — hooks build
// for the native targets — but by `tool/build_wasm.dart`, from the same
// sources with the same flags.
//
// Only the core: the particles, debris, cloth and fluid it steps on the
// CPU are the same systems a GPU steps through the hardware layer, from the
// kernels in `lib/src/visual_kernels.dart`, which need nothing built here.
// And, apart from it, the liquid's native CPU executor (`csrc/lanes/`),
// optimised and vectorised, which a build without a C compiler goes without.
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
  'csrc/src/f3d_compound.c',
  'csrc/src/f3d_vehicle.c',
  'csrc/src/f3d_multibody.c',
  'csrc/src/f3d_shallow.c',
  'csrc/src/f3d_mesh.c',
  'csrc/src/f3d_joint.c',
  'csrc/src/f3d_ccd.c',
  'csrc/src/f3d_query.c',
  'csrc/src/f3d_particles.c',
  'csrc/src/f3d_debris.c',
  'csrc/src/f3d_cloth.c',
  'csrc/src/f3d_fluid.c',
  'csrc/src/f3d_liquid.c',
  'csrc/src/f3d_pool.c',
  'csrc/src/f3d_expr.c',
  'csrc/src/f3d_memory_libc.c',
];

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final msvc = input.config.code.targetOS == OS.windows;
    await CBuilder.library(
      name: 'f3d_physics',
      assetName: 'src/core/calls_native.g.dart',
      sources: coreSources,
      includes: const <String>['csrc/include', 'csrc/src'],
      std: 'c11',
      flags: msvc
          // MSVC contracts nothing without /fp:fast; /fp:precise says so.
          ? const <String>['/fp:precise']
          : <String>[
              '-ffp-contract=off',
              '-fno-fast-math',
              // The pool's threads: in libc everywhere but older glibc.
              if (input.config.code.targetOS == OS.linux) '-pthread',
              // 32-bit x86 rounds as everywhere else only in SSE2, not on
              // the x87 it uses by default; f3d_internal.h refuses it.
              if (input.config.code.targetArchitecture ==
                  Architecture.ia32) ...<String>['-msse2', '-mfpmath=sse'],
            ],
    ).run(input: input, output: output, logger: logger);
    // The liquid's native CPU executor, apart from the core: optimised and
    // vectorised, so not under the core's deterministic flags, and never
    // the reason a build fails. Without it the liquid runs its kernels.
    try {
      await CBuilder.library(
        name: 'f3d_liquid_lanes',
        assetName: 'src/liquid_lanes_native.dart',
        sources: const <String>['csrc/lanes/f3d_liquid_lanes.c'],
        includes: const <String>['csrc/lanes'],
        std: 'c11',
        flags: msvc ? const <String>['/O2'] : const <String>['-O3'],
      ).run(input: input, output: output, logger: logger);
    } on Object catch (error) {
      logger.warning(
        'flutter3d_physics_native: no native liquid executor ($error); the '
        'liquid runs its kernels.',
      );
    }
  });
}

/// The builders' own messages, which a hook can only print.
final Logger logger = Logger('')
  // ignore: avoid_print
  ..onRecord.listen((record) => print(record.message));
