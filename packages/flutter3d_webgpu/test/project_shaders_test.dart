/// Which stages a WebGPU device opens over when it is handed none: the
/// project's bundle where it carries a `webgpu` section, the compiled table
/// where it does not, and a refusal naming the asset for a bundle that is
/// there and cannot be read.
///
///     flutter test test/project_shaders_test.dart
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_shaders/flutter3d_shaders.dart'
    show EngineBundleStamp;
import 'package:flutter3d_webgpu/engine_shaders.dart';
import 'package:flutter3d_webgpu/src/webgpu_bundle_section.dart';
import 'package:flutter3d_webgpu/src/webgpu_project_shaders.dart';
import 'package:flutter_test/flutter_test.dart';

/// A project bundle with [sections], stamped as the hook stamps one.
ByteData _bundle(Map<String, ByteData> sections) =>
    const EngineBundleStamp(dart: '3.13.0', engine: 'abc123', stages: 2)
        .bundle(
          stages: const <ShaderBundleStage>[
            ShaderBundleStage('MeshVertex', fragment: false),
            ShaderBundleStage('Unlit', fragment: true),
          ],
          sections: sections,
        )
        .encode();

ByteData _json(Object document) =>
    Uint8List.fromList(utf8.encode(jsonEncode(document))).buffer.asByteData();

/// Two of the compiled table's own stages, as a section.
ByteData _section() => encodeWebGpuSection(
  vertex: <String, WebGpuStage>{
    'MeshVertex': webGpuEngineShaders.vertex['MeshVertex']!,
  },
  fragment: <String, WebGpuStage>{
    'Unlit': webGpuEngineShaders.fragment['Unlit']!,
  },
);

void main() {
  test('no bundle is the compiled table', () {
    expect(projectWebGpuStages(null), isNull);
  });

  test("the project's webgpu section is what the device opens over", () {
    // Mutation: return null whatever the bundle holds, and the device opens
    // over the whole compiled table in a project that chose its stages.
    final stages = projectWebGpuStages(
      _bundle(<String, ByteData>{ShaderBundle.webgpuSection: _section()}),
    )!;
    expect(stages.vertex.keys, <String>['MeshVertex']);
    expect(stages.fragment.keys, <String>['Unlit']);
    expect(
      stages.fragment['Unlit']!.wgsl,
      webGpuEngineShaders.fragment['Unlit']!.wgsl,
    );
  });

  test('a bundle with no webgpu section is the compiled table', () {
    // A build on a machine without glslang and naga writes the WebGL2
    // section alone.
    expect(
      projectWebGpuStages(
        _bundle(<String, ByteData>{
          ShaderBundle.webglSection: _json(<String, Object>{
            'vertex': <String, String>{},
            'fragment': <String, String>{},
          }),
        }),
      ),
      isNull,
    );
  });

  test('a bundle that cannot be read is refused, naming the asset', () {
    final notABundle = Uint8List.fromList(utf8.encode('not a bundle'));
    expect(
      () => projectWebGpuStages(notABundle.buffer.asByteData()),
      throwsA(
        isA<ShaderBundleException>().having(
          (e) => e.asset,
          'asset',
          EngineBundleStamp.projectAsset,
        ),
      ),
    );
  });

  test('a section newer than this reader is refused as stale', () {
    expect(
      () => projectWebGpuStages(
        _bundle(<String, ByteData>{
          ShaderBundle.webgpuSection: _json(<String, Object>{
            'version': 99,
            'vertex': <String, Object>{},
            'fragment': <String, Object>{},
          }),
        }),
      ),
      throwsA(
        isA<ShaderBundleException>()
            .having((e) => e.stale, 'stale', isTrue)
            .having((e) => e.asset, 'asset', EngineBundleStamp.projectAsset),
      ),
    );
  });
}
