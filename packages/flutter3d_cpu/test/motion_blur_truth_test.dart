/// One blurred frame of a turning wheel against what the camera would have
/// recorded — `R6`: the average, in linear light, of thirty-three sharp frames
/// spread across the same exposure.
///
///     dart test test/motion_blur_truth_test.dart
///
/// **A measure more than a pass mark.** The reconstruction is an estimate from
/// one frame, and where a spoke sweeps over the background it leaves the
/// spoke nearly opaque across its whole fan, where the exposure shows it at
/// the share of the time it was there: the gather gives a still background
/// sample no weight against a moving one. So the bound below is what the
/// filter reaches today, and it is here so that a change to the gather is
/// judged by this number rather than by eye: a refinement tried after the
/// 0.8 review drew fans half as wide and scored worse, and was taken back.
library;

import 'dart:math' as math;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart' show Vector3, Vector4;

const int _width = 240;
const int _height = 160;

/// Radians the wheel turns between two frames.
const double _step = 0.35;

typedef _Staged = ({
  CpuDevice device,
  Renderer renderer,
  Scene scene,
  SceneNode wheel,
  CameraNode camera,
});

/// `motion-blur-spin`'s wheel: three spokes, each its own colour.
_Staged _staged() {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final spoke = DeviceMesh.upload(
    device,
    CuboidShape(size: Vector3(3.0, 0.3, 0.3)).build(),
  );
  final wheel = SceneNode(name: 'wheel')..setPosition(0.0, 0.0, -5.0);
  for (var i = 0; i < 3; i++) {
    wheel.add(
      MeshNode(
        spoke,
        Material(
          baseColor: <Vector4>[
            Vector4(0.9, 0.8, 0.2, 1.0),
            Vector4(0.2, 0.7, 0.9, 1.0),
            Vector4(0.9, 0.3, 0.3, 1.0),
          ][i],
        ),
      )..setRotationYawPitchRoll(0.0, 0.0, i * math.pi / 3),
    );
  }
  final camera = CameraNode();
  final scene = Scene()
    ..add(wheel)
    ..add(
      LightNode(intensity: 3.0)
        ..setLocalForward(Vector3(-2.0, -3.0, -4.0).normalized()),
    )
    ..add(camera);
  return (
    device: device,
    renderer: Renderer.create(device: device),
    scene: scene,
    wheel: wheel,
    camera: camera,
  );
}

/// Bloom off, so nothing but the blur spreads a spoke; the surface buffer
/// on, which the blur reads.
const RenderSettings _sharp = RenderSettings(
  bloom: BloomSettings(enabled: false),
  surfaceBuffer: true,
);

Future<List<int>> _draw(_Staged it, RenderSettings settings) async {
  final frame = it.renderer.render(
    width: _width,
    height: _height,
    scene: it.scene,
    views: <RenderView>[
      RenderView(camera: it.camera, clearColor: Vector4(0.0, 0.0, 0.0, 1.0)),
    ],
    settings: settings,
  );
  final bytes = await it.device.readPixels(frame.frame);
  return <int>[
    for (var i = 0; i < _width * _height * 4; i++) bytes!.getUint8(i),
  ];
}

double _linear(int c) {
  final v = c / 255.0;
  return v <= 0.04045
      ? v / 12.92
      : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
}

double _encoded(double l) =>
    255.0 *
    (l <= 0.0031308
        ? l * 12.92
        : 1.055 * math.pow(l, 1 / 2.4).toDouble() - 0.055);

/// The mean colour error of [image] against [truth], in levels, over the
/// pixels where the exposure differs from the still frame [still].
double _errorWhereMoved(List<int> image, List<double> truth, List<int> still) {
  var sum = 0.0;
  var count = 0;
  for (var p = 0; p < _width * _height; p++) {
    final moved = <int>[
      0,
      1,
      2,
    ].any((c) => (truth[p * 4 + c] - still[p * 4 + c]).abs() > 2.0);
    if (!moved) continue;
    count++;
    for (var c = 0; c < 3; c++) {
      sum += (image[p * 4 + c] - truth[p * 4 + c]).abs() / 3.0;
    }
  }
  return sum / math.max(count, 1);
}

void main() {
  test(
    'one blurred frame comes nearer the exposure than a sharp one',
    () async {
      const angle = 3 * _step;

      // The blurred frame, the one before it giving the motion.
      final moving = _staged();
      final blurred = _sharp.copyWith(
        motionBlur: const MotionBlurSettings(
          enabled: true,
          shutterFraction: 1.0,
        ),
      );
      moving.wheel.setRotationYawPitchRoll(0.0, 0.0, angle - _step);
      await _draw(moving, blurred);
      moving.wheel.setRotationYawPitchRoll(0.0, 0.0, angle);
      final blur = await _draw(moving, blurred);

      // A shutter open the whole frame, centred on the frame's own moment:
      // half a step either side, which is the span the blur reconstructs.
      const subframes = 33;
      final sum = List<double>.filled(_width * _height * 4, 0.0);
      final still = _staged();
      late List<int> sharp;
      for (var k = 0; k < subframes; k++) {
        still.wheel.setRotationYawPitchRoll(
          0.0,
          0.0,
          angle - _step / 2 + _step * k / (subframes - 1),
        );
        final pixels = await _draw(still, _sharp);
        if (k == subframes ~/ 2) sharp = pixels;
        for (var i = 0; i < pixels.length; i++) {
          sum[i] += _linear(pixels[i]);
        }
      }
      final truth = <double>[for (final s in sum) _encoded(s / subframes)];

      final sharpError = _errorWhereMoved(sharp, truth, sharp);
      final blurError = _errorWhereMoved(blur, truth, sharp);
      // ignore: avoid_print — the two numbers are what this file is for.
      print(
        'error where the wheel moved: sharp ${sharpError.toStringAsFixed(2)}, '
        'blurred ${blurError.toStringAsFixed(2)} levels',
      );
      // Measured on 2026-09-26: 68.60 sharp, 37.52 blurred. The bound sits a
      // little above the blurred number: the refinement taken back scored 39.72
    // and fails it, so a change that loses ground fails too.
      expect(blurError, lessThan(0.56 * sharpError));
    },
  );
}
