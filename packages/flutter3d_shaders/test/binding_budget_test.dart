// What WebGL2 promises a stage, held against what every stage keeps — `G3`.
//
// WebGL2 is the floor the engine is built to, and its guarantees are small:
// sixteen texture units a fragment stage may sample and twelve uniform blocks
// a stage may declare. A device may offer more and most desktops do; a phone's
// browser often offers exactly that. A stage over either compiles everywhere
// the tests run and fails to link on the one device nobody tested, so the
// count is taken from the compiled bundle's own table — the resources the
// compiler kept, not the ones the source mentions — and held here.
//
// The lit models bind eleven samplers today, and several items of the 0.8
// plan add more. Each is meant to pack rather than append (one irradiance
// atlas, one cluster texture, one LTC table); this is what says so when one
// does not.

import 'package:flutter3d_shaders/stage_bindings.dart';
import 'package:test/test.dart';

/// `MAX_TEXTURE_IMAGE_UNITS`, the minimum WebGL2 guarantees.
const int kWebGl2Samplers = 16;

/// `MAX_FRAGMENT_UNIFORM_BLOCKS` and `MAX_VERTEX_UNIFORM_BLOCKS`, the minimum
/// WebGL2 guarantees for each.
const int kWebGl2UniformBlocks = 12;

void main() {
  test('the table has every stage in it', () {
    // A table that lost its entries would hold every budget trivially.
    expect(stageBindings.length, greaterThan(40));
  });

  test('no stage samples more than WebGL2 guarantees', () {
    final over = <String, int>{
      for (final MapEntry(:key, :value) in stageBindings.entries)
        if (value.samplers.length > kWebGl2Samplers) key: value.samplers.length,
    };
    expect(
      over,
      isEmpty,
      reason:
          'these stages bind more than $kWebGl2Samplers samplers and will not '
          'link on a device that offers the minimum; pack the new data into '
          'a texture the stage already reads',
    );
  });

  test('no stage declares more uniform blocks than WebGL2 guarantees', () {
    final over = <String, int>{
      for (final MapEntry(:key, :value) in stageBindings.entries)
        if (value.blocks.length > kWebGl2UniformBlocks)
          key: value.blocks.length,
    };
    expect(over, isEmpty);
  });
}
