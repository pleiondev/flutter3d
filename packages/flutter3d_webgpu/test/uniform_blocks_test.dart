/// Two compilers, one layout — `H1`.
///
///     flutter test test/uniform_blocks_test.dart
///
/// `uniform_blocks.dart` is read off impellerc's reflection; the WebGPU table
/// in `engine_shaders.dart` is read off what glslang and naga made of the same
/// source. The typed blocks the renderer fills are built from the first and
/// the WebGPU backend packs by the second, so a member the two place
/// differently would be written to one offset and read from another. Every
/// member both of them name has to sit at the same byte and take the same
/// number of bytes.
library;

import 'package:flutter3d_shaders/uniform_blocks.dart';
import 'package:flutter3d_webgpu/engine_shaders.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every member sits where both compilers put it', () {
    final stages = {...engineShaders.vertex, ...engineShaders.fragment};
    var compared = 0;
    final disagreements = <String>[];
    for (final MapEntry(key: stage, value: wgsl) in stages.entries) {
      for (final block in wgsl.blocks) {
        final layout = uniformBlocks[stage]?[block.name];
        if (layout == null) continue;
        for (final member in block.members) {
          final reflected = layout[member.name];
          if (reflected == null) continue;
          compared++;
          if (reflected.offset != member.offsetInBytes ||
              reflected.byteLength != member.sizeInBytes) {
            disagreements.add(
              '$stage.${block.name}.${member.name}: impellerc '
              '${reflected.offset}+${reflected.byteLength}, naga '
              '${member.offsetInBytes}+${member.sizeInBytes}',
            );
          }
        }
      }
    }
    // Hundreds, not a handful: a lookup that quietly found nothing would
    // agree with everything.
    expect(compared, greaterThan(200));
    expect(disagreements, isEmpty, reason: disagreements.join('\n'));
  });
}
