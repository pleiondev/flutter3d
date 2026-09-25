/// The sun's penumbra is as wide as its angular radius says.
///
///     dart test test/sun_penumbra_width_test.dart
///
/// `ShadowSettings.directionalLightRadius` is the light's angular radius α,
/// and the penumbra a caster leaves across a gap is `2·tan(α)·gap` wide. The
/// `S3` filter blurs with a disc; a disc of radius R swept over an edge ramps
/// over 2R, so R has to be `tan(α)·gap`. This pins the CPU mirror of
/// `shadow.glsl` to that: a fragment just past the half-width is fully lit,
/// one well inside it is not.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _tile = 256;
const double _alpha = 0.1;
const double _blocker = 0.2;
const double _receiver = 0.8;

/// One tile: an occluder at depth [_blocker] over the left half, nothing over
/// the right.
BoundTexture _atlas() {
  final texture = CpuTexture(_tile, _tile, TextureFormat.r16g16b16a16Float);
  for (var y = 0; y < _tile; y++) {
    for (var x = 0; x < _tile; x++) {
      texture.pixels[(y * _tile + x) * 4] = x < _tile ~/ 2 ? _blocker : 1.0;
    }
  }
  return BoundTexture(texture, SamplerOptions.nearestClamp);
}

/// The shadow at world `x` (metres right of the occluder's edge), on a
/// receiver at depth [_receiver]. The identity light matrix makes the map two
/// metres across and one metre per unit of stored depth.
double _shadowAt(double x) {
  final surface = Surface(
    Vector3.all(1.0),
    1.0,
    // No normal, so no normal offset: the point projects where it stands.
    Vector3.zero(),
    Vector3(x, 0.0, _receiver),
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
        'shadow_bias': Float32List.fromList(<double>[0.001, 0.001, 0.001, 0]),
        'shadow_matrix': Float32List.fromList(Matrix4.identity().storage),
        'camera_position': Float32List(4),
        // `S3`: the sun's angular radius rides in `ambient_ground.w`.
        'ambient_ground': Float32List.fromList(<double>[0, 0, 0, _alpha]),
      },
    },
    <String, BoundTexture>{'shadow_texture': _atlas()},
  );
  return shadowFactor(surface, bindings, 0, 1.0);
}

void main() {
  // Half the penumbra, in metres: the disc's radius.
  final halfWidth = math.tan(_alpha) * (_receiver - _blocker);

  test('a fragment past the half-width is fully lit', () {
    // Mutation: `spread = 2·tan(α)`. The disc reaches 2·halfWidth, three of
    // its sixteen taps land on the occluder (0.81), and the penumbra is twice
    // as wide as the light's radius allows.
    expect(_shadowAt(halfWidth * 1.2), 1.0);
  });

  test('a fragment inside the half-width is partly shadowed', () {
    final lit = _shadowAt(halfWidth * 0.3);
    expect(lit, greaterThan(0.0));
    expect(lit, lessThan(1.0));
  });

  test('a fragment well under the occluder is dark', () {
    // The same mutation lets light in from the lit side: 0.19.
    expect(_shadowAt(-halfWidth * 1.2), 0.0);
  });
}
