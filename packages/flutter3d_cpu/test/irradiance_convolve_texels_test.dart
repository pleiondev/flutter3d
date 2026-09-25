/// `IrradianceConvolveShader` reads every texel of the capture — `L4`.
///
///     dart test test/irradiance_convolve_texels_test.dart
///
/// A capture that is black but for one texel, lit in turn at every texel of
/// the face a probe direction looks at: each must move the probe's tile. A
/// fixed set of directions through the cube reached at most a few hundred of
/// its 1536 texels, so a lamp a texel wide was missed by one probe and
/// counted by the next, and the hysteresis never averaged that away because
/// every update asked the same directions.
library;

import 'dart:typed_data';

import 'package:flutter3d_cpu/src/cpu_shader_bindings.dart';
import 'package:flutter3d_cpu/src/cpu_shader_stage.dart';
import 'package:flutter3d_cpu/src/cpu_shaders_irradiance.dart';
import 'package:flutter3d_cpu/src/cpu_texture.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _side = 16;

/// One probe's atlas: a 4-texel irradiance tile over a 4-texel moment tile,
/// each with its gutter, so six wide and twelve tall.
const double _atlasWidth = 6;
const double _atlasHeight = 12;
const double _momentsTop = 6;

/// A cube of [_side] holding [value] in every channel but for [lit], the
/// texel (face, column, row) that holds [litValue].
CpuTexture _cube(double value, (int, int, int)? lit, double litValue) {
  CpuTexture face(int index) {
    final texture = CpuTexture(_side, _side, TextureFormat.r32g32b32a32Float);
    for (var i = 0; i < _side * _side; i++) {
      final here =
          lit != null && lit.$1 == index && i == lit.$3 * _side + lit.$2;
      texture.pixels.fillRange(i * 4, i * 4 + 4, here ? litValue : value);
    }
    return texture;
  }

  return CpuTexture(_side, _side, TextureFormat.r32g32b32a32Float)
    ..faces = <CpuTexture>[for (var i = 0; i < 6; i++) face(i)];
}

/// The fresh value the kernel writes at atlas texel ([x], [y]), nothing of
/// the old one kept.
Vector4 _convolve(int x, int y, CpuTexture radiance, CpuTexture surface) {
  final bindings = ShaderBindings(
    <String, Map<String, Float32List>>{
      'ConvolveInfo': <String, Float32List>{
        'probe': Float32List.fromList(<double>[0, 0, 0, 1]),
        'tiles': Float32List.fromList(<double>[4, 4, _momentsTop, 64]),
        'atlas': Float32List.fromList(<double>[
          _atlasWidth,
          _atlasHeight,
          _side.toDouble(),
          0,
        ]),
      },
    },
    <String, BoundTexture>{
      'field_texture': BoundTexture(
        CpuTexture(6, 12, TextureFormat.r32g32b32a32Float),
        SamplerOptions.nearestClamp,
      ),
      'radiance_texture': BoundTexture(radiance, SamplerOptions.linearClamp),
      'surface_texture': BoundTexture(surface, SamplerOptions.nearestClamp),
    },
  );
  return const IrradianceConvolveShader().run(
    Float32List.fromList(<double>[
      (x + 0.5) / _atlasWidth,
      (y + 0.5) / _atlasHeight,
    ]),
    bindings,
    FragmentContext(),
  )!;
}

void main() {
  // Interior texel (3, 1) of a 4-texel tile decodes to about (0.95, −0.32,
  // 0): every texel of the +X face is in front of it.
  const x = 1 + 3;
  const y = 1 + 1;

  test('a uniform capture convolves to itself', () {
    final got = _convolve(x, y, _cube(0.7, null, 0), _cube(2.0, null, 0));
    expect(got.x, closeTo(0.7, 1e-5));
  });

  test('every texel of the face in front counts for irradiance', () {
    final surface = _cube(2.0, null, 0);
    for (var row = 0; row < _side; row++) {
      for (var column = 0; column < _side; column++) {
        final got = _convolve(x, y, _cube(0.0, (0, column, row), 1.0), surface);
        // Mutation: the 64 fixed Fibonacci directions. Most texels are
        // never sampled and read exactly nothing.
        expect(got.x, greaterThan(1e-5), reason: 'texel ($column, $row)');
      }
    }
  });

  test('every texel of the face in front counts for the moments', () {
    final radiance = _cube(0.0, null, 0);
    final far = _convolve(
      x,
      _momentsTop.toInt() + y,
      radiance,
      _cube(2.0, null, 0),
    );
    for (var row = 0; row < _side; row++) {
      for (var column = 0; column < _side; column++) {
        final got = _convolve(
          x,
          _momentsTop.toInt() + y,
          radiance,
          _cube(2.0, (0, column, row), 1.0),
        );
        expect(got.x, lessThan(far.x - 1e-7), reason: 'texel ($column, $row)');
      }
    }
  });
}
