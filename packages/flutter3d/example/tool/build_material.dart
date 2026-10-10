// Compiles the example's `.f3dmat` sources into loadable shader bundles —
// `P8`. Run by `tool/build_shaders.sh` after the hand-written bundle.
//
//     dart run tool/build_material.dart
//
// The same `compileMaterial` the build hook runs for a game's
// `assets_src/**/*.f3dmat`, called directly: this example does not use the
// hook, and its golden runner wants the bundle at a fixed asset path.
import 'dart:io';

import 'package:flutter3d_build_hooks/flutter3d_build_hooks.dart';
import 'package:flutter3d_shaders/compile.dart';

void main() {
  final example = Directory.current;
  final engine = loadShaders(from: example.path);
  final compilers = MaterialCompilers.locate();
  final scratch = Directory.systemTemp.createTempSync('f3dmat');
  try {
    for (final file in Directory('${example.path}/shaders').listSync()) {
      if (file is! File || !file.path.endsWith('.f3dmat')) continue;
      final name = file.uri.pathSegments.last.replaceAll('.f3dmat', '');
      final bundle = compileMaterial(
        file.readAsStringSync(),
        source: file.path,
        engine: engine,
        compilers: compilers,
        scratch: scratch,
      );
      final out = File('${example.path}/assets/shaders/$name.f3dshaders')
        ..writeAsBytesSync(bundle.encode().buffer.asUint8List());
      stdout.writeln(
        'wrote ${out.path}: ${bundle.stages.length} stage, sections '
        '${bundle.sections.keys.join(', ')}',
      );
    }
  } on MaterialBuildException catch (error) {
    stderr.writeln(error);
    exit(1);
  } finally {
    scratch.deleteSync(recursive: true);
  }
}
