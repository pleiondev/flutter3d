/// The software rasteriser registers its material compiler beside its
/// device (D26), and the compiler writes the section `RuntimeShaders` wrote
/// for this backend on its own.
///
///     dart test test/section_compiler_test.dart
///
/// Mutation: leave the compiler out of `registerCpuBackend` and the registry
/// answers null; cancel the device alone and the compiler outlives it.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/data_plugins.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_shaders/backend.dart';
import 'package:test/test.dart';

const String _glow = '''
material Glow {
  param vec3 tint = vec3(1.0, 0.6, 0.2);
  fragment {
    return vec4(albedo * tint, alpha);
  }
}
''';

List<int> _bytes(ByteData data) =>
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

void main() {
  test('the backend registers its compiler and takes it out again', () {
    final compilers = MaterialCompilerRegistry();
    final registration = registerCpuBackend(
      DeviceRegistry(),
      compilers: compilers,
    );
    expect(compilers.forBackend('cpu'), isA<CpuSectionCompiler>());
    registration.cancel();
    expect(compilers.forBackend('cpu'), isNull);
  });

  test('the registered compiler writes the bytes the engine wrote', () {
    final own = runtimeMaterialBundle(
      _glow,
      backend: 'cpu',
      from: 'glow.f3dmat',
    );
    final compiled = runtimeMaterialBundle(
      _glow,
      backend: 'cpu',
      from: 'glow.f3dmat',
      compilers: MaterialCompilerRegistry(<MaterialCompiler>[
        const CpuSectionCompiler(),
      ]),
    );
    expect(compiled.names, own.names);
    expect(compiled.sections.keys, own.sections.keys);
    expect(
      _bytes(compiled.sections[ShaderBundle.materialSection]!),
      _bytes(own.sections[ShaderBundle.materialSection]!),
    );
  });
}
