/// What a see-through caster lets through is filtered as the opaque edge is.
///
///     dart test test/translucent_shadow_filter_test.dart
///
/// The shadow atlas is read without filtering, so one tap of the translucent
/// layer drew a glass's or a liquid's shadow edge as stairs a texel high.
/// `ShadowFactor` averages it over the same 3×3 texels as the opaque kernel,
/// and this pins the Dart transcription to that.
library;

import 'dart:typed_data';

import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_cpu/src/cpu_shaders_builtin.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _tile = 8;

/// One tile, nothing opaque in it, and a caster over its left half that
/// takes all the red and none of the rest.
BoundTexture _atlas() {
  final texture = CpuTexture(_tile, _tile, TextureFormat.r16g16b16a16Float);
  for (var y = 0; y < _tile; y++) {
    for (var x = 0; x < _tile; x++) {
      final i = (y * _tile + x) * 4;
      texture.pixels[i] = 1.0;
      texture.pixels[i + 1] = x < _tile ~/ 2 ? 1.0 : 0.0;
      texture.pixels[i + 2] = 0.0;
      texture.pixels[i + 3] = 1.0;
    }
  }
  return BoundTexture(texture, SamplerDescriptor.nearestClamp);
}

/// The red let through to a fragment at the centre of texel [column].
double _redThrough(int column) {
  final u = (column + 0.5) / _tile;
  final surface = Surface(
    Vector3.all(1.0),
    1.0,
    // No normal, so no normal offset: the point projects where it stands.
    Vector3.zero(),
    Vector3(u * 2.0 - 1.0, 0.0, 0.5),
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
        'shadow_params': Float32List.fromList(<double>[
          1.0 / _tile,
          0.001,
          0.0,
          1.0,
        ]),
        'frame_params': Float32List(4),
        'shadow_cascades': Float32List.fromList(<double>[
          100.0,
          200.0,
          1.0,
          1.0 / _tile,
        ]),
        // The fourth bias is the translucent-casters flag.
        'shadow_bias': Float32List.fromList(<double>[0.001, 0.001, 0.001, 1]),
        'shadow_matrix': Float32List.fromList(Matrix4.identity().storage),
        'camera_position': Float32List(4),
        'ambient_ground': Float32List(4),
      },
    },
    <String, BoundTexture>{'shadow_texture': _atlas()},
  );
  expect(shadowFactor(surface, bindings, 0, 1.0), 1.0);
  return shadowTransmittance.x;
}

void main() {
  test('well inside the caster nothing red gets through', () {
    expect(_redThrough(1), closeTo(0.0, 1e-6));
  });

  test('well outside it all of it does', () {
    expect(_redThrough(6), closeTo(1.0, 1e-6));
  });

  test('across the edge the light steps in thirds, not all at once', () {
    // Mutation: read the translucent layer in the one tap at the fragment.
    // The edge texels then say 0 and 1, the stair a texel high this filter
    // exists to smooth.
    expect(_redThrough(3), closeTo(1.0 / 3.0, 1e-3));
    expect(_redThrough(4), closeTo(2.0 / 3.0, 1e-3));
  });
}
