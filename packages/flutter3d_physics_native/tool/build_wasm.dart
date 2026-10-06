/// Builds the physics core as a WebAssembly module — P9.
///
///     dart run tool/build_wasm.dart [out.wasm]
///
/// Into `web/f3d_physics.wasm` by default: the module the package ships, as
/// an asset a Flutter web app serves and `loadPhysicsCore()` fetches. Hooks
/// do not build for the browser, so it is built here and kept in the
/// package; `test/wasm_test.dart` holds it to the core it was built from.
///
/// Hooks build code for the native targets only, so the browser's module is
/// built here, from the same sources and with the same flags as
/// `hook/build.dart`: no fused multiply-add contraction and no fast math, so
/// the module steps to the bits the native library steps to. Freestanding,
/// with no C library: `f3d_memory_wasm.c` is the allocator and the module
/// imports nothing.
///
/// Needs a clang with the wasm32 target (Apple's has it) and a wasm linker:
/// `wasm-ld` on the path, or the `rust-lld` a Rust toolchain ships, which is
/// `wasm-ld` under `-flavor wasm`.
library;

import 'dart:io';

/// The core's sources for the WebAssembly build: the world, and the
/// allocator in place of the C library's.
const List<String> wasmSources = <String>[
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
  'csrc/src/f3d_memory_wasm.c',
  'csrc/wasm/f3d_wasm_shim.c',
];

/// The compiler flags the module is built with.
const List<String> wasmFlags = <String>[
  '--target=wasm32',
  '-std=c11',
  '-O2',
  '-ffreestanding',
  '-nostdlib',
  '-ffp-contract=off',
  '-fno-fast-math',
  '-fvisibility=hidden',
  '-Icsrc/include',
  '-Icsrc/src',
];

/// A wasm linker's command line prefix, or null when there is none.
List<String>? findWasmLinker() {
  bool runs(String executable, List<String> args) {
    try {
      return Process.runSync(executable, args).exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  if (runs('wasm-ld', <String>['--version'])) return <String>['wasm-ld'];
  final home = Platform.environment['HOME'];
  if (home == null) return null;
  final toolchains = Directory('$home/.rustup/toolchains');
  if (!toolchains.existsSync()) return null;
  for (final entity in toolchains.listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('/bin/rust-lld')) {
      return <String>[entity.path, '-flavor', 'wasm'];
    }
  }
  return null;
}

/// What the threads build adds: atomics and bulk memory to compile, and a
/// shared memory the host makes and hands every instance — the main one
/// and each worker's — with the stack pointer exported for the host to
/// give each worker a stack of its own.
const List<String> wasmThreadFlags = <String>[
  '-matomics',
  '-mbulk-memory',
  '-DF3D_WASM_THREADS',
];

const List<String> wasmThreadLinkFlags = <String>[
  '--shared-memory',
  '--import-memory',
  '--initial-memory=16777216',
  '--max-memory=2147483648',
  '--export=__stack_pointer',
];

/// Builds the module into [out], from the package root [root]: with
/// [threads], the threads build. Throws a
/// [StateError] naming what is missing or what failed.
void buildWasm({
  required String root,
  required String out,
  bool threads = false,
}) {
  final linker = findWasmLinker();
  if (linker == null) {
    throw StateError(
      'no wasm linker: install lld (wasm-ld), or a Rust toolchain, whose '
      'rust-lld links wasm',
    );
  }
  final scratch = Directory.systemTemp.createTempSync('f3d_wasm');
  try {
    final objects = <String>[];
    for (final source in wasmSources) {
      final object =
          '${scratch.path}/${source.split('/').last.replaceAll('.c', '.o')}';
      final compiled = Process.runSync('clang', <String>[
        ...wasmFlags,
        if (threads) ...wasmThreadFlags,
        '-c',
        source,
        '-o',
        object,
      ], workingDirectory: root);
      if (compiled.exitCode != 0) {
        throw StateError('clang failed on $source:\n${compiled.stderr}');
      }
      objects.add(object);
    }
    final linked = Process.runSync(linker.first, <String>[
      ...linker.skip(1),
      '--no-entry',
      '--export-dynamic',
      '--strip-debug',
      if (threads) ...wasmThreadLinkFlags,
      '-o',
      out,
      ...objects,
    ], workingDirectory: root);
    if (linked.exitCode != 0) {
      throw StateError('linking failed:\n${linked.stderr}${linked.stdout}');
    }
  } finally {
    scratch.deleteSync(recursive: true);
  }
}

/// Both modules by default, the single-threaded one and the threads one;
/// or the one at the path given (`--threads` for the threads build).
void main(List<String> args) {
  final paths = args.where((a) => !a.startsWith('--')).toList();
  final builds = paths.isEmpty
      ? <(String, bool)>[
          ('web/f3d_physics.wasm', false),
          ('web/f3d_physics_threads.wasm', true),
        ]
      : <(String, bool)>[(paths.first, args.contains('--threads'))];
  for (final (out, threads) in builds) {
    File(out).parent.createSync(recursive: true);
    buildWasm(root: Directory.current.path, out: out, threads: threads);
    stdout.writeln('wrote $out (${File(out).lengthSync()} bytes)');
  }
}
