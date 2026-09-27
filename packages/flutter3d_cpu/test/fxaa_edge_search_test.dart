/// FXAA smooths a long, shallow staircase towards the edge it stands for —
/// `gfx-04n`, the edge search of FXAA 3.11 Quality.
///
///     dart test test/fxaa_edge_search_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 96;
const int _height = 64;

/// A white card tipped a few degrees off level, on black, [factor] times the
/// size, with or without FXAA. Unlit, so the only thing to smooth is the
/// silhouette.
Float32List _render({required bool fxaa, int factor = 1}) {
  final width = _width * factor;
  final height = _height * factor;
  final device = CpuDevice(
    width: width,
    height: height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final card =
      MeshNode(
          DeviceMesh.upload(device, CuboidShape().build()),
          Material(
            lighting: LightingModel.unlit,
            baseColor: Vector4(1.0, 1.0, 1.0, 1.0),
          ),
        )
        ..setPosition(0.0, -0.5, -3.0)
        ..setRotationYawPitchRoll(0.0, 0.0, 0.07)
        ..setScale(6.0, 1.6, 0.05);
  final camera = CameraNode();
  final result = Renderer.create(device: device).render(
    width: width,
    height: height,
    scene: Scene()
      ..add(card)
      ..add(camera),
    views: <RenderView>[
      RenderView(camera: camera, clearColor: Vector4(0.0, 0.0, 0.0, 1.0)),
    ],
    settings: RenderSettings(
      bloom: const BloomSettings(enabled: false),
      look: const LookSettings(dither: 0.0),
      antiAlias: AntiAliasSettings(enabled: fxaa),
    ),
  );
  return device.readHdrPixels(result.frame);
}

/// [big] box-filtered down by [factor]: the coverage each pixel should have.
Float32List _downsample(Float32List big, int factor) {
  final out = Float32List(_width * _height);
  for (var y = 0; y < _height; y++) {
    for (var x = 0; x < _width; x++) {
      var sum = 0.0;
      for (var dy = 0; dy < factor; dy++) {
        for (var dx = 0; dx < factor; dx++) {
          sum +=
              big[((y * factor + dy) * _width * factor + x * factor + dx) * 4];
        }
      }
      out[y * _width + x] = sum / (factor * factor);
    }
  }
  return out;
}

/// The summed distance of [frame]'s red from [reference].
double _error(Float32List frame, Float32List reference) {
  var sum = 0.0;
  for (var i = 0; i < reference.length; i++) {
    sum += (frame[i * 4] - reference[i]).abs();
  }
  return sum;
}

void main() {
  test('a shallow edge comes out near its supersampled coverage', () {
    // Eight by eight samples a pixel is the edge as it should look. Without
    // the search a pixel moves at most three quarters of a texel on its own
    // neighbourhood, the same at every point of a step, and the staircase
    // stays a staircase. With it each pixel learns where along its step it
    // sits. Mutation: make `goodSpan` false in the mirror, which leaves the
    // sub-pixel term alone.
    final reference = _downsample(_render(fxaa: false, factor: 8), 8);
    final hard = _error(_render(fxaa: false), reference);
    final smoothed = _error(_render(fxaa: true), reference);
    // ignore: avoid_print
    print('error against coverage: hard $hard, FXAA $smoothed');
    expect(smoothed, lessThan(hard * 0.6));
  });
}
