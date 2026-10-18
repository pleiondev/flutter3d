/// A data plugin's material, compiled at run time by a backend's own
/// compiler found in a `MaterialCompilerRegistry` — a fifth backend's, in
/// place of the switch over the engine's four (D26).
///
///     dart test test/data_plugin/material_compilers_test.dart
///
/// Mutation: skip the registry in `runtimeMaterialBundle` and the first test
/// is refused as a backend the engine cannot compile for.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/data_plugins.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart' show ShaderBundle;
import 'package:flutter3d_shaders/backend.dart';
import 'package:test/test.dart';

const String _glow = '''
material Glow {
  fragment {
    return vec4(albedo * 2.0, alpha);
  }
}
''';

/// A compiler that writes the stage names it was handed into its section.
final class _Vulkan extends MaterialCompiler {
  const _Vulkan({this.atRunTime = true});

  final bool atRunTime;

  @override
  String get backend => 'vulkan';

  @override
  String get bundleSection => 'vulkan';

  @override
  bool get compilesAtRunTime => atRunTime;

  @override
  MaterialCompileResult compile(MaterialCompileRequest request) {
    if (request.stages.single.glsl.isEmpty) {
      throw const MaterialCompileException('no GLSL');
    }
    final bytes = Uint8List.fromList(request.stages.single.name.codeUnits);
    return MaterialCompileResult(section: bytes.buffer.asByteData());
  }
}

void main() {
  test('a fifth backend\'s compiler builds its section of the bundle', () {
    final bundle = runtimeMaterialBundle(
      _glow,
      backend: 'vulkan',
      from: 'glow.f3dmat',
      compilers: MaterialCompilerRegistry(<MaterialCompiler>[const _Vulkan()]),
    );
    expect(bundle.names, <String>['Glow']);
    expect(
      bundle.sections.keys,
      containsAll(<String>['vulkan', ShaderBundle.materialSection]),
    );
    final section = bundle.sections['vulkan']!;
    expect(
      String.fromCharCodes(
        section.buffer.asUint8List(0, section.lengthInBytes),
      ),
      'Glow',
    );
  });

  test('a compiler that runs in the build only is refused at run time', () {
    expect(
      () => runtimeMaterialBundle(
        _glow,
        backend: 'vulkan',
        from: 'glow.f3dmat',
        compilers: MaterialCompilerRegistry(<MaterialCompiler>[
          const _Vulkan(atRunTime: false),
        ]),
      ),
      throwsA(
        isA<RuntimeShadersException>().having(
          (e) => e.message,
          'message',
          contains('the vulkan compiler runs in the build only'),
        ),
      ),
    );
  });

  test('without a compiler, a backend the engine does not know is refused', () {
    expect(
      () =>
          runtimeMaterialBundle(_glow, backend: 'vulkan', from: 'glow.f3dmat'),
      throwsA(isA<RuntimeShadersException>()),
    );
  });
}
