// Prints the filesystem root of a resolved Dart package.
//
//   dart tool/package_root.dart flutter3d
//   dart tool/package_root.dart flutter3d --from ../some/consumer
//
// Why this exists: a shader in an extension package writes
// `#include <lib/color.glsl>`, and impellerc can only satisfy that if it is
// handed `<flutter3d>/shaders` as an include root. Inside this repository that
// root is a known relative path, so nobody needed to look it up. A package
// installed from pub has no knowable relative path — it sits in the pub cache
// under a version-stamped directory — so the path has to be *resolved*, not
// written down.
//
// `.dart_tool/package_config.json` is the resolver. Pub writes it for every
// dependency regardless of where the dependency came from: a path dependency, a
// git dependency and a hosted dependency all get one `rootUri` entry, and only
// the value differs. That makes it the single mechanism that works off-path.
//
// Why Dart rather than python3 or shell parsing:
//
//   * The Flutter SDK is already a hard prerequisite of the shader build — we
//     invoke impellerc out of `bin/cache/artifacts` — so `dart` costs no new
//     dependency, whereas python3 is merely likely to be present.
//   * `rootUri` is a URI, not a path. It may be relative (workspace and path
//     dependencies get `../packages/foo`, resolved against the location of
//     package_config.json) or absolute (`file:///…/.pub-cache/hosted/pub.dev/
//     foo-1.2.3`), and it is percent-encoded, so a cache under a directory with
//     a space in its name arrives as `%20`. `Uri.resolve` plus `toFilePath()`
//     implements exactly those rules; `sed`/`grep` implements roughly them,
//     which is the failure mode that only shows up on somebody else's machine.
//   * Being Dart, it is covered by `flutter analyze` and by a unit test rather
//     than being an untested string in a shell script.

import 'dart:convert';
import 'dart:io';

const _usage = '''
usage: dart tool/package_root.dart <package-name> [--from <directory>]

Prints the absolute filesystem path of <package-name>'s root directory, as
recorded in the nearest .dart_tool/package_config.json at or above <directory>
(default: the current directory).

Exit codes: 0 found, 1 not found / no package config, 2 bad usage.
''';

// `exitCode` rather than a returned int: the Dart VM ignores whatever `main`
// returns, and the caller here is a shell script under `set -e` that decides
// what to do by the status. A silent 0 would turn "package not found" into
// "include root is the empty string", which impellerc reports as a missing
// header three steps later.
void main(List<String> arguments) {
  exitCode = _run(arguments);
}

int _run(List<String> arguments) {
  String? name;
  var from = Directory.current.path;

  for (var i = 0; i < arguments.length; i++) {
    final argument = arguments[i];
    if (argument == '--from' || argument == '-f') {
      if (i + 1 >= arguments.length) {
        stderr.writeln(_usage);
        return 2;
      }
      from = arguments[++i];
    } else if (argument.startsWith('-')) {
      stderr.writeln(_usage);
      return 2;
    } else if (name == null) {
      name = argument;
    } else {
      stderr.writeln(_usage);
      return 2;
    }
  }

  if (name == null) {
    stderr.writeln(_usage);
    return 2;
  }

  final configFile = findPackageConfig(from);
  if (configFile == null) {
    stderr.writeln(
      'package_root: no .dart_tool/package_config.json at or above '
      '"$from". Run `flutter pub get` first.',
    );
    return 1;
  }

  final String root;
  try {
    root = packageRoot(configFile, name);
  } on FormatException catch (error) {
    stderr.writeln('package_root: ${configFile.path}: ${error.message}');
    return 1;
  } on StateError catch (error) {
    stderr.writeln('package_root: ${error.message}');
    return 1;
  }

  stdout.writeln(root);
  return 0;
}

/// Walks up from [start] looking for `.dart_tool/package_config.json`.
///
/// Walking up rather than looking only in [start] is not a convenience. Under a
/// pub workspace there is exactly one package config, at the workspace root, and
/// the member packages have none of their own — so a build script invoked from
/// `packages/foo` would find nothing if it did not climb.
File? findPackageConfig(String start) {
  var directory = Directory(start).absolute;
  // `absolute` does not normalise `..`, and `parent` of a path ending in `..`
  // just appends another one, so resolve the symlinks/relative parts once.
  if (directory.existsSync()) {
    directory = Directory(directory.resolveSymbolicLinksSync());
  }

  while (true) {
    final candidate = File(
      '${directory.path}${Platform.pathSeparator}.dart_tool'
      '${Platform.pathSeparator}package_config.json',
    );
    if (candidate.existsSync()) return candidate;

    final parent = directory.parent;
    if (parent.path == directory.path) return null;
    directory = parent;
  }
}

/// Resolves [name]'s `rootUri` from [configFile] to an absolute path.
///
/// Throws [StateError] when the package is absent from the config, and
/// [FormatException] when the config is not a package config at all.
String packageRoot(File configFile, String name) {
  final Object? decoded = jsonDecode(configFile.readAsStringSync());
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('not a JSON object');
  }
  final packages = decoded['packages'];
  if (packages is! List) {
    throw const FormatException('no "packages" list');
  }

  for (final entry in packages) {
    if (entry is! Map<String, Object?>) continue;
    if (entry['name'] != name) continue;

    final rootUri = entry['rootUri'];
    if (rootUri is! String) {
      throw FormatException('package "$name" has no string "rootUri"');
    }

    // The spec: a relative rootUri is resolved against the location of
    // package_config.json itself — that is, against `.dart_tool/`, which is why
    // workspace members read as `../packages/foo` rather than `packages/foo`.
    // An absolute `file:` URI, which is what the pub cache produces, resolves to
    // itself, so one call covers both.
    final base = Uri.file(configFile.absolute.path);
    final resolved = base.resolve(rootUri);
    if (resolved.scheme != 'file') {
      throw FormatException('package "$name" has a non-file rootUri: $rootUri');
    }
    // Strips any trailing slash so callers can append their own separator.
    final path = resolved.toFilePath();
    if (path.length > 1 && path.endsWith(Platform.pathSeparator)) {
      return path.substring(0, path.length - 1);
    }
    return path;
  }

  throw StateError(
    'package "$name" is not in ${configFile.path}. '
    'Is it a dependency, and has `flutter pub get` run since it was added?',
  );
}
