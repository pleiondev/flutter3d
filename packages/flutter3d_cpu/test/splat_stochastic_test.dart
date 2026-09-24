/// Hashed splats, averaged by the temporal resolve, come towards the sorted
/// picture — `N5`.
///
///     dart test test/splat_stochastic_test.dart
///
/// Two claims, held apart because they fail for different reasons. The hash:
/// each splat is kept at a pixel with its own opacity, independently of the
/// splats in front of it — checked frame by frame with the resolve off, by
/// counting which splat each pixel shows. And the golden's: sixteen frames of
/// an unsorted cloud through the resolve land near the sorted blend.
///
/// **Near, not on, and the gap is the resolve's rather than the hash's.**
/// `TemporalResolve` clips its history to the current frame's 3 × 3
/// neighbourhood, and where a splat's tail is faint its kept pixels are
/// sparse: a neighbourhood holding none of them clips the history to the
/// background. So the cores converge and the tails come out darker than the
/// sorted blend, by about as much after 48 frames as after 16. Measured with
/// the clip taken out of the CPU resolve, the same scene's error falls from
/// 0.053 to 0.027 at 16 frames. The bound here holds what the hash delivers
/// through the resolve as it stands.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 64;
const int _height = 48;

/// Round splats of [sigma] at the given places, colours and opacities.
SplatCloud _cloud(List<(Vector3, Vector4)> splats, {double sigma = 0.6}) {
  final n = splats.length;
  final centres = Float32List(n * 3);
  final colours = Float32List(n * 4);
  final scales = Float32List(n * 3);
  final rotations = Float32List(n * 4);
  for (var i = 0; i < n; i++) {
    final (where, colour) = splats[i];
    centres.setAll(i * 3, <double>[where.x, where.y, where.z]);
    colours.setAll(i * 4, <double>[colour.x, colour.y, colour.z, colour.w]);
    scales.setAll(i * 3, <double>[sigma, sigma, sigma]);
    rotations[i * 4 + 3] = 1.0;
  }
  return SplatCloud(
    centres: centres,
    colours: colours,
    scales: scales,
    rotations: rotations,
  );
}

/// Near red and middle green, both half opaque, over a blue one behind:
/// three layers, so a pixel's colour depends on every splat's verdict at
/// once. Listed far to near on purpose — the unsorted draw takes them in
/// this order, and the depth test is what has to put the red one on top.
SplatCloud _layers() => _cloud(<(Vector3, Vector4)>[
  (Vector3(0.3, 0.2, -1.0), Vector4(0.0, 0.0, 1.0, 0.9)),
  (Vector3(0.0, 0.0, 1.0), Vector4(1.0, 0.0, 0.0, 0.5)),
  (Vector3(-0.3, -0.1, 0.0), Vector4(0.0, 1.0, 0.0, 0.5)),
]);

/// [frames] frames of [cloud] drawn as [composite]; the last one as read
/// back, with [everyFrame] shown each of them on the way.
Float32List _render(
  SplatCloud cloud,
  SplatComposite composite, {
  required int frames,
  bool temporal = true,
  void Function(Float32List pixels)? everyFrame,
}) {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final camera = CameraNode()
    ..setPosition(0.0, 0.0, 5.0)
    ..lookAt(Vector3.zero());
  final scene = Scene()
    ..ambientIntensity = 0.0
    ..add(camera);
  final renderer = Renderer.create(device: device)
    ..addContributor(SplatContributor(cloud, composite: composite));
  final settings = RenderSettings(
    tonemap: false,
    bloom: const BloomSettings(enabled: false),
    antiAlias: AntiAliasSettings(temporal: TemporalSettings(enabled: temporal)),
  );
  final view = RenderView(
    camera: camera,
    clearColor: Vector4(0.0, 0.0, 0.0, 1.0),
  );
  late FrameResult result;
  for (var i = 0; i < frames; i++) {
    result = renderer.render(
      width: _width,
      height: _height,
      scene: scene,
      views: <RenderView>[view],
      settings: settings,
    );
    everyFrame?.call(device.readHdrPixels(result.frame));
  }
  expect(result.antiAliasing.temporal, temporal);
  return device.readHdrPixels(result.frame);
}

