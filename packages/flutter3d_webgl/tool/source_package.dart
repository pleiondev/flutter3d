/// Where a package unpacked to, from the nearest package config.
///
/// Shared by `generate_shaders.dart` and `pack_shaders.dart`: both read the
/// engine's GLSL out of `flutter3d_shaders` and neither may guess a relative
/// path to it, because a path works only while the dependency comes from a
/// path and breaks the day the package is consumed from the pub cache.
library;

import 'dart:convert';
import 'dart:io';

/// The root directory of [name], resolved through `.dart_tool/package_config.json`
/// at or above [from] (the working directory by default).
///
/// `rootUri` is a URI and relative for a workspace member, resolved against
/// `.dart_tool/` — which is why this is `Uri.resolve` and not a string join.
String packageRoot(String name, {String? from}) {
  var dir = Directory(from ?? Directory.current.path);
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
