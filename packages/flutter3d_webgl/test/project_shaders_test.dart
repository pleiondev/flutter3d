/// Which stages a WebGL2 device opens over when it is handed none: the
/// project's bundle where it carries a `webgl` section, the compiled table
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
import 'package:flutter3d_shaders/translate.dart' show encodeWebGlSection;
import 'package:flutter3d_webgl/src/webgl_project_shaders.dart';
import 'package:flutter_test/flutter_test.dart';

const String _vertex =
    '#version 300 es\nvoid main() { gl_Position = vec4(0); }\n';
const String _fragment =
    '#version 300 es\nprecision highp float;\nout vec4 c;\n'
    'void main() { c = vec4(1); }\n';

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

void main() {
  test('no bundle is the compiled table', () {
    expect(projectWebGlSources(null), isNull);
  });

  test("the project's webgl section is what the device opens over", () {
    // Mutation: return null whatever the bundle holds, and the device opens
    // over the whole compiled table in a project that chose its stages.
    final sources = projectWebGlSources(
      _bundle(<String, ByteData>{
        ShaderBundle.webglSection: encodeWebGlSection(
          vertex: const <String, String>{'MeshVertex': _vertex},
          fragment: const <String, String>{'Unlit': _fragment},
        ),
      }),
    )!;
    expect(sources.vertex.keys, <String>['MeshVertex']);
    expect(sources.fragment['Unlit'], _fragment);
  });

  test('a bundle written for a native target alone is the compiled table', () {
    expect(
      projectWebGlSources(
        _bundle(<String, ByteData>{ShaderBundle.impellerSection: ByteData(4)}),
      ),
      isNull,
    );
  });

  test('a bundle that cannot be read is refused, naming the asset', () {
    // Mutation: answer null for bytes that are not a bundle, and a broken
    // build draws with stages it did not choose.
    final notABundle = Uint8List.fromList(utf8.encode('not a bundle'));
    expect(
      () => projectWebGlSources(notABundle.buffer.asByteData()),
      throwsA(
        isA<ShaderBundleException>().having(
          (e) => e.asset,
          'asset',
          EngineBundleStamp.projectAsset,
        ),
      ),
    );
    expect(
      () => projectWebGlSources(
        _bundle(<String, ByteData>{
          ShaderBundle.webglSection: Uint8List.fromList(
            utf8.encode('[1, 2]'),
          ).buffer.asByteData(),
        }),
      ),
      throwsA(
        isA<ShaderBundleException>()
            .having((e) => e.asset, 'asset', EngineBundleStamp.projectAsset)
            .having((e) => e.reason, 'reason', contains('webgl')),
      ),
    );
  });
}
