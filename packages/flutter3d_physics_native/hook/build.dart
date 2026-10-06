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
// Then the GPU passes, `csrc/gpu/`, as a library of their own, linked with
// wgpu-native, which `wgpu_native.dart` fetches for the target; without it,
// the core alone.
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

import 'wgpu_native.dart';

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
  'csrc/src/f3d_water.c',
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
    final code = input.config.code;
    final target = wgpuNativeTarget(code);
    if (target == null) {
      logger.info('no wgpu-native for ${code.targetOS}: no GPU passes');
      return;
    }
    final wgpu = await fetchWgpuNative(
      target,
      input.outputDirectoryShared,
      logger.warning,
    );
    if (wgpu == null) return;
    await CBuilder.library(
      name: 'f3d_gpu',
      assetName: 'src/gpu_bindings.dart',
      sources: const <String>[
        'csrc/gpu/f3d_gpu.c',
        'csrc/gpu/f3d_gpu_particles.c',
        'csrc/gpu/f3d_gpu_debris.c',
        'csrc/gpu/f3d_gpu_cloth.c',
        'csrc/gpu/f3d_gpu_fluid.c',
      ],
      includes: <String>['csrc/gpu', '${wgpu.path}/include'],
      std: 'c11',
      libraries: const <String>['wgpu_native'],
      libraryDirectories: <String>['${wgpu.path}/lib'],
      flags: wgpuNativeSystemLibraries(code.targetOS),
    ).run(input: input, output: output, logger: logger);
  });
}

/// The builders' own messages, which a hook can only print.
final Logger logger = Logger('')
  // ignore: avoid_print
  ..onRecord.listen((record) => print(record.message));
