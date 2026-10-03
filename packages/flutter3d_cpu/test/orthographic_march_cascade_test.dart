/// The cascade a light shaft or the volumetric fog reads, through an
/// orthographic lens — `P7`.
///
///     dart test test/orthographic_march_cascade_test.dart
///
/// Both passes march from the eye's plane and pick a cascade for each step by
/// the way along the ray from there, which is the metric `shadow.glsl` picks a
/// surface's cascade by: the distance from the eye through a perspective lens,
/// the depth along the axis through an orthographic one. Picked by distance
/// from the eye's point instead, a step at the edge of an orthographic frame
/// is counted as far as the frame is wide, passes the split it is well inside
/// by depth, and reads a later tile than the ground under it. This pins the
/// Dart transcriptions to `light_shafts.frag` and `volumetric_fog.frag`.
library;

import 'dart:typed_data';

import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _tile = 8;

/// Two tiles: the near one empty, the far one an occluder in every texel
/// unless [farLit] — so the answer says which tile was read.
BoundTexture _atlas({required bool farLit}) {
  final texture = CpuTexture(_tile * 2, _tile, TextureFormat.r16g16b16a16Float);
  for (var y = 0; y < _tile; y++) {
    for (var x = 0; x < _tile * 2; x++) {
      texture.pixels[(y * _tile * 2 + x) * 4] = x < _tile || farLit ? 1.0 : 0.0;
    }
  }
  return BoundTexture(texture, SamplerOptions.nearestClamp);
}

/// One black texel, for the scene and for a surface buffer with nothing in
/// it, so the march runs its whole length.
BoundTexture _black() => BoundTexture(
  CpuTexture(1, 1, TextureFormat.r16g16b16a16Float),
  SamplerOptions.nearestClamp,
);

Float32List _vec4(double x, double y, double z, double w) =>
    Float32List.fromList(<double>[x, y, z, w]);

/// What both passes share: an orthographic view a hundred metres wide looking
/// along +z from the origin, thirty metres of march, two cascades split at
/// forty metres, and a light space a hundred and twenty metres across that
/// holds the whole march.
Map<String, Float32List> _march() => <String, Float32List>{
  'forward': _vec4(0.0, 0.0, 1.0, 16.0),
  // Clip to world: x and y fifty metres each way, depth nought to a hundred,
  // and no perspective divide — the rays are parallel.
  'inverse_view_projection': Float32List.fromList(
    Matrix4.diagonal3Values(50.0, 50.0, 100.0).storage,
  ),
  'camera': _vec4(0.0, 0.0, 0.0, 30.0),
  'cascades': _vec4(40.0, 200.0, 2.0, 0.0),
  'bias': _vec4(0.001, 0.001, 0.001, 0.0),
  for (final name in <String>[
    'shadow_matrix',
    'shadow_matrix_far',
    'shadow_matrix_farthest',
  ])
    name: Float32List.fromList(
      Matrix4.diagonal3Values(1.0 / 60.0, 1.0 / 60.0, 1.0 / 100.0).storage,
    ),
  'sun': _vec4(0.0, -1.0, 0.0, 0.0),
};

/// The pixel nine tenths of the way to the right edge: forty-five metres off
/// the axis, so every step of the march is past the split by distance from
/// the eye and inside it by depth.
final Float32List _edge = Float32List.fromList(<double>[0.95, 0.5]);

double _shafts({required bool farLit}) {
  final bindings = ShaderBindings(
    <String, Map<String, Float32List>>{
      'ShaftInfo': <String, Float32List>{
        ..._march(),
        'scatter': _vec4(1.0, 1.0, 1.0, 0.05),
      },
    },
    <String, BoundTexture>{
      'scene_texture': _black(),
      'surface_texture': _black(),
      'shadow_texture': _atlas(farLit: farLit),
    },
  );
  return builtinCpuShaders()['LightShafts']!.fragment!
      .run(_edge, bindings, FragmentContext())!
      .x;
}

double _fog({required bool farLit}) {
  final bindings = ShaderBindings(
    <String, Map<String, Float32List>>{
      'VolumeFogInfo': <String, Float32List>{
        ..._march(),
        'medium': _vec4(0.05, 0.0, 0.0, 0.0),
        'sun_radiance': _vec4(1.0, 1.0, 1.0, 0.0),
        'ambient': _vec4(0.0, 0.0, 0.0, 0.0),
        'albedo': _vec4(0.0, 0.0, 0.0, 0.0),
      },
    },
    <String, BoundTexture>{
      'surface_texture': _black(),
      'shadow_texture': _atlas(farLit: farLit),
    },
  );
  return builtinCpuShaders()['VolumetricFog']!.fragment!
      .run(_edge, bindings, FragmentContext())!
      .x;
}

void main() {
  test('a light shaft at the edge of an orthographic frame reads the near '
      'cascade', () {
    // Mutation: pick by `(at - eye).length` in `LightShaftsShader`, as before
    // `P7`. Every step is forty-five metres and more from the eye, past the
    // split, and reads the far tile's occluder: the shaft goes dark.
    final lit = _shafts(farLit: true);
    expect(lit, greaterThan(0.0), reason: 'the shaft scatters nothing');
    expect(_shafts(farLit: false), closeTo(lit, 1e-9));
  });

  test('the volumetric fog at the edge of an orthographic frame reads the '
      'near cascade', () {
    // Mutation: pick by `(at - eye).length` in `VolumetricFogShader`, as
    // before `P7`. The air reads the far tile's occluder and scatters only
    // the ambient, which is black here.
    final lit = _fog(farLit: true);
    expect(lit, greaterThan(0.0), reason: 'the fog scatters nothing');
    expect(_fog(farLit: false), closeTo(lit, 1e-9));
  });
}
