/// The horizon searches reach as far up the screen as across it, and the
/// indirect light comes only off surfaces that face the point — `L5`.
///
///     dart test test/ssao_slices_test.dart
///
/// Run against a surface buffer written by hand rather than a rendered scene:
/// a wall facing the eye five metres away, and a strip standing proud of it a
/// few pixels from the point being shaded. The same strip, turned a quarter,
/// must shade the point the same, on a wide target and a tall one. Where the
/// strip sits is chosen per shape so that a search stepped in uv misses it
/// one way: short of it up a wide target, past it up a tall one.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_cpu/src/cpu_shader_bindings.dart';
import 'package:flutter3d_cpu/src/cpu_shader_stage.dart';
import 'package:flutter3d_cpu/src/cpu_shaders_color.dart';
import 'package:flutter3d_cpu/src/cpu_shaders_ssao.dart';
import 'package:flutter3d_cpu/src/cpu_texture.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const double _depth = 5.0;

/// How many pixels the radius spans. At sixteen samples the steps land at an
/// eighth, three eighths, five eighths and seven eighths of it.
const int _reach = 24;

/// [SsaoShader] at the middle pixel of a [width] by [height] target whose
/// buffer is the wall, with the strip [down] from the point or to its right,
/// from [near] to [far] pixels away, standing three tenths of the radius
/// proud of the wall.
///
/// The middle pixel has a Bayer cell of nought, so its two slices run
/// straight across and straight down.
Vector4 _shade({
  required int width,
  required int height,
  required bool down,
  required double method,
  required int near,
  required int far,
  Vector3? stripNormal,
}) {
  final aspect = width / height;
  const fovY = math.pi / 3.0;
  final projection = makePerspectiveMatrix(fovY, aspect, 0.1, 100.0);
  final view = makeViewMatrix(
    Vector3.zero(),
    Vector3(0.0, 0.0, -1.0),
    Vector3(0.0, 1.0, 0.0),
  );
  final viewProjection = projection.multiplied(view);
  final pixel = 2.0 * _depth * math.tan(fovY / 2.0) / height;
  final radius = pixel * _reach;

  final cx = width ~/ 2;
  final cy = height ~/ 2;
  final wall = encodeOctahedral(Vector3(0.0, 0.0, 1.0));
  final strip = encodeOctahedral(stripNormal ?? Vector3(0.0, 0.0, 1.0));
  final surface = CpuTexture(width, height, TextureFormat.r32g32b32a32Float);
  final scene = CpuTexture(width, height, TextureFormat.r32g32b32a32Float);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final away = down ? y - cy : x - cx;
      final inStrip = away >= near && away <= far;
      final encoded = inStrip ? strip : wall;
      final at = (y * width + x) * 4;
      surface.pixels
        ..[at] = encoded.x
        ..[at + 1] = encoded.y
        ..[at + 3] = inStrip ? _depth - 0.3 * radius : _depth;
      scene.pixels.fillRange(at, at + 4, 1.0);
    }
  }

  final bindings = ShaderBindings(
    <String, Map<String, Float32List>>{
      'SsaoInfo': <String, Float32List>{
        'inverse_view_projection': Float32List.fromList(
          (Matrix4.copy(viewProjection)..invert()).storage,
        ),
        'view_projection': Float32List.fromList(viewProjection.storage),
        'params': Float32List.fromList(<double>[radius, 16.0, 0.0, 0.0]),
        'screen': Float32List.fromList(<double>[
          1.0 / width,
          1.0 / height,
          method,
          0.3,
        ]),
        'camera': Float32List(4),
        'forward': Float32List.fromList(<double>[0.0, 0.0, -1.0, 0.0]),
      },
    },
    <String, BoundTexture>{
      'surface_texture': BoundTexture(surface, SamplerOptions.nearestClamp),
      'scene_texture': BoundTexture(scene, SamplerOptions.nearestClamp),
    },
  );
  return const SsaoShader().run(
    Float32List.fromList(<double>[(cx + 0.5) / width, (cy + 0.5) / height]),
    bindings,
    FragmentContext(),
  )!;
}

void main() {
  for (final (name, method, channel) in <(String, double, int)>[
    ('the horizon search', 1.0, 0),
    ('the indirect light', 2.0, 3),
  ]) {
    // Wide: the strip at the second step, past where a search stepped in uv
    // stops going down. Tall: at the first, short of where that search's
    // first step lands going down.
    for (final (shape, width, height, near, far)
        in <(String, int, int, int, int)>[
          ('wide', 192, 64, 8, 11),
          ('tall', 64, 192, 2, 4),
        ]) {
      Vector4 shade({required bool down}) => _shade(
        width: width,
        height: height,
        down: down,
        method: method,
        near: near,
        far: far,
      );

      test('$name reaches as far down a $shape target as across it', () {
        final across = shade(down: false)[channel];
        final downwards = shade(down: true)[channel];
        // The strip is found at all: the bare wall is wholly open.
        expect(across, lessThan(0.99));
        // Mutation: step `uvRadius` in uv, as before. The search down misses
        // the strip that the search across finds.
        expect(downwards, closeTo(across, 0.005));
      });
    }
  }

  test('the indirect light comes off a strip facing the point, and only '
      'that', () {
    Vector4 light(Vector3 normal) => _shade(
      width: 192,
      height: 64,
      down: false,
      method: 2.0,
      near: 8,
      far: 11,
      stripNormal: normal..normalize(),
    );
    final facing = light(Vector3(-1.0, 0.0, 0.3));
    final away = light(Vector3(1.0, 0.0, 0.3));
    expect(facing.x, greaterThan(1e-3));
    // Mutation: drop the sample's own cosine. The strip's lit face, turned
    // from the point, lights it as much as one turned towards it.
    expect(away.x, closeTo(0.0, 1e-6));
    // What hides the hemisphere does not depend on which way the strip faces.
    expect(away.w, closeTo(facing.w, 1e-6));
  });
}
