// Compiles the package's materials into the bundles it ships, by hand:
// what the build hook does on every build, for a `dart test` run that no
// build has come before.
//
//     dart run tool/build_materials.dart
import 'dart:io';

import 'package:flutter3d_build/flutter3d_build.dart';

import '../hook/material_bundles.dart';

void main() {
  try {
    for (final source in buildMaterialBundles(Directory.current)) {
      stdout.writeln('built ${source.path}');
    }
  } on MaterialBuildException catch (error) {
    stderr.writeln(error);
    exit(1);
  }
}
