/// The spatial upscale brings a half-size frame up to the asked-for size
/// closer to the full-size frame than stretching it does — `R5`, the
/// `easu-half` scene.
///
///     dart test test/easu_test.dart
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 96;
const int _height = 64;

({Float32List pixels, int width, int height}) _render(
  double scale, {
  bool upscale = false,
  double sharpen = 0.0,
}) {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final cube = DeviceMesh.upload(device, CuboidShape().build());
  final camera = CameraNode()
    ..setPosition(0.0, 1.2, 3.2)
    ..lookAt(Vector3.zero());
  final scene = Scene()
    ..add(
      MeshNode(cube, Material(baseColor: Vector4(0.9, 0.9, 0.9, 1.0)))
        ..setRotationYawPitchRoll(0.5, 0.2, 0.1),
    )
    ..add(LightNode(intensity: 3.0)..setRotationYawPitchRoll(0.4, -0.7, 0.0))
    ..add(camera);
  final result = Renderer.create(device: device).render(
    width: _width,
    height: _height,
    scene: scene,
    views: <RenderView>[
      RenderView(camera: camera, clearColor: Vector4(0.05, 0.05, 0.08, 1.0)),
    ],
    settings: RenderSettings(
      renderScale: scale,
      spatialUpscale: SpatialUpscaleSettings(
        enabled: upscale,
        sharpen: sharpen,
      ),
    ),
  );
  return (
    pixels: device.readHdrPixels(result.frame),
    width: result.frame.width,
    height: result.frame.height,
  );
}

/// [small] stretched to the full size with a bilinear filter, as a presenter
/// stretching the smaller texture would.
Float32List _stretch(({Float32List pixels, int width, int height}) small) {
  final out = Float32List(_width * _height * 4);
  for (var y = 0; y < _height; y++) {
    for (var x = 0; x < _width; x++) {
      final sx = (x + 0.5) * small.width / _width - 0.5;
      final sy = (y + 0.5) * small.height / _height - 0.5;
      final x0 = sx.floor().clamp(0, small.width - 1);
      final y0 = sy.floor().clamp(0, small.height - 1);
      final x1 = math.min(x0 + 1, small.width - 1);
      final y1 = math.min(y0 + 1, small.height - 1);
      final fx = (sx - sx.floorToDouble()).clamp(0.0, 1.0);
      final fy = (sy - sy.floorToDouble()).clamp(0.0, 1.0);
      for (var c = 0; c < 4; c++) {
        double at(int px, int py) =>
            small.pixels[(py * small.width + px) * 4 + c];
        final top = at(x0, y0) + (at(x1, y0) - at(x0, y0)) * fx;
        final bottom = at(x0, y1) + (at(x1, y1) - at(x0, y1)) * fx;
        out[(y * _width + x) * 4 + c] = top + (bottom - top) * fy;
      }
    }
  }
  return out;
}

double _error(Float32List a, Float32List b) {
  var sum = 0.0;
  for (var i = 0; i < a.length; i += 4) {
    for (var c = 0; c < 3; c++) {
      sum += (a[i + c] - b[i + c]).abs();
    }
  }
  return sum / (a.length / 4 * 3);
}

void main() {
  test('off, a half-scale frame comes back at half size, as before', () {
    final small = _render(0.5);
    expect(small.width, _width ~/ 2);
    expect(small.height, _height ~/ 2);
  });

  test('on, it comes back at the asked-for size, nearer the full frame', () {
    final full = _render(1.0);
    final upscaled = _render(0.5, upscale: true);
    expect(upscaled.width, _width);
    expect(upscaled.height, _height);

    final stretched = _stretch(_render(0.5));
    final easu = _error(upscaled.pixels, full.pixels);
    final bilinear = _error(stretched, full.pixels);
    // ignore: avoid_print
    print('mean error: easu $easu, bilinear $bilinear');
    // Mutation: return the nearest tap from `EasuShader`. A blockier picture
    // than a bilinear stretch, and further from the full frame.
    expect(easu, lessThan(bilinear));
    // The budget the `easu-half` golden holds it to.
    expect(easu, lessThan(0.03));
  });

  test('the sharpening after it runs and changes the picture', () {
    final plain = _render(0.5, upscale: true);
    final sharpened = _render(0.5, upscale: true, sharpen: 0.5);
    expect(sharpened.width, _width);
    expect(sharpened.pixels, isNot(plain.pixels));
  });

  test('a temporal resolve takes precedence: nothing upscales twice', () {
    expect(
      SpatialUpscaleSettings.runsFor(
        const RenderSettings(
          renderScale: 0.5,
          spatialUpscale: SpatialUpscaleSettings(enabled: true),
          antiAlias: AntiAliasSettings(
            temporal: TemporalSettings(enabled: true),
          ),
        ),
      ),
      isFalse,
    );
  });
}
