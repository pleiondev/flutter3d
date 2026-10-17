/// WebGL2's material compiler, registered beside the device, writes the
/// section `RuntimeShaders` wrote on its own before (D26), and refuses a
/// request it cannot translate with a sentence.
///
///     flutter test test/section_compiler_test.dart
///
/// Mutation: translate every stage as a fragment stage in
/// `WebGlSectionCompiler.compile` and the vertex stages differ from the
/// engine's own path. On the VM, because the engine's headers are read off
/// disk, so the compiler is imported from `src/` rather than through the
/// barrel, which reaches `package:web`.
@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:flutter3d_core/data_plugins.dart';
import 'package:flutter3d_hardware/shader_bundle.dart';
import 'package:flutter3d_shaders/backend.dart';
import 'package:flutter3d_shaders/compile.dart' show loadShaders;
import 'package:flutter3d_webgl/src/webgl_section_compiler.dart';
import 'package:flutter_test/flutter_test.dart';

/// A material with a vertex block, so the section has vertex stages too.
const String _breathe = '''
f3dmat 2
material Breathe {
  uniform float breath = 0.0;
  vertex {
    out world = world + normal * (0.02 * breath);
  }
  fragment {
    let rim = pow(1.0 - clamp(nDotV, 0.0, 1.0), 3.0);
    return vec4(albedo + vec3(rim), alpha);
  }
}
''';

List<int> _bytes(ByteData data) =>
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

void main() {
  final engine = loadShaders().sources;

  test('the registered compiler writes the bytes the engine wrote', () {
    final compilers = MaterialCompilerRegistry(<MaterialCompiler>[
      const WebGlSectionCompiler(),
    ]);

    final own = runtimeMaterialBundle(
      _breathe,
      backend: 'webgl',
      from: 'breathe.f3dmat',
      engineSources: engine,
    );
    final compiled = runtimeMaterialBundle(
      _breathe,
      backend: 'webgl',
      from: 'breathe.f3dmat',
      engineSources: engine,
      compilers: compilers,
    );
    expect(compiled.names, <String>[
      'Breathe',
      'BreatheVertex',
      'BreatheVertexSkinned',
    ]);
    expect(compiled.names, own.names);
    expect(
      _bytes(compiled.sections[ShaderBundle.webglSection]!),
      _bytes(own.sections[ShaderBundle.webglSection]!),
    );
  });

  test('a request without the engine headers is refused, saying so', () {
    expect(
      () => const WebGlSectionCompiler().compile(
        const MaterialCompileRequest(
          name: 'Glow',
          from: 'glow.f3dmat',
          source: '',
          stages: <MaterialStageSource>[
            MaterialStageSource(name: 'Glow', fragment: true, glsl: ''),
          ],
        ),
      ),
      throwsA(
        isA<MaterialCompileException>().having(
          (e) => e.message,
          'message',
          contains('engineSources'),
        ),
      ),
    );
  });
}