/// Mean absolute difference over the colour channels, after a 3 × 3 box blur
/// of both.
///
/// **Blurred, because a perceptual bound is.** What an exponential history
/// leaves of kept-or-dropped pixels is grain at the scale of one pixel, which
/// FLIP's contrast filter discounts at any viewing distance; the blur stands
/// in for that filter. The unblurred numbers are printed beside it.
double _meanError(Float32List a, Float32List b, {int radius = 1}) {
  var sum = 0.0;
  var count = 0;
  final taps = (2 * radius + 1) * (2 * radius + 1);
  for (var y = radius; y < _height - radius; y++) {
    for (var x = radius; x < _width - radius; x++) {
      for (var channel = 0; channel < 3; channel++) {
        var difference = 0.0;
        for (var dy = -radius; dy <= radius; dy++) {
          for (var dx = -radius; dx <= radius; dx++) {
            final at = ((y + dy) * _width + x + dx) * 4 + channel;
            difference += a[at].clamp(0.0, 1.0) - b[at].clamp(0.0, 1.0);
          }
        }
        sum += (difference / taps).abs();
        count++;
      }
    }
  }
  return sum / count;
}

/// Mean signed error over the pixels whose sorted value is at least [floor],
/// the splats' cores.
double _coreBias(Float32List hashed, Float32List sorted, double floor) {
  var sum = 0.0;
  var count = 0;
  for (var i = 0; i < sorted.length; i++) {
    if (i % 4 == 3 || sorted[i] < floor) continue;
    sum += hashed[i] - sorted[i];
    count++;
  }
  return sum / count;
}

void main() {
  test('splat-stochastic', () {
    final sorted = _render(_layers(), SplatComposite.sorted, frames: 16);
    final hashed = _render(_layers(), SplatComposite.automatic, frames: 16);
    final single = _render(_layers(), SplatComposite.automatic, frames: 1);

    final settled = _meanError(hashed, sorted);
    final speckle = _meanError(single, sorted);
    // ignore: avoid_print
    print(
      'splat-stochastic: mean error ${speckle.toStringAsFixed(4)} after one '
      'frame, ${settled.toStringAsFixed(4)} after 16 (3 x 3 blurred); '
      '${_meanError(single, sorted, radius: 0).toStringAsFixed(4)} and '
      '${_meanError(hashed, sorted, radius: 0).toStringAsFixed(4)} per pixel; '
      'core bias ${_coreBias(hashed, sorted, 0.7).toStringAsFixed(4)}',
    );
    // Mutation: pass nought as the resolve's history weight — the sixteenth
    // frame is as speckled as the first and both of these fail.
    expect(settled, lessThan(0.06));
    expect(settled, lessThan(speckle * 0.6));
    // The cores, where the resolve's clip has kept pixels to clip against,
    // come out as the sorted blend does.
    expect(_coreBias(hashed, sorted, 0.7).abs(), lessThan(0.03));
  });

  test('each splat is kept with its own opacity, independently of the one '
      'in front', () {
    // Red in front of green, both at 0.6, and no resolve: every pixel of every
    // frame shows red, green or the black background, whole. Counted over
    // the middle of the pair, red shows with its own chance `p`, and green
    // shows where red was dropped *and* green kept: `(1 - p) p`. With one
    // number for both splats green would be kept only where red was too, and
    // would never show at all.
    final cloud = _cloud(<(Vector3, Vector4)>[
      (Vector3(0.0, 0.0, -0.5), Vector4(0.0, 1.0, 0.0, 0.6)),
      (Vector3(0.0, 0.0, 0.5), Vector4(1.0, 0.0, 0.0, 0.6)),
    ], sigma: 1.5);
    var red = 0;
    var green = 0;
    var total = 0;
    _render(
      cloud,
      SplatComposite.hashed,
      frames: 32,
      temporal: false,
      everyFrame: (pixels) {
        for (var y = _height ~/ 2 - 3; y < _height ~/ 2 + 3; y++) {
          for (var x = _width ~/ 2 - 3; x < _width ~/ 2 + 3; x++) {
            final at = (y * _width + x) * 4;
            final r = pixels[at];
            final g = pixels[at + 1];
            if (r > 0.5 && g < 0.1) red++;
            if (g > 0.5 && r < 0.1) green++;
            total++;
          }
        }
      },
    );
    final p = red / total;
    final q = green / total;
    // ignore: avoid_print
    print('red shows ${p.toStringAsFixed(3)}, green ${q.toStringAsFixed(3)}');
    expect(p, closeTo(0.6, 0.06));
    // Mutation: give every splat the same offset into the noise in
    // `SplatHashedShader` — green falls to nothing.
    expect(q, closeTo((1.0 - p) * p, 0.05));
  });

  test('with the resolve off, the default is the sorted draw, unchanged', () {
    // `automatic` without a resolve is exactly `sorted`: the frame a scene
    // drew before this existed.
    final automatic = _render(
      _layers(),
      SplatComposite.automatic,
      frames: 1,
      temporal: false,
    );
    final sorted = _render(
      _layers(),
      SplatComposite.sorted,
      frames: 1,
      temporal: false,
    );
    expect(automatic, sorted);
  });
}
