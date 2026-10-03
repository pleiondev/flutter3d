/// The cascade a fragment reads, through an orthographic lens — `P7`.
///
///     dart test test/orthographic_cascade_pick_test.dart
///
/// Through an orthographic lens the renderer cuts the near cascades as slabs
/// of depth along the view axis, because the eye is only where the camera was
/// put and its distance from a fragment is mostly how far back that was.
/// `ShadowFactor` has to pick by the same depth, or a fragment well inside
/// the first slab, but far from the eye, reads a later and coarser tile. This
/// pins the Dart transcription to `shadow.glsl`.
library;

import 'dart:typed_data';

import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _tile = 8;

/// Two tiles: the near one empty, the far one an occluder in every texel —
/// so the answer says which tile was read.
BoundTexture _atlas() {
  final texture = CpuTexture(_tile * 2, _tile, TextureFormat.r16g16b16a16Float);
  for (var y = 0; y < _tile; y++) {
    for (var x = 0; x < _tile * 2; x++) {
      texture.pixels[(y * _tile * 2 + x) * 4] = x < _tile ? 1.0 : 0.0;
    }
  }
  return BoundTexture(texture, SamplerOptions.nearestClamp);
}

/// A fragment at the middle of both tiles' projection, with the eye forty
/// metres back along z and four across in x: thirty metres of depth, more
/// than fifty of distance, against a first split at forty.
double _shadowThrough({required bool orthographic}) {
  final world = Vector3(0.0, 0.0, 0.5);
  final surface = Surface(
    Vector3.all(1.0),
    1.0,
    Vector3.zero(),
    world,
    Vector3.zero(),
    0.0,
    1.0,
    Vector3(0.0, 0.0, 1.0),
    1.0,
    Vector4.zero(),
  );
  final eye = <double>[40.0, 0.0, -29.5, 0.0];
  final bindings = ShaderBindings(
    <String, Map<String, Float32List>>{
      'FragInfo': <String, Float32List>{
        'shadow_params': Float32List.fromList(<double>[
          1.0 / (_tile * 2),
          0.001,
          0.0,
          1.0,
        ]),
        'frame_params': Float32List(4),
        'shadow_cascades': Float32List.fromList(<double>[
          40.0,
          200.0,
          2.0,
          1.0 / _tile,
        ]),
        'shadow_bias': Float32List.fromList(<double>[0.001, 0.001, 0.001, 0]),
        'shadow_matrix': Float32List.fromList(Matrix4.identity().storage),
        'shadow_matrix_far': Float32List.fromList(Matrix4.identity().storage),
        'camera_position': Float32List.fromList(eye),
        'ambient_ground': Float32List(4),
      },
      'FogInfo': <String, Float32List>{
        'eye': Float32List.fromList(eye),
        // Looking along +z: the fragment is thirty metres deep.
        'forward': Float32List.fromList(<double>[0.0, 0.0, 1.0, 0.0]),
        'projection': Float32List.fromList(<double>[
          if (orthographic) 1.0 else 0.0,
          0.0,
          0.0,
          0.0,
        ]),
      },
    },
    <String, BoundTexture>{'shadow_texture': _atlas()},
  );
  return shadowFactor(surface, bindings, 0, 1.0);
}

void main() {
  test('through an orthographic lens the depth picks the cascade', () {
    // Mutation: pick by distance from the eye whatever the lens, as before
    // `P7`. The fragment is fifty metres from the eye, past the split, and
    // reads the far tile's occluder.
    expect(_shadowThrough(orthographic: true), 1.0);
  });

  test('through a perspective lens the distance still does', () {
    // Mutation: pick by depth whatever the lens. Every perspective scene's
    // cascades are split by distance, and a fragment at the edge of the frame
    // would read a nearer tile than the one fitted for it.
    expect(_shadowThrough(orthographic: false), 0.0);
  });
}
