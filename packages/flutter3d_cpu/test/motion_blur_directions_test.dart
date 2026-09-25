/// A pixel in a neighbourhood of two motions is blurred along its own — `R6`.
///
///     dart test test/motion_blur_directions_test.dart
///
/// Run against buffers written by hand rather than a rendered scene: every
/// pixel moves six pixels down either side of the exposure, and the scene is
/// stripes of red and black, so a streak along them changes nothing and a
/// streak across them greys them. The tile neighbourhood says something
/// faster moves sideways somewhere near, which is what a wheel's rim or a
/// passing object tells the pixels beside it.
library;

import 'dart:typed_data';

import 'package:flutter3d_cpu/src/cpu_shader_bindings.dart';
import 'package:flutter3d_cpu/src/cpu_shader_stage.dart';
import 'package:flutter3d_cpu/src/cpu_shaders_motion_blur.dart';
import 'package:flutter3d_cpu/src/cpu_texture.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _size = 40;
const int _tile = 20;

CpuTexture _filled(int width, int height, List<double> Function(int, int) at) {
  final texture = CpuTexture(width, height, TextureFormat.r32g32b32a32Float);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      texture.pixels.setAll((y * width + x) * 4, at(x, y));
    }
  }
  return texture;
}

/// [MotionBlurShader] at pixel ([x], [y]), every pixel moving [own] and the
/// neighbourhood's longest motion [dominant], both in pixels. The stripes
/// run down the columns, or along the rows with [rows].
Vector4 _blurred(
  int x,
  int y, {
  required Vector2 own,
  required Vector2 dominant,
  bool rows = false,
}) {
  final scene = _filled(
    _size,
    _size,
    (x, y) => <double>[(rows ? y : x).isOdd ? 1.0 : 0.0, 0.0, 0.0, 1.0],
  );
  final velocity = _filled(
    _size,
    _size,
    (_, _) => <double>[own.x, own.y, 0, 0],
  );
  final surface = _filled(_size, _size, (_, _) => <double>[0, 0, 0, 5.0]);
  const tiles = _size ~/ _tile;
  final neighbors = _filled(
    tiles,
    tiles,
    (_, _) => <double>[dominant.x, dominant.y, 0, 1],
  );

  final bindings = ShaderBindings(
    <String, Map<String, Float32List>>{
      'MotionBlurInfo': <String, Float32List>{
        'scene': Float32List.fromList(<double>[
          1.0 / _size,
          1.0 / _size,
          _size.toDouble(),
          _size.toDouble(),
        ]),
        // Velocities already in pixels, a long bound, fifteen samples.
        'params': Float32List.fromList(<double>[1.0, 1.0, 32.0, 15.0]),
        'tiles': Float32List.fromList(<double>[
          tiles.toDouble(),
          tiles.toDouble(),
          _tile.toDouble(),
          0.1,
        ]),
      },
    },
    <String, BoundTexture>{
      for (final (name, texture) in <(String, CpuTexture)>[
        ('scene_texture', scene),
        ('velocity_texture', velocity),
        ('surface_texture', surface),
        ('neighbor_texture', neighbors),
      ])
        name: BoundTexture(texture, SamplerOptions.nearestClamp),
    },
  );
  final context = FragmentContext();
  context.coord
    ..x = x + 0.5
    ..y = y + 0.5;
  return const MotionBlurShader().run(
    Float32List.fromList(<double>[(x + 0.5) / _size, (y + 0.5) / _size]),
    bindings,
    context,
  )!;
}

void main() {
  test('a pixel moving down is not smeared across by a sideways '
      'neighbour', () {
    // Mutation: weigh every sample as though its streak ran along the line
    // sampled (`ownAlong` and `tapAlong` one), as the 2012 filter does. The
    // columns either side are gathered in and the red pixel comes out about
    // half grey.
    for (final (x, y) in <(int, int)>[(19, 19), (21, 10), (9, 30)]) {
      final red = _blurred(
        x,
        y,
        own: Vector2(0.0, 6.0),
        dominant: Vector2(8.0, 0.0),
      ).x;
      expect(red, closeTo(1.0, 1e-6), reason: 'at ($x, $y)');
    }
  });

  test('a pixel moving down is smeared down, whatever its neighbour '
      'does', () {
    // Stripes along the rows now, which only a streak down the picture
    // greys. Mutation: put every sample on the neighbourhood's line
    // (`onMine` false), as the 2012 filter does. Nothing is sampled down the
    // pixel's own motion and it keeps its red. Seven pixels rather than
    // eight: at eight every sample on the own line lands an even number of
    // rows away, on red again.
    final red = _blurred(
      19,
      19,
      own: Vector2(0.0, 6.0),
      dominant: Vector2(7.0, 0.0),
      rows: true,
    ).x;
    expect(red, inInclusiveRange(0.2, 0.8));
  });

  test('the same pixel moving sideways is smeared across', () {
    // The weights, seen from the other side: with its own motion along the
    // neighbourhood's, the pixel gathers the black columns beside it.
    final red = _blurred(
      19,
      19,
      own: Vector2(6.0, 0.0),
      dominant: Vector2(8.0, 0.0),
    ).x;
    expect(red, inInclusiveRange(0.2, 0.8));
  });
}
