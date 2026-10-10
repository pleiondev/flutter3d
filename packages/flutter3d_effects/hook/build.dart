// The package's build hook: its materials compiled into the bundles it
// ships, on every build of an application that depends on it, so a fresh
// checkout runs with no step between `flutter pub get` and `flutter run`.
import 'dart:io';

import 'package:flutter3d_build_hooks/flutter3d_build_hooks.dart';
import 'package:hooks/hooks.dart';

import 'material_bundles.dart';

void main(List<String> arguments) async {
  await build(arguments, (input, output) async {
    final root = Directory.fromUri(input.packageRoot).path;
    final package = Directory(
      root.endsWith('/') ? root.substring(0, root.length - 1) : root,
    );
    final List<File> sources;
    try {
      sources = buildMaterialBundles(package);
    } on MaterialBuildException catch (error) {
      throw BuildError(message: '$error');
    }
    for (final source in sources) {
      output.dependencies.add(source.absolute.uri);
    }
  });
}
