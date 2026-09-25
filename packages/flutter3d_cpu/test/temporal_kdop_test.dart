/// The temporal resolve's k-DOP clip keeps a history of the wrong hue out
/// where the box lets it in — `N4`, golden `taa-railing`.
///
///     dart test test/temporal_kdop_test.dart
///
/// A railing of blue bars in front of a wall that turns from red to green,
/// with nothing moving: the depth test keeps the history, since the wall is
/// the same wall, and only the clip stands between the red it remembers and
/// the green it is now. Around a bar the nine colours are green and blue;
/// the box around them in YCoCg has a corner that is grey, and the red
/// history lands there. The k-DOP hugs the two colours and the red goes.
library;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart' show Vector4;

const int _width = 48;
const int _height = 32;

RenderSettings _settings(TemporalClip clip) => RenderSettings(
  tonemap: false,
  bloom: const BloomSettings(enabled: false),
  antiAlias: AntiAliasSettings(
    temporal: TemporalSettings(enabled: true, sharpen: 0.0, clip: clip),
  ),
);

typedef _Railing = ({
  CpuDevice device,
  Renderer renderer,
  Scene scene,
  RenderView view,
  Material wall,
});

_Railing _railing() {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final camera = CameraNode();
  final wall = Material(
    lighting: LightingModel.unlit,
    baseColor: Vector4(1.0, 0.0, 0.0, 1.0),
  );
  final bar = Material(
    lighting: LightingModel.unlit,
    baseColor: Vector4(0.0, 0.0, 1.0, 1.0),
  );
  final cube = DeviceMesh.upload(device, CuboidShape().build());
  // Near enough behind the bars (under a tenth of the depth) that the
  // resolve takes the wall and the bars for one surface and keeps the
  // history across them, as it does for a railing against its own wall.
  final scene = Scene()
    ..add(
      MeshNode(cube, wall)
        ..setPosition(0.0, 0.0, -4.3)
        ..setScale(20.0, 20.0, 0.1),
    )
    ..add(camera);
  for (var i = -4; i <= 4; i++) {
    scene.add(
      MeshNode(cube, bar)
        ..setPosition(i * 0.45, 0.0, -4.0)
        ..setRotationYawPitchRoll(0.0, 0.0, 0.3)
        ..setScale(0.08, 6.0, 0.08),
    );
  }
  return (
    device: device,
    renderer: Renderer.create(device: device),
    scene: scene,
    view: RenderView(camera: camera, clearColor: Vector4(0.0, 0.0, 0.0, 1.0)),
    wall: wall,
  );
}

List<double> _draw(_Railing it, TemporalClip clip) {
  final result = it.renderer.render(
    width: _width,
    height: _height,
    scene: it.scene,
    views: <RenderView>[it.view],
    settings: _settings(clip),
  );
  return it.device.readHdrPixels(result.frame);
}

/// The mean over the frame of how far each pixel's colour is from [b]'s.
double _meanDifference(List<double> a, List<double> b) {
  var sum = 0.0;
  for (var i = 0; i < a.length; i++) {
    if (i % 4 == 3) continue;
    sum += (a[i].clamp(0.0, 1.0) - b[i].clamp(0.0, 1.0)).abs();
  }
  return sum / (a.length * 3 ~/ 4);
}

/// How much red is left in the frame: the wall's old colour, which neither
/// the green wall nor the blue bars have.
double _red(List<double> pixels) {
  var sum = 0.0;
  for (var i = 0; i < pixels.length; i += 4) {
    sum += pixels[i].clamp(0.0, 1.0);
  }
  return sum / (pixels.length ~/ 4);
}

/// Settles the railing on the red wall, turns the wall green, and returns
/// the first frame after and the frame once it has settled again.
({List<double> after, List<double> settled}) _turn(TemporalClip clip) {
  final it = _railing();
  for (var i = 0; i < 32; i++) {
    _draw(it, clip);
  }
  it.wall.baseColor.setValues(0.0, 1.0, 0.0, 1.0);
  final after = _draw(it, clip);
  for (var i = 0; i < 48; i++) {
    _draw(it, clip);
  }
  return (after: after, settled: _draw(it, clip));
}

void main() {
  group('taa-railing', () {
    final turns = {for (final clip in TemporalClip.values) clip: _turn(clip)};
    final box = turns[TemporalClip.aabb]!;

    test('the box lets the old wall through beside the bars', () {
      // The premise: without it the k-DOP has nothing to improve on. The
      // settled frame is green and blue and nearly free of red.
      expect(_red(box.settled), lessThan(0.01));
      expect(_red(box.after), greaterThan(0.02));
    });

    for (final clip in TemporalClip.values.skip(1)) {
      test('${clip.name} leaves less of the old wall than the box', () {
        final turn = turns[clip]!;
        // Mutation: pass nought for `clip.x` in `_encodeTemporalResolve`.
        // The resolve clips to its box and the red is the box's.
        expect(_red(turn.after), lessThan(_red(box.after) * 0.5));
      });

      test('${clip.name} settles to the picture the box settles to', () {
        // A k-DOP must not cost the still frame its smoothing: once the
        // history agrees with the scene, what it keeps is what the box
        // keeps, give or take the jitter's own few grey levels.
        expect(
          _meanDifference(turns[clip]!.settled, box.settled),
          lessThan(0.02),
        );
      });
    }
  });

  test('every axis is a unit vector and every set starts with the box', () {
    for (final clip in TemporalClip.values.skip(1)) {
      expect(clip.axes, hasLength(clip.axisCount));
      expect(clip.axes.take(3), const [
        (1.0, 0.0, 0.0),
        (0.0, 1.0, 0.0),
        (0.0, 0.0, 1.0),
      ]);
      for (final (x, y, z) in clip.axes) {
        expect(x * x + y * y + z * z, closeTo(1.0, 1e-4));
      }
    }
  });
}
