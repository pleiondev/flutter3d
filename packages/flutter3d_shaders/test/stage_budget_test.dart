/// A stage over WebGPU's binding budget is refused when its section is
/// written, not when a device makes its pipeline.
///
///     dart test test/stage_budget_test.dart
///
/// A plugin's lit model adds its own textures and blocks to the engine's,
/// and a WebGPU device guarantees 16 sampled textures, 16 samplers and 12
/// uniform buffers a stage. A stage past them built, packed and then failed
/// on the device at its first draw; the section writer every packer calls
/// refuses it with the stage and the count.
///
/// Mutation: compare with `>=` in `MaterialStageBudget.problem`, and a stage
/// of exactly sixteen textures is refused.
library;

import 'package:flutter3d_shaders/translate.dart';
import 'package:test/test.dart';

const String _fragment = '''
#version 460
layout(location = 0) out vec4 frag_color;
void main() { frag_color = vec4(1.0); }
''';

PackedStage _stage({int textures = 0, int blocks = 0}) => (
  wgsl: '',
  prepared: PreparedStage(
    glsl: _fragment,
    attributes: const <PreparedAttribute>[],
    blocks: <PreparedBlock>[
      for (var i = 0; i < blocks; i++)
        (
          name: 'Block$i',
          group: 1,
          binding: i,
          sizeInBytes: 16,
          members: const <PreparedMember>[],
        ),
    ],
    samplers: <PreparedSampler>[
      for (var i = 0; i < textures; i++)
        (
          name: 'map_$i',
          group: 2,
          textureBinding: 2 * i,
          samplerBinding: 2 * i + 1,
          dimension: 'twoDimensional',
        ),
    ],
  ),
);

Matcher _refused(String saying) => throwsA(
  isA<WgslSectionException>().having(
    (WgslSectionException e) => e.message,
    'message',
    allOf(contains('"Hair"'), contains(saying), contains('WebGPU')),
  ),
);

void main() {
  test('a stage at the budget is written', () {
    expect(
      wgslSectionDocument(
        vertex: const <String, PackedStage>{},
        fragment: <String, PackedStage>{
          'Hair': _stage(
            textures: MaterialStageBudget.textures,
            blocks: MaterialStageBudget.uniformBlocks,
          ),
        },
      ),
      contains('"Hair"'),
    );
  });

  test('a texture past the budget is refused, naming the count', () {
    expect(
      () => wgslSectionDocument(
        vertex: const <String, PackedStage>{},
        fragment: <String, PackedStage>{'Hair': _stage(textures: 17)},
      ),
      _refused('binds 17 textures'),
    );
  });

  test('a uniform block past the budget is refused', () {
    expect(
      () => wgslSectionDocument(
        vertex: const <String, PackedStage>{},
        fragment: <String, PackedStage>{'Hair': _stage(blocks: 13)},
      ),
      _refused('binds 13 uniform blocks'),
    );
  });
}
