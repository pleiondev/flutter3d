/// Screen-space patterns land on the same pixels whichever way a backend
/// counts its rows, and the hashed splat's offset is the same number on a GPU.
///
///     dart test test/frag_coord_patterns_test.dart
///
/// WebGL2 counts rows from the bottom, the other backends from the top, and
/// `FragCoordFromTop` is what turns the first into the second. The software
/// rasteriser always counts from the top, so it never sees the difference on
/// its own. These tests hand the Dart mirrors the other convention — the
/// rows in the block, `gl_FragCoord` counted from the bottom — and hold them
/// to the answer they give for the same pixel counted from the top: the
/// same arithmetic the GLSL runs on WebGL2.
library;

import 'dart:typed_data';

import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:test/test.dart';

const int _rows = 37;

FragmentContext _at(double x, double y) =>
    FragmentContext()..coord.setValues(x, y, 0.5, 1.0);

/// [value] rounded to a 32-bit float, as a GPU would hold it.
double _f32(double value) => (Float32List(1)..[0] = value)[0];

/// `mod` as GLSL defines it, every step rounded to 32 bits.
double _mod32(double x, double y) =>
    _f32(x - _f32(y * _f32(_f32(x / y).floorToDouble())));

/// [splatNoiseOffset] with every intermediate a 32-bit float.
(double, double) _offset32(double identity) {
  final affine = _mod32(_f32(_f32(identity * 1597.0) + 2531.0), 4096.0);
  final mixed = _mod32(
    _f32(affine * _mod32(_f32(_f32(2.0 * affine) + 1.0), 4096.0)),
    4096.0,
  );
  final row = _f32(_f32(mixed / 64.0).floorToDouble());
  return (_mod32(_f32(mixed + _f32(row * 37.0)), 64.0), row);
}

void main() {
  test('the sun shadow turns its kernel on the same pixel counted either '
      'way', () {
    // Mutation: read `c.coord.y` in `shadowNoise` without the rows — the
    // bottom-counted pixel then gets another rotation and this fails.
    ShaderBindings bindings(double rows) => ShaderBindings(
      <String, Map<String, Float32List>>{
        'FragInfo': <String, Float32List>{
          'target_origin': Float32List.fromList(<double>[rows, 0.0, 0.0, 3.0]),
        },
      },
      const <String, BoundTexture>{},
    );
    for (var y = 0; y < _rows; y++) {
      for (var x = 0; x < 8; x++) {
        final fromTop = shadowNoise(bindings(0.0), _at(x + 0.5, y + 0.5));
        final fromBottom = shadowNoise(
          bindings(_rows.toDouble()),
          _at(x + 0.5, _rows - y - 0.5),
        );
        expect(fromBottom, closeTo(fromTop, 1e-9), reason: 'pixel ($x, $y)');
      }
    }
  });

  test('a hashed splat keeps the same pixels counted either way', () {
    // Mutation: drop the `frame.y` row flip from `SplatHashedShader` — the
    // bottom-counted run reads the tile upside down and keeps other pixels.
    final noise = CpuTexture(512, 256, TextureFormat.r32g32b32a32Float);
    for (var i = 0; i < 512 * 256; i++) {
      noise.pixels[i * 4] = ((i * 2654435761) % 251) / 251.0;
    }
    ShaderBindings bindings(double rows) => ShaderBindings(
      <String, Map<String, Float32List>>{
        'SplatHashInfo': <String, Float32List>{
          'frame': Float32List.fromList(<double>[5.0, rows, 0.0, 0.0]),
          'eye': Float32List.fromList(<double>[0.0, 0.0, 5.0, 0.0]),
          'forward': Float32List.fromList(<double>[0.0, 0.0, -1.0, 0.0]),
        },
      },
      <String, BoundTexture>{
        'blue_noise_texture': BoundTexture(noise, SamplerOptions.nearestClamp),
      },
    );
    final varyings = Float32List.fromList(<double>[
      0.8, 0.3, 0.1, 0.5, // colour, half opaque
      0.0, 0.0, // the Gaussian's centre
      0.0, 0.0, 1.25, // world position
    ]);
    const shader = SplatHashedShader();
    var kept = 0;
    for (var y = 0; y < _rows; y++) {
      for (var x = 0; x < 16; x++) {
        final fromTop = shader.run(
          varyings,
          bindings(0.0),
          _at(x + 0.5, y + 0.5),
        );
        final fromBottom = shader.run(
          varyings,
          bindings(_rows.toDouble()),
          _at(x + 0.5, _rows - y - 0.5),
        );
        expect(fromBottom == null, fromTop == null, reason: 'pixel ($x, $y)');
        if (fromTop != null) kept++;
      }
    }
    // Neither all nor none, or the comparison above proves nothing.
    expect(kept, inExclusiveRange(0, _rows * 16));
  });

  test('the splat offset gives each identity its own cell, and a GPU the '
      'same one', () {
    // Mutation: go back to `fract(sin(identity * k) * 43758.5453)` — cells
    // repeat, and the 32-bit run parts from the 64-bit one.
    final cells = <int>{};
    for (var identity = 0; identity < 4096; identity++) {
      final (x, y) = splatNoiseOffset(identity.toDouble());
      expect(x, inInclusiveRange(0.0, 63.0));
      expect(y, inInclusiveRange(0.0, 63.0));
      expect(x, x.floorToDouble());
      expect(y, y.floorToDouble());
      cells.add(y.toInt() * 64 + x.toInt());
      expect(_offset32(identity.toDouble()), (
        x,
        y,
      ), reason: 'identity $identity in 32-bit floats');
    }
    expect(cells, hasLength(4096));
  });
}
