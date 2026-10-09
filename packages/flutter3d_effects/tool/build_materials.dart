// Compiles the package's materials into the bundles it ships, by hand:
// what the build hook does on every build, for a `dart test` run that no
// build has come before.
//
//     dart run tool/build_materials.dart
import 'dart:io';

import 'package:flutter3d_build_hooks/flutter3d_build_hooks.dart';
import 'package:flutter3d_core/formats.dart';

import '../hook/material_bundles.dart';

void main() {
  try {
    final sources = buildMaterialBundles(Directory.current);
    for (final source in sources) {
      stdout.writeln('built ${source.path}');
    }
    // Item 22: the typed accessors `SeabedLook` and `LiquidLook` set their
    // uniforms through, generated from the same sources and committed, as
    // a package's own Dart must be.
    File('lib/src/materials.g.dart').writeAsStringSync(
      generateMaterialAccessors(
        <MaterialProgram>[
          for (final source in sources)
            parseMaterial(source.readAsStringSync()),
        ],
        from: <String, String>{
          for (final source in sources)
            parseMaterial(source.readAsStringSync()).name:
                'assets_src/${source.uri.pathSegments.last}',
        },
      ),
    );
    stdout.writeln('wrote lib/src/materials.g.dart');
  } on MaterialBuildException catch (error) {
    stderr.writeln(error);
    exit(1);
  }
}
