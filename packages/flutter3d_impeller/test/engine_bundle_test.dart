/// The engine's own bundle is built for the SDK it runs on (amendment 4):
/// the project's copy first, the shipped one as a fallback held to the same
/// SDK, and either refused by name when it was compiled on another.
///
///     flutter test test/engine_bundle_test.dart
///
/// Mutation: return the section without `impellerSectionOf` in
/// `engineSectionOf`, and a bundle from another SDK loads.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_impeller/flutter3d_impeller.dart'
    show GpuRenderBackend;
import 'package:flutter3d_impeller/src/gpu_loaded_shaders.dart';
import 'package:flutter3d_impeller/src/shader_bundle_build.dart';
import 'package:flutter3d_shaders/flutter3d_shaders.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stand-in `impellerc` output: bytes that are not the container's magic.
final List<int> _compiled = utf8.encode('IPLR-not-a-real-flatbuffer');

const String _manifest =
    '{"MeshVertex": {"type": "vertex", "file": "shaders/mesh.vert"},'
    ' "Pbr": {"type": "fragment", "file": "shaders/lighting/pbr.frag"}}';

ByteData _stamped(String dart) => stampedEngineBundle(
  _compiled,
  manifest: _manifest,
  dart: dart,
  engine: '5f77625673248ee5846fbcaf5d3e1a3878386fd7',
);

void main() {
  test('the build writes the engine container with its stamp', () {
    final bundle = ShaderBundle.decode(_stamped('3.12.0'));
    expect(bundle.name, 'flutter3d');
    expect(bundle.sdk, '3.12.0');
    expect(bundle.names, <String>['MeshVertex', 'Pbr']);
    expect(bundle.stages.first.fragment, isFalse);
    final stamp = EngineBundleStamp.decode(
      bundle.section(EngineBundleStamp.section),
    )!;
    expect(stamp.engine, startsWith('5f7762'));
    expect(stamp.dart, '3.12.0');
    expect(stamp.stages, 2);
    expect(stamp.full, isTrue);
  });

  test('a bundle built on this SDK hands back its compiled section', () {
    final section = engineSectionOf(
      _stamped('3.12.0'),
      asset: EngineBundleStamp.projectAsset,
      running: '3.12.0',
      fromProject: true,
    );
    expect(
      section.buffer.asUint8List(section.offsetInBytes, section.lengthInBytes),
      _compiled,
    );
  });

  test('impellerc output from a checkout passes through unchecked', () {
    final raw = Uint8List.fromList(_compiled).buffer.asByteData();
    expect(
      engineSectionOf(
        raw,
        asset: GpuRenderBackend.defaultBundleAsset,
        running: '3.12.0',
        fromProject: false,
      ),
      same(raw),
    );
  });

  test('the project\'s bundle from another SDK is refused as stale', () {
    expect(
      () => engineSectionOf(
        _stamped('3.11.0'),
        asset: EngineBundleStamp.projectAsset,
        running: '3.12.0',
        fromProject: true,
      ),
      throwsA(
        isA<ShaderBundleException>()
            .having((e) => e.stale, 'stale', isTrue)
            .having((e) => e.asset, 'asset', EngineBundleStamp.projectAsset)
            .having((e) => e.message, 'message', contains('engine 5f7762'))
            .having((e) => e.advice, 'advice', contains('again')),
      ),
    );
  });

  test('the shipped bundle from another SDK asks for the hook', () {
    expect(
      () => engineSectionOf(
        _stamped('3.11.0'),
        asset: GpuRenderBackend.defaultBundleAsset,
        running: '3.12.0',
        fromProject: false,
      ),
      throwsA(
        isA<ShaderBundleException>()
            .having((e) => e.stale, 'stale', isTrue)
            .having((e) => e.advice, 'advice', contains('hook/build.dart')),
      ),
    );
  });

  test('the project\'s bundle is read before the shipped one', () async {
    final asked = <String>[];
    await expectLater(
      loadEngineShaderLibrary(
        GpuRenderBackend.defaultBundleAsset,
        running: '3.12.0',
        load: (key) async {
          asked.add(key);
          return key == EngineBundleStamp.projectAsset
              ? _stamped('3.11.0')
              : _stamped('3.12.0');
        },
      ),
      throwsA(
        isA<ShaderBundleException>().having(
          (e) => e.asset,
          'asset',
          EngineBundleStamp.projectAsset,
        ),
      ),
    );
    expect(asked, <String>[EngineBundleStamp.projectAsset]);
  });

  test('no bundle at all names both places', () async {
    await expectLater(
      loadEngineShaderLibrary(
        GpuRenderBackend.defaultBundleAsset,
        running: '3.12.0',
        load: (_) async => null,
      ),
      throwsA(
        isA<ShaderBundleException>().having(
          (e) => e.message,
          'message',
          contains(EngineBundleStamp.projectAsset),
        ),
      ),
    );
  });
}
