/// The resolve's depth test weighs the four history texels around the
/// reprojected point one by one, and never tests a blend of their depths.
///
///     dart test test/temporal_depth_trust_test.dart
///
/// Run against buffers written by hand rather than a rendered scene: an eight
/// by eight frame of one surface five metres off, a history whose left half
/// was that surface and whose right half was a wall at ten, and a motion of
/// half a texel. A pixel whose history lands on the seam between the two has
/// one texel of its own surface under it and one of the wall; a bilinear read
/// of the depths gives seven and a half, which is neither, and would drop the
/// history the surface does have.
library;

import 'dart:typed_data';

import 'package:flutter3d_cpu/src/cpu_shader_bindings.dart';
import 'package:flutter3d_cpu/src/cpu_shader_stage.dart';
import 'package:flutter3d_cpu/src/cpu_shaders_temporal.dart';
import 'package:flutter3d_cpu/src/cpu_texture.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _size = 8;

/// How much of each pixel is history when it is trusted in full.
const double _share = 0.9;

CpuTexture _filled(double Function(int x, int y, int channel) value) {
  final texture = CpuTexture(_size, _size, TextureFormat.r32g32b32a32Float);
  for (var y = 0; y < _size; y++) {
    for (var x = 0; x < _size; x++) {
      for (var c = 0; c < 4; c++) {
        texture.pixels[(y * _size + x) * 4 + c] = value(x, y, c);
      }
    }
  }
  return texture;
}

/// [TemporalResolveShader] at pixel ([x], 4), with the motion [motionX] in
/// uv and the history grey everywhere.
Vector4 _resolve(int x, double motionX) {
  // A checkerboard, so the neighbourhood's box spans the grey history and
  // the clip leaves it as it is.
  final scene = _filled((x, y, c) => c == 3 ? 1.0 : ((x + y).isEven ? 1.0 : 0.0));
  final surface = _filled((x, y, c) => c == 3 ? 5.0 : 0.0);
  final velocity = _filled((x, y, c) => c == 0 ? motionX : 0.0);
  final history = _filled(
    (x, y, c) => c == 3 ? (x < _size ~/ 2 ? 5.0 : 10.0) : 0.5,
  );
  final bindings = ShaderBindings(
    <String, Map<String, Float32List>>{
      'TemporalInfo': <String, Float32List>{
        'scene_texel': Float32List.fromList(<double>[
          1.0 / _size,
          1.0 / _size,
          _size.toDouble(),
          _size.toDouble(),
        ]),
        'jitter': Float32List.fromList(<double>[0.0, 0.0, _share, 1.0]),
        'params': Float32List.fromList(<double>[
          0.0,
          0.1,
          _size.toDouble(),
          _size.toDouble(),
        ]),
        'clip': Float32List(4),
        'clip_axes': Float32List(64),
      },
    },
    <String, BoundTexture>{
      'scene_texture': BoundTexture(scene, SamplerOptions.linearClamp),
      // Filtered, as the pass binds it for the colour's Catmull-Rom.
      'history_texture': BoundTexture(history, SamplerOptions.linearClamp),
      'velocity_texture': BoundTexture(velocity, SamplerOptions.nearestClamp),
      'surface_texture': BoundTexture(surface, SamplerOptions.nearestClamp),
    },
  );
  return const TemporalResolveShader().run(
    Float32List.fromList(<double>[(x + 0.5) / _size, 4.5 / _size]),
    bindings,
    FragmentContext(),
  )!;
}

/// What the resolve gives a pixel whose own colour is [current] when it
/// keeps [trust] of the history's share.
double _blend(double current, double trust) =>
    current * (1.0 - _share * trust) + 0.5 * _share * trust;

void main() {
  const half = 0.5 / _size;

  test('a history on the seam keeps the half that is the same surface', () {
    // Pixel 4 reprojects to the edge between texels 3 (five) and 4 (ten).
    // Mutation: test `history.sample(thenU, thenW).w` as one depth. The
    // blend is seven and a half, a third away from five, and the pixel
    // comes out as this frame alone.
    final out = _resolve(4, half);
    expect(out.x, closeTo(_blend(1.0, 0.5), 1e-4));
    expect(out.w, 5.0);
  });

  test('a history wholly on the wall is dropped', () {
    // Pixel 6 reprojects between texels 5 and 6, both the wall.
    final out = _resolve(6, half);
    expect(out.x, closeTo(_blend(1.0, 0.0), 1e-4));
  });

  test('a history wholly on the surface is kept', () {
    // Pixel 2 reprojects between texels 1 and 2, both the surface.
    final out = _resolve(2, half);
    expect(out.x, closeTo(_blend(1.0, 1.0), 1e-4));
  });

  test('with nothing moving each pixel reads its own texel', () {
    // A still camera lands on texel centres: pixel 4 is the wall's texel
    // and pixel 3 the surface's, as before the four were weighed.
    expect(_resolve(4, 0.0).x, closeTo(_blend(1.0, 0.0), 1e-4));
    expect(_resolve(3, 0.0).x, closeTo(_blend(0.0, 1.0), 1e-4));
  });
}
