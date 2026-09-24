/// The LTC fit integrates the GGX lobe over a rectangle to within the fit's
/// own error of the integral taken the long way — `L7`.
///
///     dart test test/ltc_test.dart
library;

import 'dart:math' as math;

import 'package:flutter3d_core/src/engine/render/engine_tables.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_cpu/src/cpu_shaders_ltc.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// The engine's LTC table as the software rasteriser samples it.
BoundTexture _table() {
  final device = CpuDevice(
    width: 1,
    height: 1,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final pixels = device.readHdrPixels(EngineTables.of(device).ltc);
  final texture = CpuTexture(64, 128, TextureFormat.r32g32b32a32Float)
    ..pixels.setAll(0, pixels);
  return BoundTexture(texture, SamplerOptions.linearClamp);
}

/// ∫ D · Vis · (n · l) dω over the rectangle, by a grid of [steps]² points:
/// the GGX lobe with a Fresnel of one, which the fit's norm stands for.
double _reference(
  Vector3 n,
  Vector3 v,
  double roughness,
  Vector3 centre,
  Vector3 halfWidth,
  Vector3 halfHeight, {
  int steps = 256,
}) {
  final alpha = roughness * roughness;
  final a2 = alpha * alpha;
  final emits = halfWidth.cross(halfHeight)..normalize();
  final dA = 4.0 * halfWidth.length * halfHeight.length / (steps * steps);
  final nDotV = n.dot(v);
  var total = 0.0;
  for (var i = 0; i < steps; i++) {
    for (var j = 0; j < steps; j++) {
      final p =
          centre +
          halfWidth * ((i + 0.5) / steps * 2.0 - 1.0) +
          halfHeight * ((j + 0.5) / steps * 2.0 - 1.0);
      final r2 = p.length2;
      final l = p.normalized();
      final facing = -l.dot(emits);
      final nDotL = n.dot(l);
      if (facing <= 0.0 || nDotL <= 0.0) continue;
      final h = (l + v)..normalize();
      final nDotH = n.dot(h);
      final d = nDotH * nDotH * (a2 - 1.0) + 1.0;
      final dGgx = a2 / (math.pi * d * d);
      final lambdaV = nDotL * math.sqrt(nDotV * nDotV * (1.0 - a2) + a2);
      final lambdaL = nDotV * math.sqrt(nDotL * nDotL * (1.0 - a2) + a2);
      final vis = 0.5 / (lambdaV + lambdaL);
      total += dGgx * vis * nDotL * dA * facing / r2;
    }
  }
  return total;
}

void main() {
  final table = _table();
  final n = Vector3(0.0, 1.0, 0.0);
  final v = Vector3(0.0, 1.0, 1.0)..normalize();
  // A metre-wide panel facing down, where the mirror direction points and
  // a little aside of it.
  final halfWidth = Vector3(0.5, 0.0, 0.0);
  final halfHeight = Vector3(0.0, 0.0, 0.5);

  for (final centre in <Vector3>[
    Vector3(0.0, 1.5, -1.5),
    Vector3(0.8, 1.2, -0.4),
  ]) {
    for (final roughness in <double>[0.3, 0.6, 0.9]) {
      test('roughness $roughness, panel at $centre', () {
        final corners = <Vector3>[
          centre - halfWidth - halfHeight,
          centre + halfWidth - halfHeight,
          centre + halfWidth + halfHeight,
          centre - halfWidth + halfHeight,
        ];
        final fit = ltcRectangle(table, n, v, roughness, corners);
        final expected = _reference(
          n,
          v,
          roughness,
          centre,
          halfWidth,
          halfHeight,
        );
        // Within a fifth: the fit is a fit, and its worst here is the tail
        // of a narrow lobe, sixteen per cent under. Mutation: drop the
        // negation in `LtcRectangle`, and the integral is nought.
        expect(fit.x * fit.y, closeTo(expected, expected * 0.2));
      });
    }
  }
}
