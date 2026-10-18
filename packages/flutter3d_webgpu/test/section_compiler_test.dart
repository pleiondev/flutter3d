/// WebGPU's material compiler, registered with a `MaterialCompilerRegistry`,
/// packs the section `RuntimeShaders` wrote on its own before (D26), and
/// refuses a request that carries no WGSL with a sentence.
///
///     flutter test test/section_compiler_test.dart
///
/// Mutation: drop the `webGpuStages` option in `runtimeMaterialBundle` and
/// the registered compiler refuses the material; file a stage under the
/// vertex stages in `WebGpuSectionCompiler.compile` and the section differs.
@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:flutter3d_core/data_plugins.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_shaders/backend.dart';
import 'package:flutter3d_webgpu/flutter3d_webgpu.dart';
import 'package:flutter_test/flutter_test.dart';

const String _glow = '''
material Glow {
  param vec3 tint = vec3(1.0, 0.6, 0.2);
  uniform float pulse = 0.5;
  fragment {
    return vec4(albedo * tint * pulse, alpha);
  }
}
''';

List<int> _bytes(ByteData data) =>
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

void main() {
  final host = webGpuMaterialHost();

  test('the registered compiler packs the bytes the engine packed', () {
    final own = runtimeMaterialBundle(
      _glow,
      backend: 'webgpu',
      from: 'glow.f3dmat',
      webGpuHost: host,
    );
    final compiled = runtimeMaterialBundle(
      _glow,
      backend: 'webgpu',
      from: 'glow.f3dmat',
      webGpuHost: host,
      compilers: MaterialCompilerRegistry(<MaterialCompiler>[
        const WebGpuSectionCompiler(),
      ]),
    );
    expect(compiled.names, own.names);
    expect(
      _bytes(compiled.sections[ShaderBundle.webgpuSection]!),
      _bytes(own.sections[ShaderBundle.webgpuSection]!),
    );
  });

  test('without a host the material is refused, naming the build', () {
    expect(
      () => runtimeMaterialBundle(
        _glow,
        backend: 'webgpu',
        from: 'glow.f3dmat',
        compilers: MaterialCompilerRegistry(<MaterialCompiler>[
          const WebGpuSectionCompiler(),
        ]),
      ),
      throwsA(
        isA<RuntimeShadersException>().having(
          (e) => e.message,
          'message',
          allOf(contains('glow.f3dmat'), contains('assets_src/')),
        ),
      ),
    );
  });
}
