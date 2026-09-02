/// A bundle loaded from bytes on the backend that compiles nothing.
///
///     flutter test test/loaded_shaders_test.dart
///
/// The rule under test is the one `CpuLoadedShaderLibrary` states: the
/// bundle's names are answered with the device's own Dart stages, a name the
/// device has no Dart for refuses the whole bundle by name, and a refused
/// reload leaves the library as it was. The conformance suite checks the same
/// behaviour through the interface; this file checks the refusals the suite
/// cannot phrase for every backend at once.
library;

import 'dart:typed_data';

import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

final class _Magenta implements CpuFragmentShader {
  const _Magenta();

  @override
  Vector4? run(Float32List v, ShaderBindings bindings, FragmentContext c) =>
      Vector4(1.0, 0.0, 1.0, 1.0);
}

CpuDevice _device({Map<String, CpuStage> extra = const <String, CpuStage>{}}) =>
    CpuDevice(
      width: 8,
      height: 8,
      shaders: CpuShaderLibrary(<String, CpuStage>{
        ...builtinCpuShaders(),
        ...extra,
      }),
    );

ByteData _bundle(List<String> names, {String name = 'effects'}) => ShaderBundle(
  name: name,
  sdk: '',
  stages: <ShaderBundleStage>[
    for (final n in names)
      ShaderBundleStage(n, fragment: !n.endsWith('Vertex')),
  ],
).encode();

void main() {
  test(
    'the bundle\'s names are answered with the device\'s own stages',
    () async {
      // Identity, not merely equality: the handle a loaded library answers is
      // the one the built-in library answers, so a pipeline built through either
      // is the same pair. Mutation: build a fresh `ShaderHandle` in
      // `CpuLoadedShaderLibrary[]` and the `identical` fails.
      final device = _device();
      final loaded = await device.loadShaders(
        _bundle(<String>['MeshVertex', 'Unlit']),
      );
      expect(loaded.name, 'effects');
      expect(
        identical(loaded['MeshVertex'], device.shaders['MeshVertex']),
        isTrue,
      );
      expect(identical(loaded['Unlit'], device.shaders['Unlit']), isTrue);
      // A name the device has and the bundle did not claim is not answered:
      // the library is the bundle, not a window onto everything.
      expect(loaded['Pbr'], isNull);
    },
  );

  test(
    'a stage this backend has no Dart for refuses the bundle by name',
    () async {
      // Mutation: drop `_requireEveryStage` from `load` — the bundle loads,
      // `loaded['Stripes']` is null, and the renderer fails later naming the
      // stage rather than the file.
      final device = _device();
      await expectLater(
        device.loadShaders(_bundle(<String>['MeshVertex', 'Stripes', 'Waves'])),
        throwsA(
          isA<ShaderBundleRefused>()
              .having((r) => r.name, 'name', 'effects')
              .having((r) => r.reason, 'reason', contains('Stripes, Waves')),
        ),
      );
    },
  );

  test(
    'a Dart stage the application handed the device is a stage the bundle may name',
    () async {
      // The way an application's own look reaches this backend: write it in
      // Dart, put it in the device's library, and the bundle that names it on
      // the hardware backends loads here too.
      final device = _device(
        extra: <String, CpuStage>{
          'Magenta': const CpuStage.fragment(_Magenta()),
        },
      );
      final loaded = await device.loadShaders(
        _bundle(<String>['MeshVertex', 'Magenta']),
      );
      expect(loaded['Magenta'], isNotNull);
      expect(
        () => device.createPipeline(loaded['MeshVertex']!, loaded['Magenta']!),
        returnsNormally,
      );
    },
  );

  test('a refused reload leaves the library as it was', () async {
    // Mutation: assign `_bundle` before the check in `reload` and the library
    // ends up naming a stage it cannot answer — `loaded['Unlit']` goes null.
    final device = _device();
    final loaded = await device.loadShaders(
      _bundle(<String>['MeshVertex', 'Unlit']),
    );
    expect(
      () => loaded.reload(_bundle(<String>['Unlit', 'Nothing'], name: 'v2')),
      throwsA(isA<ShaderBundleRefused>().having((r) => r.name, 'name', 'v2')),
    );
    expect(loaded.name, 'effects');
    expect(loaded['Unlit'], isNotNull);
    expect(loaded['Nothing'], isNull);

    loaded.reload(_bundle(<String>['Unlit', 'Pbr'], name: 'v3'));
    expect(loaded.name, 'v3');
    expect(loaded['Pbr'], isNotNull);
    expect(loaded['MeshVertex'], isNull, reason: 'the new bundle dropped it');
  });

  test(
    'bytes that are not a bundle are refused before any stage is looked at',
    () async {
      final device = _device();
      await expectLater(
        device.loadShaders(ByteData(32)),
        throwsA(isA<ShaderBundleRefused>()),
      );
    },
  );
}
