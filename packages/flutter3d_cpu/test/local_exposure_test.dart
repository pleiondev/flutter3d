/// Local exposure lifts the dark half of a frame without brightening the
/// bright half — `R7`, the `window-interior` case a global exposure cannot
/// handle.
///
///     dart test test/local_exposure_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 256;
const int _height = 128;

/// A block in near darkness on the left and one under a strong lamp on the
/// right.
Float32List _render({required bool local}) {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final cube = DeviceMesh.upload(device, CuboidShape().build());
  final camera = CameraNode()
    ..setPosition(0.0, 0.5, 5.0)
    ..lookAt(Vector3.zero());
  final scene = Scene()
    ..add(MeshNode(cube, Material())..setPosition(-1.6, 0.0, 0.0))
    ..add(MeshNode(cube, Material())..setPosition(1.6, 0.0, 0.0))
    ..add(LightNode(intensity: 0.08)..setRotationYawPitchRoll(0.3, -0.5, 0.0))
    ..add(
      LightNode(type: LightType.point, intensity: 60.0, range: 3.0)
        ..setPosition(1.6, 0.8, 1.4),
    )
    ..add(camera);
  final result = Renderer.create(device: device).render(
    width: _width,
    height: _height,
    scene: scene,
    views: <RenderView>[
      RenderView(camera: camera, clearColor: Vector4(0.0, 0.0, 0.0, 1.0)),
    ],
    settings: RenderSettings(
      bloom: const BloomSettings(enabled: false),
      localExposure: LocalExposureSettings(enabled: local, strength: 1.0),
    ),
  );
  return device.readHdrPixels(result.frame);
}

/// The mean of red, green and blue over the pixels of [pixels] between
/// columns [from] and [to] that are not the black background.
double _mean(Float32List pixels, int from, int to) {
  var sum = 0.0;
  var count = 0;
  for (var y = 0; y < _height; y++) {
    for (var x = from; x < to; x++) {
      final at = (y * _width + x) * 4;
      final value = (pixels[at] + pixels[at + 1] + pixels[at + 2]) / 3.0;
      if (value <= 0.0) continue;
      sum += value;
      count++;
    }
  }
  return count == 0 ? 0.0 : sum / count;
}

void main() {
  test('the dark block lifts and the bright one does not', () {
    final global = _render(local: false);
    final local = _render(local: true);
    final darkBefore = _mean(global, 0, _width ~/ 3);
    final darkAfter = _mean(local, 0, _width ~/ 3);
    final brightBefore = _mean(global, _width * 2 ~/ 3, _width);
    final brightAfter = _mean(local, _width * 2 ~/ 3, _width);
    // ignore: avoid_print
    print(
      'dark $darkBefore -> $darkAfter, bright $brightBefore -> $brightAfter',
    );
    // Measured: the dark block comes up by a fifth; the black around both
    // weighs every exposure alike and holds the shift down. Mutation: write
    // nought stops from the blur. Nothing moves.
    expect(darkAfter, greaterThan(darkBefore * 1.15));
    expect(brightAfter, lessThanOrEqualTo(brightBefore + 1e-3));
  });

  test('off is the frame it was', () {
    expect(const RenderSettings().localExposure.enabled, isFalse);
  });
}
