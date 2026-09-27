/// One blurred frame against what the camera would have recorded — `R6`:
/// the light of thirty-three sharp frames spread across the same exposure,
/// added up before the tone curve, the way a sensor adds it.
///
///     dart test test/motion_blur_truth_test.dart
///
/// **A measure more than a pass mark.** The reconstruction is an estimate from
/// one frame, so each bound below is what the filter reaches today, a little
/// above it, and it is here so that a change to the gather is judged by these
/// numbers rather than by eye. Two cases, so that a change is not tuned to
/// one: a turning wheel over black, where each spoke sweeps a fan, and a box
/// sliding across a checkerboard, where what shows behind it matters.
///
/// **Before the tone curve.** Each sharp frame is drawn untonemapped at a
/// quarter of the exposure, so nothing clips, and the average is scaled back
/// and put through the same Khronos PBR Neutral curve the composite applies.
/// Averaging the finished frames instead would be averaging after the curve,
/// which dims every streak brighter than the curve's knee; the first check
/// in [_measure] holds the path to the composite's own frame.
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

/// Metres the box slides between two frames.
const double _slide = 0.5;

/// How far down the exposure of the sharp frames is taken so that no channel
/// reaches one.
const double _dim = 0.25;

typedef _Staged = ({
  CpuDevice device,
  Renderer renderer,
  Scene scene,
  SceneNode mover,
  CameraNode camera,
});

/// A stage for what [fill] adds to the scene, moving what it returns.
_Staged _stage(SceneNode Function(CpuDevice device, Scene scene) fill) {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final scene = Scene();
  final mover = fill(device, scene);
  final camera = CameraNode();
  scene
    ..add(
      // No shadow: a shadow has no motion of its own to blur it by, so it
      // would be an error the gather cannot answer for.
      LightNode(intensity: 3.0, castsShadow: false)
        ..setLocalForward(Vector3(-2.0, -3.0, -4.0).normalized()),
    )
    ..add(camera);
  return (
    device: device,
    renderer: Renderer.create(device: device),
    scene: scene,
    mover: mover,
    camera: camera,
  );
}

/// `motion-blur-spin`'s wheel: three spokes, each its own colour.
_Staged _wheel() => _stage((device, scene) {
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
  scene.add(wheel);
  return wheel;
});

/// A red box three metres in front of a wall of cream and blue tiles.
_Staged _box() => _stage((device, scene) {
  final box = MeshNode(
    DeviceMesh.upload(device, CuboidShape(size: Vector3.all(0.8)).build()),
    Material(baseColor: Vector4(0.9, 0.3, 0.2, 1.0)),
  );
  scene.add(box);
  final tile = DeviceMesh.upload(
    device,
    CuboidShape(size: Vector3(0.5, 0.5, 0.1)).build(),
  );
  for (var y = -4; y < 4; y++) {
    for (var x = -6; x < 6; x++) {
      scene.add(
        MeshNode(
          tile,
          Material(
            baseColor: (x + y).isOdd
                ? Vector4(0.8, 0.8, 0.75, 1.0)
                : Vector4(0.15, 0.3, 0.5, 1.0),
          ),
        )..setPosition(x * 0.5 + 0.25, y * 0.5 + 0.25, -8.0),
      );
    }
  }
  return box;
});

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

/// Light summed over [count] untonemapped frames, as the composite would
/// finish it: back to the frame's exposure, through the curve, encoded.
List<double> _finished(List<double> sum, int count) {
  final out = List<double>.filled(sum.length, 255.0);
  for (var p = 0; p < _width * _height; p++) {
    final mapped = tonemapNeutral(
      Vector3(sum[p * 4], sum[p * 4 + 1], sum[p * 4 + 2]) / (count * _dim),
    );
    out[p * 4] = _encoded(mapped.x);
    out[p * 4 + 1] = _encoded(mapped.y);
    out[p * 4 + 2] = _encoded(mapped.z);
  }
  return out;
}

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

/// The error of a sharp and of a blurred frame where [make]'s mover moved,
/// posed by [pose] at [at] and moving [step] a frame.
Future<({double sharp, double blurred})> _measure(
  _Staged Function() make,
  void Function(SceneNode mover, double at) pose,
  double at,
  double step,
) async {
  // The blurred frame, the one before it giving the motion.
  final moving = make();
  final blurred = _sharp.copyWith(
    motionBlur: const MotionBlurSettings(enabled: true, shutterFraction: 1.0),
  );
  pose(moving.mover, at - step);
  await _draw(moving, blurred);
  pose(moving.mover, at);
  final blur = await _draw(moving, blurred);

  // A shutter open the whole frame, centred on the frame's own moment: half
  // a step either side, which is the span the blur reconstructs.
  const subframes = 33;
  final raw = _sharp.copyWith(tonemap: false, exposure: _sharp.exposure * _dim);
  final sum = List<double>.filled(_width * _height * 4, 0.0);
  final still = make();
  late List<int> sharp;
  late List<int> middle;
  for (var k = 0; k < subframes; k++) {
    pose(still.mover, at - step / 2 + step * k / (subframes - 1));
    final pixels = await _draw(still, raw);
    if (k == subframes ~/ 2) {
      sharp = await _draw(still, _sharp);
      middle = pixels;
    }
    for (var i = 0; i < pixels.length; i++) {
      sum[i] += _linear(pixels[i]);
    }
  }

  // The path to the truth, held to the composite: one frame taken down it
  // lands where the composite put that frame, within the dither.
  final one = _finished(<double>[for (final c in middle) _linear(c)], 1);
  var drift = 0.0;
  for (var i = 0; i < one.length; i++) {
    drift += (one[i] - sharp[i]).abs();
  }
  expect(drift / one.length, lessThan(0.5));

  final truth = _finished(sum, subframes);
  return (
    sharp: _errorWhereMoved(sharp, truth, sharp),
    blurred: _errorWhereMoved(blur, truth, sharp),
  );
}

void main() {
  test(
    'a turning wheel comes nearer the exposure than a sharp frame',
    () async {
      final error = await _measure(
        _wheel,
        (wheel, angle) => wheel.setRotationYawPitchRoll(0.0, 0.0, angle),
        3 * _step,
        _step,
      );
      // ignore: avoid_print — the two numbers are what this file is for.
      print(
        'error where the wheel moved: sharp ${error.sharp.toStringAsFixed(2)}, '
        'blurred ${error.blurred.toStringAsFixed(2)} levels',
      );
      // Measured on 2026-09-26: 74.20 sharp, 10.49 blurred. The gather that
      // normalised its weights, before the shares of the exposure, made 19.91
      // here: the spoke nearly opaque across its fan.
      expect(error.blurred, lessThan(0.15 * error.sharp));
    },
  );

  test('a sliding box comes nearer the exposure than a sharp frame', () async {
    final error = await _measure(
      _box,
      (box, x) => box.setPosition(x, 0.0, -5.0),
      0.0,
      _slide,
    );
    // ignore: avoid_print — the two numbers are what this file is for.
    print(
      'error where the box moved: sharp ${error.sharp.toStringAsFixed(2)}, '
      'blurred ${error.blurred.toStringAsFixed(2)} levels',
    );
    // Measured on 2026-09-26: 22.91 sharp, 5.45 blurred, and 9.41 for the
    // gather that normalised its weights. Most of what is left is inside the
    // box's own blur, where the tiles it hid show through and the gather can
    // only guess them from the nearest tile it saw.
    expect(error.blurred, lessThan(0.25 * error.sharp));
  });
}
