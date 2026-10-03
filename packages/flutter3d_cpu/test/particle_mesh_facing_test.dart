/// A mesh particle faces the view axis through an orthographic lens — `P7`.
///
///     dart test test/particle_mesh_facing_test.dart
///
/// `particle_mesh.frag` shades a shard by how squarely it faces the eye. It
/// measured that towards the eye's point, which through an orthographic lens
/// is only where the camera was put: a shard square to the view came out dim
/// because the camera stood off to one side of it. This pins the Dart
/// transcription to `ParticleTowardsEye` in `lib/particle_fog.glsl`.
library;

import 'dart:typed_data';

import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:test/test.dart';

/// What a white shard at the origin facing +z gives, the eye ten metres off
/// to its side and the view looking down −z.
double _brightness({required bool orthographic}) {
  final varyings = Float32List.fromList(<double>[
    1.0, 1.0, 1.0, 1.0, // colour
    0.0, 0.0, 0.0, // world
    0.0, 0.0, 1.0, // normal
  ]);
  final bindings = ShaderBindings(<String, Map<String, Float32List>>{
    'FogInfo': <String, Float32List>{
      'fog': Float32List(4),
      'eye': Float32List.fromList(<double>[10.0, 0.0, 0.0, 0.0]),
      'forward': Float32List.fromList(<double>[0.0, 0.0, -1.0, 0.0]),
      'projection': Float32List.fromList(<double>[
        if (orthographic) 1.0 else 0.0,
        0.0,
        0.0,
        0.0,
      ]),
    },
  }, const {});
  return const ParticleMeshShader()
      .run(varyings, bindings, FragmentContext())!
      .x;
}

void main() {
  test('square to an orthographic view, a shard is at full brightness', () {
    // Mutation: face the eye's point whatever the lens, as before `P7` —
    // edge-on to it, the shard drops to its floor of 0.35.
    expect(_brightness(orthographic: true), closeTo(1.0, 1e-6));
  });

  test('through a perspective lens it still faces the eye', () {
    expect(_brightness(orthographic: false), closeTo(0.35, 1e-6));
  });
}
