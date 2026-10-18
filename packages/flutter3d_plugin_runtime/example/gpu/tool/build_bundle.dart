// Compiles the sample plugin's lit model into the bundle the GPU harness
// loads: an Impeller section from impellerc, GLSL ES 3.00 for WebGL2, and
// WGSL with its reflection for WebGPU.
//
//     dart run tool/build_bundle.dart
//
// The same `compileMaterial` a game's build hook runs for its own
// materials, called directly, because the plugin ships its material as
// source (`hairSource`) and this harness wants the bundle at a fixed asset
// path. Run with the Flutter SDK's Dart: the Impeller section is stamped
// with that SDK, and a device on another one refuses it by name.
import 'dart:io';

import 'package:flutter3d_build_hooks/flutter3d_build_hooks.dart';
import 'package:flutter3d_hardware/shader_bundle.dart';
import 'package:flutter3d_plugin_runtime_example/acme_sample.dart';
import 'package:flutter3d_shaders/compile.dart';

void main() {
  final harness = Directory.current;
  final scratch = Directory.systemTemp.createTempSync('acme_sample');
  try {
    final bundle = compileMaterial(
      hairSource,
      source: 'acme_sample.dart#hairSource',
      engine: loadShaders(),
      compilers: MaterialCompilers.locate(),
      scratch: scratch,
      // The plugin's namespace: `material Hair` compiles as the stage
      // `acme_sample__Hair` its lighting model names.
      namespace: 'acme_sample',
    );
    final missing = <String>[
      for (final section in <String>[
        ShaderBundle.impellerSection,
        ShaderBundle.webglSection,
        ShaderBundle.webgpuSection,
      ])
        if (bundle.section(section) == null) section,
    ];
    if (missing.isNotEmpty) {
      stderr.writeln(
        'the bundle has no ${missing.join(', ')} section: WebGPU\'s needs '
        'glslangValidator and naga on PATH',
      );
      exit(1);
    }
    final bytes = bundle.encode().buffer.asUint8List();
    final out = File('${harness.path}/assets/acme_sample.f3dshaders')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(bytes);
    // The browser test fetches it from the test server, which serves
    // `test/` and not the application's assets.
    File('${harness.path}/test/acme_sample.f3dshaders').writeAsBytesSync(bytes);
    stdout.writeln(
      'wrote ${out.path}: ${bundle.names.join(', ')}, sections '
      '${bundle.sections.keys.join(', ')}, for ${bundle.sdk}',
    );
  } on MaterialBuildException catch (error) {
    stderr.writeln(error);
    exit(1);
  } finally {
    scratch.deleteSync(recursive: true);
  }
}
