/// The depth pyramid says how flat each block was, not just how far.
///
///     dart test test/depth_pyramid_test.dart
///
/// `HiZOcclusion` moves each cell of the reading as one plane at its
/// farthest depth, and drops it once its nearest depth would part from that
/// plane: a post in front of a doorway. It can only do that if the pass
/// writes the nearest depth, as 128 plus 127ths of the farthest in alpha.
/// This pins the Dart transcription of `depth_pyramid.frag` to that.
library;

import 'dart:typed_data';

import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:test/test.dart';

/// One cell reduced from a 4 × 4 surface buffer whose view depth at column
/// x is [depthAt]; the cell's alpha as a byte.
int _alpha(double Function(int x) depthAt) {
  final texture = CpuTexture(4, 4, TextureFormat.r16g16b16a16Float);
  for (var y = 0; y < 4; y++) {
    for (var x = 0; x < 4; x++) {
      texture.pixels[(y * 4 + x) * 4 + 3] = depthAt(x);
    }
  }
  final bindings = ShaderBindings(
    <String, Map<String, Float32List>>{
      'DepthPyramidInfo': <String, Float32List>{
        'block': Float32List.fromList(<double>[1.0, 1.0, 4.0, 4.0]),
        'range': Float32List.fromList(<double>[1.0 / 100.0, 0.0, 0.0, 0.0]),
      },
    },
    <String, BoundTexture>{
      'surface_texture': BoundTexture(texture, SamplerOptions.nearestClamp),
    },
  );
  final out = const DepthPyramidShader().run(
    Float32List.fromList(<double>[0.5, 0.5]),
    bindings,
    FragmentContext(),
  )!;
  return (out.w * 255.0).round();
}

void main() {
  test('a flat block is 255, one pixel of sky is zero', () {
    expect(_alpha((x) => 10.0), 255);
    expect(_alpha((x) => x == 0 ? 0.0 : 10.0), 0);
  });

  test('a post three metres out in front of a wall at ten is 128 + 38', () {
    // Mutation: write alpha one for every drawn block, as the pass did
    // before it kept the nearest depth — 255, a flat wall.
    expect(_alpha((x) => x < 2 ? 3.0 : 10.0), 128 + 38);
  });
}
