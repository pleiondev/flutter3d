/// Writes `shaders/lib/shading_constants.glsl` from the Dart constants in
/// `lib/src/shading_constants.dart`.
///
///     dart run tool/gen_shading_constants.dart          write it
///     dart run tool/gen_shading_constants.dart --check  exit 1 if stale
///
/// Run from the package root. After writing, the shader bundles are older
/// than their sources and the structure rule says how to rebuild them.
library;

import 'dart:io';

import 'package:flutter3d_shaders/src/shading_constants.dart';

void main(List<String> args) {
  final file = File('shaders/lib/shading_constants.glsl');
  final text = shadingConstantsGlsl();
  if (args.contains('--check')) {
    if (!file.existsSync() || file.readAsStringSync() != text) {
      stderr.writeln(
        '${file.path} is not what lib/src/shading_constants.dart says; '
        'run dart run tool/gen_shading_constants.dart',
      );
      exit(1);
    }
    return;
  }
  file.writeAsStringSync(text);
  stdout.writeln('wrote ${file.path}');
}
