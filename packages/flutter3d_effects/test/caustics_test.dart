/// The sea floor's caustics evaluated as the software backend evaluates
/// them, from the material's own source — its light block, which the
/// engine multiplies by the sun's radiance, n·l and shadow — against what
/// refraction must do: light that only bends neither appears nor vanishes, so over the floor it
/// averages to what fell on the surface, and the deeper the floor the more
/// it gathers into lines.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter3d_core/formats.dart';
import 'package:test/test.dart';

void main() {
  final program = specialiseMaterial(
    parseMaterial(File('assets_src/seabed.f3dmat').readAsStringSync()),
    const MaterialVariant('default'),
  );

  /// The floor's brightness at (x, z), [depth] under the surface, under a
  /// sun overhead of light one, through water that takes nothing out.
  double lit(double x, double z, double depth) => evaluateMaterialLight(
    program,
    MaterialSurfaceValues(
      uniforms: <String, List<double>>{
        'time': <double>[1.0],
        'level': <double>[0.0],
        'eye': <double>[0.0, 10.0, 0.0],
        'toSun': <double>[0.0, 1.0, 0.0],
        'sunColor': <double>[1.0, 1.0, 1.0],
        'absorb': <double>[0.0, 0.0, 0.0],
        'scatter': <double>[0.0, 0.0, 0.0],
      },
      inputs: <String, List<double>>{
        'albedo': const <double>[1, 1, 1],
        'alpha': const <double>[1],
        'normal': const <double>[0, 1, 0],
        'view': const <double>[0, 1, 0],
        'nDotV': const <double>[1],
        'metallic': const <double>[0],
        'roughness': const <double>[1],
        'occlusion': const <double>[1],
        'emissive': const <double>[0, 0, 0],
        'ambient': const <double>[0, 0, 0],
        'uv': const <double>[0, 0],
        'world': <double>[x, -depth, z],
        // The sun straight overhead, as the light block is asked of it.
        'lightDir': const <double>[0, 1, 0],
        'halfDir': const <double>[0, 1, 0],
        'nDotL': const <double>[1],
        'nDotH': const <double>[1],
        'vDotH': const <double>[1],
      },
      sample: (slot, u, v) => const <double>[1, 1, 1, 1],
    ),
  )[1];

  /// The mean and spread of the floor's brightness over eight metres.
  ({double mean, double spread}) over(double depth) {
    final values = <double>[
      for (var i = 0; i < 100; i++)
        for (var j = 0; j < 100; j++) lit(i * 0.08, j * 0.08, depth),
    ];
    final mean = values.reduce((a, b) => a + b) / values.length;
    final spread = math.sqrt(
      values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
          values.length,
    );
    return (mean: mean, spread: spread);
  }

  test('at the surface the floor is lit evenly', () {
    final at = over(0.0);
    expect(at.mean, closeTo(1.0, 1e-6));
    expect(at.spread, closeTo(0.0, 1e-6));
  });

  test('below it the light gathers into lines and none is lost', () {
    final shallow = over(0.5), deeper = over(2.0);
    // Mutation: drop the Hessian's terms — the floor is evenly lit at any
    // depth, no lines.
    expect(deeper.spread, greaterThan(shallow.spread));
    expect(deeper.spread, greaterThan(0.2));
    // What only bends averages to what fell: within what the sun's width
    // clips off the brightest lines.
    expect(shallow.mean, closeTo(1.0, 0.05));
    expect(deeper.mean, closeTo(1.0, 0.08));
  });
}
