/// Builds the physics core as a WebAssembly module — P9.
///
///     dart run tool/build_wasm.dart [out.wasm]
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
  'csrc/src/f3d_memory_wasm.c',
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

/// Builds the module into [out], from the package root [root]. Throws a
/// [StateError] naming what is missing or what failed.
void buildWasm({required String root, required String out}) {
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

void main(List<String> args) {
  final out = args.isEmpty ? 'build/f3d_physics.wasm' : args.first;
  File(out).parent.createSync(recursive: true);
  buildWasm(root: Directory.current.path, out: out);
  stdout.writeln('wrote $out (${File(out).lengthSync()} bytes)');
}
