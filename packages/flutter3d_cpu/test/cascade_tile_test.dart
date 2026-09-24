/// The cascade filter stays inside its own tile.
///
///     dart test test/cascade_tile_test.dart
///
/// The cascades sit side by side in one texture. A fragment at the right edge
/// of the near tile filters over its neighbours, and the right-hand column of
/// that kernel lies in the next cascade's tile: a depth measured through
/// another projection, of another part of the scene. `ShadowFactor` holds every
/// tap inside the tile it chose, and this pins the Dart transcription to that.
library;

import 'dart:typed_data';

import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _tile = 8;

/// Two tiles: the near one empty, the far one an occluder in every texel.
BoundTexture _atlas() {
  final texture = CpuTexture(_tile * 2, _tile, TextureFormat.r16g16b16a16Float);
  for (var y = 0; y < _tile; y++) {
    for (var x = 0; x < _tile * 2; x++) {
      texture.pixels[(y * _tile * 2 + x) * 4] = x < _tile ? 1.0 : 0.0;
    }
  }
  return BoundTexture(texture, SamplerOptions.nearestClamp);
}

/// A fragment at [u] across the near tile, halfway down it, at depth 0.5.
double _shadowAt(double u) {
  final world = Vector3(u * 2.0 - 1.0, 0.0, 0.5);
  final surface = Surface(
    Vector3.all(1.0),
    1.0,
    // No normal, so no normal offset: the point projects where it stands.
    Vector3.zero(),
    world,
    Vector3.zero(),
    0.0,
    1.0,
    Vector3(0.0, 0.0, 1.0),
    1.0,
    Vector4.zero(),
  );
  final bindings = ShaderBindings(
    <String, Map<String, Float32List>>{
      'FragInfo': <String, Float32List>{
        // One atlas texel across, a bias, no normal offset, full strength.
        'shadow_params': Float32List.fromList(<double>[
          1.0 / (_tile * 2),
          0.001,
          0.0,
          1.0,
        ]),
        // The caster is light zero.
        'frame_params': Float32List(4),
        // Splits far out, so the near cascade is chosen; two cascades; one
        // tile texel down.
        'shadow_cascades': Float32List.fromList(<double>[
          100.0,
          200.0,
          2.0,
          1.0 / _tile,
        ]),
        'shadow_bias': Float32List.fromList(<double>[0.001, 0.001, 0.001, 0]),
        'shadow_matrix': Float32List.fromList(Matrix4.identity().storage),
        'shadow_matrix_far': Float32List.fromList(Matrix4.identity().storage),
        'camera_position': Float32List(4),
        'ambient_ground': Float32List(4),
      },
    },
    <String, BoundTexture>{'shadow_texture': _atlas()},
  );
  return shadowFactor(surface, bindings, 0, 1.0);
}

void main() {
  test('the middle of the near tile reads the near tile', () {
    expect(_shadowAt(0.5), 1.0);
  });

  test('the edge of the near tile does not read the next one', () {
    // Mutation: sample `u + x * texelU` without the clamp. The kernel's right
    // column lands in the far tile's occluder and three taps of nine say
    // shadow: 0.67 on a fragment nothing stands in front of.
    expect(_shadowAt(0.97), 1.0);
  });
}
