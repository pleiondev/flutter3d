/// The horizon slices are measured from the right zenith, with the normal
/// kept on the eye's side of it — `L5`.
///
///     dart test test/gtao_view_test.dart
///
/// Run against a surface buffer written by hand: a bare wall facing the eye,
/// with nothing standing proud of it, so every pixel should come out as open
/// as the wall's own normal allows.
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

const int _size = 64;
const double _depth = 2.0;

/// [SsaoShader] at pixel [x], [y] of a square target whose buffer is a wall
/// [_depth] metres in front of an eye at the origin looking down -z, every
/// pixel's normal facing the eye except the shaded one's, which is
/// [normal].
Vector4 _shade({
  required Matrix4 projection,
  required double pixel,
  required double method,
  required int x,
  required int y,
  Vector3? normal,
}) {
  final view = makeViewMatrix(
    Vector3.zero(),
    Vector3(0.0, 0.0, -1.0),
    Vector3(0.0, 1.0, 0.0),
  );
  final viewProjection = projection.multiplied(view);
  final wall = encodeOctahedral(Vector3(0.0, 0.0, 1.0));
  final shaded = encodeOctahedral(normal ?? Vector3(0.0, 0.0, 1.0));
  final surface = CpuTexture(_size, _size, TextureFormat.r32g32b32a32Float);
  final scene = CpuTexture(_size, _size, TextureFormat.r32g32b32a32Float);
  for (var py = 0; py < _size; py++) {
    for (var px = 0; px < _size; px++) {
      final encoded = px == x && py == y ? shaded : wall;
      final at = (py * _size + px) * 4;
      surface.pixels
        ..[at] = encoded.x
        ..[at + 1] = encoded.y
        ..[at + 3] = _depth;
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
        'params': Float32List.fromList(<double>[pixel * 12.0, 16.0, 0.0, 0.0]),
        'screen': Float32List.fromList(<double>[
          1.0 / _size,
          1.0 / _size,
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
    Float32List.fromList(<double>[(x + 0.5) / _size, (y + 0.5) / _size]),
    bindings,
    FragmentContext(),
  )!;
}

void main() {
  // Twenty metres across at two deep: the frame's corner is about seventy
  // degrees off the view axis as seen from the camera position.
  const extent = 10.0;
  final orthographic = makeOrthographicMatrix(
    -extent,
    extent,
    -extent,
    extent,
    0.1,
    100.0,
  );

  test('a bare wall under an orthographic camera is open to the corner', () {
    double at(int x, int y) => _shade(
      projection: orthographic,
      pixel: 2.0 * extent / _size,
      method: 1.0,
      x: x,
      y: y,
    ).x;
    final centre = at(_size ~/ 2, _size ~/ 2);
    final corner = at(4, 5);
    expect(centre, closeTo(1.0, 1e-3));
    // Mutation: measure from the camera position, as before. The zenith
    // tilts off the slice towards the corner and the wall there comes out
    // under half open.
    expect(corner, closeTo(centre, 1e-3));
  });

  test('a normal turned away from the eye is held at the grazing edge', () {
    const fovY = math.pi / 3.0;
    final perspective = makePerspectiveMatrix(fovY, 1.0, 0.1, 100.0);
    final pixel = 2.0 * _depth * math.tan(fovY / 2.0) / _size;
    // The middle pixel: its two slices run straight across and straight
    // down, and the eye looks squarely at the wall.
    double visibility(Vector3 normal) => _shade(
      projection: perspective,
      pixel: pixel,
      method: 1.0,
      x: _size ~/ 2,
      y: _size ~/ 2,
      normal: normal..normalize(),
    ).x;
    final away = visibility(Vector3(0.3, 0.0, -1.0));
    // Held at the edge of the eye's half circle, a slice across an open wall
    // keeps a quarter of the arc, pi / 4, times the normal's length in it.
    // Mutation: clamp the cosine to [-1, 1], as before. The angle passes a
    // quarter turn, the horizon lands on the wrong side of the zenith and the
    // arc takes visibility away, leaving the open wall a dark speck.
    expect(away, greaterThan(0.7));
    expect(away, lessThanOrEqualTo(1.0));
  });
}
