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
    // Exposure one, so the fusion judges the scene's own light: the weights
    // follow the frame's exposure, and at the default 1.6 the dark block is
    // already less underexposed than this case is about.
    settings: RenderSettings(
      exposure: 1.0,
      bloom: const BloomSettings(enabled: false),
      localExposure: LocalExposureSettings(enabled: local, strength: 1.0),
    ),
  );
  return device.readHdrPixels(result.frame);
}

/// The centre of a frame filled by an unlit card of 0.02 linear light, at
/// [exposure], as the finished (encoded) red.
double _card({required double exposure, required bool local}) {
  const size = 64;
  final device = CpuDevice(
    width: size,
    height: size,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  // 0.02 linear, authored in sRGB as the unlit stage decodes it.
  const authored = 0.1522;
  final card =
      MeshNode(
          DeviceMesh.upload(device, CuboidShape().build()),
          Material(
            lighting: LightingModel.unlit,
            baseColor: Vector4(authored, authored, authored, 1.0),
          ),
        )
        ..setPosition(0.0, 0.0, -1.0)
        ..setScale(4.0, 4.0, 0.1);
  final camera = CameraNode();
  final result = Renderer.create(device: device).render(
    width: size,
    height: size,
    scene: Scene()
      ..add(card)
      ..add(camera),
    views: <RenderView>[RenderView(camera: camera)],
    settings: RenderSettings(
      exposure: exposure,
      bloom: const BloomSettings(enabled: false),
      look: const LookSettings(dither: 0.0),
      localExposure: LocalExposureSettings(enabled: local, strength: 1.0),
    ),
  );
  final centre = (size ~/ 2 * size + size ~/ 2) * 4;
  return device.readHdrPixels(result.frame)[centre];
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

  test('a frame the camera already exposed up is not lifted again', () {
    // A dim card, 0.02 of linear light, filling the frame. At exposure one
    // it is well under mid grey and the fusion lifts it. With the camera's
    // exposure three stops up (auto exposure's ceiling in a dark room) it
    // lands near mid grey, and the fusion has to see that: judged at
    // exposure one it lifted the already-lifted room by as much again.
    // Mutation: drop `* camera.x` from the mirror's luminance.
    double lift(double exposure) {
      final off = _card(exposure: exposure, local: false);
      final on = _card(exposure: exposure, local: true);
      // ignore: avoid_print
      print('exposure $exposure: $off -> $on');
      return on / off;
    }

    final atOne = lift(1.0);
    final atEight = lift(8.0);
    // Measured: three times brighter at exposure one; at eight, 1.16 with
    // the frame's exposure in the weights and 1.49 without it. What is left
    // is the Reinhard proxy's lean towards lifting.
    expect(atOne, greaterThan(2.0), reason: 'an underexposed card lifts');
    expect(atEight, lessThan(1.25), reason: 'an exposed card barely moves');
  });

  test('off is the frame it was', () {
    expect(const RenderSettings().localExposure.enabled, isFalse);
  });
}
