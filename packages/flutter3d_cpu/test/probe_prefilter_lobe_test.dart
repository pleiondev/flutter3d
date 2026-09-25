/// `ProbePrefilterShader`'s lobe, read off one texel of a known cube.
///
///     dart test test/probe_prefilter_lobe_test.dart
///
/// The same measurement `flutter3d_core`'s `environment_prefilter_lobe_test`
/// makes of the host bake, made here of the device-side stage's transcription:
/// a cube that is white but for a black +Z, read straight along +Z, reports
/// the share of the lobe that reaches past the black face. The two copies were
/// wrong together once — each tap's sideways part shrunk far below the lobe's
/// — so each is held to the lobe on its own rather than to the other.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_cpu/src/cpu_shader_bindings.dart';
import 'package:flutter3d_cpu/src/cpu_shader_stage.dart';
import 'package:flutter3d_cpu/src/cpu_shaders_probe.dart';
import 'package:flutter3d_cpu/src/cpu_texture.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:test/test.dart';

const int _side = 16;

/// A cube of [_side], white but for a black +Z.
CpuTexture _blackFront() {
  CpuTexture face(double level) {
    final texture = CpuTexture(_side, _side, TextureFormat.r8g8b8a8UNormInt);
    for (var i = 0; i < _side * _side; i++) {
      texture.pixels
        ..[i * 4] = level
        ..[i * 4 + 1] = level
        ..[i * 4 + 2] = level
        ..[i * 4 + 3] = 1.0;
    }
    return texture;
  }

  return CpuTexture(
    _side,
    _side,
    TextureFormat.r8g8b8a8UNormInt,
  )..faces = <CpuTexture>[for (var i = 0; i < 6; i++) face(i == 4 ? 0.0 : 1.0)];
}

/// Red at the centre of the +Z face of a level of [roughness].
double _centre(double roughness) {
  final bindings = ShaderBindings(
    <String, Map<String, Float32List>>{
      'ProbeInfo': <String, Float32List>{
        'params': Float32List.fromList(<double>[4, roughness, 0, 64]),
      },
    },
    <String, BoundTexture>{
      'capture_texture': BoundTexture(
        _blackFront(),
        SamplerOptions.linearClamp,
      ),
    },
  );
  final colour = const ProbePrefilterShader().run(
    Float32List.fromList(<double>[0.5, 0.5]),
    bindings,
    FragmentContext(),
  )!;
  return colour.x;
}

/// One minus the view factor from the cube's centre to its +Z face: the
/// cosine-weighted share of the hemisphere about +Z the face does not cover.
final double _lambertOutsideFace =
    1.0 - 4.0 / (math.pi * math.sqrt2) * math.atan(1.0 / math.sqrt2);

void main() {
  test('the fully rough level is the cosine convolution', () {
    // Mutation: restore `radius * (1 - spread)` as the tap's sideways part —
    // this reads about 0.20 and fails.
    expect(_centre(1.0), closeTo(_lambertOutsideFace, 0.03));
  });

  test('a level of roughness one-half reaches past a face 45° away', () {
    // A GGX lobe of alpha one-quarter sends about a tenth of its weight past
    // 45°. Mutation: the old construction reads 0.0.
    expect(_centre(0.5), inInclusiveRange(0.06, 0.15));
  });
}
