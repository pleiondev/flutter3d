/// Where the engine's GLSL is, and what the manifest says is in it.
///
/// One file rather than a block inside the generator, because the test that
/// runs every stage through glslang and naga has to read exactly the same list.
/// A test that walked the shader directory itself would pass on the day
/// somebody added a `.frag` and forgot to name it in the manifest — which is
/// the day the engine starts asking for a stage no backend has.
///
/// The twin of `flutter3d_webgl/tool/source_package.dart`, and copied rather
/// than shared: a `tool/` directory is a program and not a library, so nothing
/// under one package's `tool/` is importable from another's. Twenty lines of
/// pub plumbing is a cheaper duplicate than making one backend's build scripts
/// part of another backend's published surface.
///
/// **`dart:io` under `lib/`, which reads oddly in a backend that only runs in a
/// browser.** It is here rather than in `tool/` because the browser test runner
/// serves a package from `test/` and cannot read a sibling directory, so a test
/// may only import what is under `lib/`. Nothing this package exports reaches
/// it, so nothing a consumer builds carries it; and `dart:io` compiles for the
/// web to stubs that throw, which is why the browser run gets through this file
/// rather than failing on it.
library;

import 'dart:convert';
import 'dart:io';

/// Every shader file, keyed the way an `#include <…>` spells it, beside the
/// manifest's entry points in the order it lists them.
typedef ShaderSet = ({
  Map<String, String> sources,
  Map<String, ({String file, bool fragment})> stages,
});

/// Reads `flutter3d_shaders` out of the nearest package config.
///
/// Throws [StateError] with a message worth showing a person when the package
/// is not there or has no `shaders/` in it.
ShaderSet loadShaders() {
  final root = packageRoot('flutter3d_shaders');
  final shaders = Directory('$root/shaders');
  if (!shaders.existsSync()) throw StateError('no shaders/ in $root');

  final sources = <String, String>{};
  for (final file in shaders.listSync(recursive: true).whereType<File>()) {
    final path = file.path;
    if (!path.endsWith('.glsl') &&
        !path.endsWith('.frag') &&
        !path.endsWith('.vert')) {
      continue;
    }
    sources[path.substring(shaders.path.length + 1)] = file.readAsStringSync();
  }

  // The same manifest impellerc reads and the WebGL generator reads. One list
  // of entry points for every backend, so a shader added for one cannot be
  // quietly missing from another — the engine asks for a name and all of them
  // must answer to it.
  final manifestFile = File('${shaders.path}/flutter3d.shaderbundle.json');
  if (!manifestFile.existsSync()) {
    throw StateError('no manifest at ${manifestFile.path}');
  }
  final manifest =
      jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;

  final stages = <String, ({String file, bool fragment})>{};
  manifest.forEach((name, spec) {
    final entry = spec as Map<String, dynamic>;
    final file = (entry['file'] as String).replaceFirst('shaders/', '');
    if (!sources.containsKey(file)) {
      throw StateError('$name names $file, which is not in shaders/');
    }
    stages[name] = (file: file, fragment: entry['type'] == 'fragment');
  });

  return (sources: sources, stages: stages);
}

/// The root directory of [name], through `.dart_tool/package_config.json` at or
/// above the working directory.
///
/// The one mapping pub guarantees for path, git and hosted dependencies alike.
/// A relative path would work here and break the day this package is consumed
/// from the cache.
///
/// `rootUri` is a URI and relative for a workspace member, resolved against
/// `.dart_tool/` — which is why this is `Uri.resolve` and not a string join.
String packageRoot(String name) {
  var dir = Directory.current;
  while (true) {
    final config = File('${dir.path}/.dart_tool/package_config.json');
    if (config.existsSync()) {
      final json =
          jsonDecode(config.readAsStringSync()) as Map<String, dynamic>;
      for (final entry in (json['packages'] as List<dynamic>)) {
        final package = entry as Map<String, dynamic>;
        if (package['name'] != name) continue;
        final base = Uri.directory('${dir.path}/.dart_tool/');
        return base
            .resolve(package['rootUri'] as String)
            .toFilePath()
            .replaceAll(RegExp(r'/$'), '');
      }
      throw StateError(
        '$name is not in ${config.path}. '
        'Is it a dependency, and has `flutter pub get` run?',
      );
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError(
        'no .dart_tool/package_config.json above ${Directory.current.path}',
      );
    }
    dir = parent;
  }
}
