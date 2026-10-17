/// The core's C sources compiled once per set of flags and kept, so a test
/// that runs a C program links it against the core's objects instead of
/// compiling the whole core again.
///
/// **Why it is kept.** `c_unit_test.dart` builds thirty-odd programs in two
/// precisions under the sanitisers and `law_parity_test.dart` two more; each
/// compiled the core's twenty-seven sources from nothing, eight to ten
/// seconds a program, and the suite spent most of its quarter of an hour
/// compiling the same files with the same flags.
///
/// **What the key is.** The compiler, what its `--version` says, the flags,
/// and every byte of every source and header under `csrc/src` and
/// `csrc/include`: an edit to any of them, a flag a test adds, or an update
/// of the toolchain under the same `cc` is a new key and a fresh build, so a
/// kept object is never one the sources or the compiler have moved on from.
/// The version is asked on every build, not remembered: a compiler is never
/// taken to be what it was earlier in the run. A key's objects are
/// written into a directory of their own and renamed into place whole, so
/// two test files building the same key at once each see a complete set.
/// Keys whose flags match the new one are removed when it is made: the
/// cache holds one build per set of flags.
///
/// Under `.dart_tool/`, which is not committed.
library;

import 'dart:io';
import 'dart:math' as math;

import '../hook/build.dart' show coreSources;

/// Where the kept builds are, from the package's root.
const String _cacheRoot = '.dart_tool/flutter3d_physics_native/c_cache';

/// FNV-1a, 64 bits, over [bytes], continuing from [hash].
int _fnv(int hash, List<int> bytes) {
  var h = hash;
  for (final b in bytes) {
    h ^= b;
    h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return h;
}

const int _fnvOffset = 0xcbf29ce484222325;

String _hex(int hash) => hash.toUnsigned(64).toRadixString(16).padLeft(16, '0');

/// The core's sources and every header they can include, in a fixed order.
List<File> _inputs() => <File>[
  for (final dir in const <String>['csrc/src', 'csrc/include'])
    ...Directory(dir).listSync().whereType<File>().where(
      (f) => f.path.endsWith('.c') || f.path.endsWith('.h'),
    ),
]..sort((a, b) => a.path.compareTo(b.path));

/// The core's object files, built by [compiler] with [flags] — or the kept
/// ones of an earlier build with the same compiler, flags and sources. The
/// include paths are added here.
Future<List<String>> coreObjects(String compiler, List<String> flags) async {
  final flagsKey = _hex(
    _fnv(_fnvOffset, '$compiler ${flags.join(' ')}'.codeUnits),
  );
  final said = await Process.run(compiler, const <String>['--version']);
  var content = _fnv(
    _fnv(_fnvOffset, flagsKey.codeUnits),
    '${said.exitCode} ${said.stdout}'.codeUnits,
  );
  for (final file in _inputs()) {
    content = _fnv(content, file.path.codeUnits);
    content = _fnv(content, file.readAsBytesSync());
  }
  final key = '$flagsKey-${_hex(content)}';
  final root = Directory(_cacheRoot)..createSync(recursive: true);
  final home = Directory('${root.path}/$key');
  List<String> objects(Directory dir) => <String>[
    for (var i = 0; i < coreSources.length; i++) '${dir.absolute.path}/$i.o',
  ];
  if (File('${home.path}/done').existsSync()) return objects(home);

  final scratch = root.createTempSync('$key.building-');
  try {
    // As many compilers at once as the machine has cores.
    final width = math.max(1, Platform.numberOfProcessors);
    final pending = <int>[for (var i = 0; i < coreSources.length; i++) i];
    Future<void> worker() async {
      while (pending.isNotEmpty) {
        final i = pending.removeLast();
        final built = await Process.run(compiler, <String>[
          ...flags,
          '-Icsrc/include',
          '-Icsrc/src',
          '-c',
          coreSources[i],
          '-o',
          '${scratch.path}/$i.o',
        ]);
        if (built.exitCode != 0) {
          throw StateError(
            '${coreSources[i]} did not build:\n${built.stdout}${built.stderr}',
          );
        }
      }
    }

    await Future.wait(<Future<void>>[for (var w = 0; w < width; w++) worker()]);
    File('${scratch.path}/done').writeAsStringSync(flags.join(' '));
    try {
      scratch.renameSync(home.path);
    } on FileSystemException {
      // Another test file built the same key first: its set is as good.
      if (!File('${home.path}/done').existsSync()) rethrow;
    }
  } finally {
    if (scratch.existsSync()) scratch.deleteSync(recursive: true);
  }
  // The builds of these flags from older sources.
  for (final old in root.listSync().whereType<Directory>()) {
    final name = old.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    if (name.startsWith('$flagsKey-') && name != key && !name.contains('.')) {
      try {
        old.deleteSync(recursive: true);
      } on FileSystemException {
        // Being read or removed by another test file: left for next time.
      }
    }
  }
  return objects(home);
}

/// Builds [sources] with [compiler] and [flags] against the core's kept
/// objects ([coreObjects]) into [binary], linking [libraries] after.
Future<ProcessResult> buildAgainstCore(
  String compiler,
  List<String> flags,
  List<String> sources,
  String binary, {
  List<String> libraries = const <String>['-lm'],
}) async {
  final core = await coreObjects(compiler, flags);
  return Process.run(compiler, <String>[
    ...flags,
    '-Icsrc/include',
    '-Icsrc/src',
    ...sources,
    ...core,
    '-o',
    binary,
    ...libraries,
  ]);
}
