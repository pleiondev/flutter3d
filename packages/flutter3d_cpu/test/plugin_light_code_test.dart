/// The engine's light loops skip a plugin's light type: a row coded 16 or
/// more is packed by its `LightTypeHook` and read by its own lighting model,
/// so `SampleLight` and `ContributorLight` give it nothing rather than
/// reading it as a panel or a point. The software stages are transcribed
/// from `surface.glsl` and `contributor_lights.glsl`, which skip it the same
/// way.
///
///     dart test test/plugin_light_code_test.dart
///
/// Mutation: drop the `position.w > 15.5` early-out in `sampleLight` and a
/// code-16 row is shaded as a rectangle; drop it from `contributorLight` and
/// the particle lit by it brightens.
library;

import 'dart:typed_data';

import 'package:flutter3d_cpu/src/cpu_shader.dart';
import 'package:flutter3d_cpu/src/cpu_shaders_lighting.dart';
import 'package:flutter3d_cpu/src/cpu_shaders_surface.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// One light in slot zero, a metre above the origin, coded [code].
ShaderBindings _light(double code, {String block = 'FragInfo'}) =>
    ShaderBindings(<String, Map<String, Float32List>>{
      block: <String, Float32List>{
        'light_position': Float32List.fromList(<double>[0, 1, 0, code]),
        'light_color': Float32List.fromList(<double>[1, 1, 1, 10]),
        'light_direction': Float32List.fromList(<double>[0.5, -0.5, 0, 5]),
        'light_cone': Float32List.fromList(<double>[0, 0, 0.5, 0]),
        'light_params': Float32List.fromList(<double>[1, 0, 0, 0]),
        'slots': Float32List.fromList(<double>[1, 0, 0, 0]),
      },
    }, const <String, BoundTexture>{});

Surface _surface() => Surface(
  Vector3.all(0.5),
  1,
  Vector3(0, 1, 0),
  Vector3.zero(),
  Vector3.zero(),
  0,
  0.5,
  Vector3(0, 1, 0),
  1,
  Vector4(1, 0, 0, 1),
);

void main() {
  test('the surface loop gives a plugin light type nothing', () {
    for (final code in <double>[0, 1, 3]) {
      expect(
        sampleLight(_light(code), 0, _surface()),
        isNotNull,
        reason: 'code $code is the engine\'s and reaches the surface',
      );
    }
    for (final code in <double>[16, 17, 40]) {
      expect(
        sampleLight(_light(code), 0, _surface()),
        isNull,
        reason: 'code $code is a plugin\'s',
      );
    }
  });

  test('the contributor loop gives a plugin light type nothing', () {
    const block = 'ContributorLightInfo';
    final point = contributorLight(_light(1, block: block), 0, Vector3.zero());
    expect(point.radiance.length, greaterThan(0));
    final plugin = contributorLight(
      _light(16, block: block),
      0,
      Vector3.zero(),
    );
    expect(plugin.radiance.length, 0);
  });
}
