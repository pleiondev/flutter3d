/// Frames blended into a history smooth an edge that no single frame could —
/// `R2`.
///
///     dart test test/temporal_resolve_test.dart
///
/// On the software rasteriser, which draws exactly what it is told: with no
/// multisampling at all, every edge of a single frame is a staircase of whole
/// pixels, so an edge pixel between the two flat levels can only have come
/// from the resolve averaging jittered frames.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart' show Vector4;

const int _width = 48;
const int _height = 32;

RenderSettings _settings({bool temporal = true, double renderScale = 1.0}) =>
    RenderSettings(
      renderScale: renderScale,
      tonemap: false,
      // The glow would put grey around every edge whatever the resolve did.
      bloom: const BloomSettings(enabled: false),
      antiAlias: AntiAliasSettings(
        temporal: TemporalSettings(enabled: temporal),
      ),
    );

typedef _Staged = ({
  CpuDevice device,
  Renderer renderer,
  Scene scene,
  RenderView view,
});

_Staged _staged() {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final camera = CameraNode();
  // A white box on the dark clear, turned so its edges are diagonal: a
  // straight edge on a pixel boundary has nothing to smooth.
  final box =
      MeshNode(
          DeviceMesh.upload(device, CuboidShape().build()),
          Material(
            lighting: LightingModel.unlit,
            baseColor: Vector4(1.0, 1.0, 1.0, 1.0),
          ),
        )
        ..setPosition(0.0, 0.0, -4.0)
        ..setRotationYawPitchRoll(0.0, 0.0, 0.4);
  final scene = Scene()
    ..add(box)
    ..add(camera);
  return (
    device: device,
    renderer: Renderer.create(device: device),
    scene: scene,
    view: RenderView(camera: camera, clearColor: Vector4(0.0, 0.0, 0.0, 1.0)),
  );
}

({Uint8List pixels, FrameResult result}) _draw(
  _Staged it,
  RenderSettings settings,
) {
  final result = it.renderer.render(
    width: _width,
    height: _height,
    scene: it.scene,
    views: <RenderView>[it.view],
    settings: settings,
  );
  final hdr = it.device.readHdrPixels(result.frame);
  final pixels = Uint8List(hdr.length);
  for (var i = 0; i < hdr.length; i++) {
    pixels[i] = (hdr[i].clamp(0.0, 1.0) * 255).round();
  }
  return (pixels: pixels, result: result);
}

/// How many pixels are neither the box nor the background.
int _between(Uint8List pixels) {
  var count = 0;
  for (var i = 0; i < pixels.length; i += 4) {
    final g = pixels[i + 1];
    if (g > 12 && g < 243) count++;
  }
  return count;
}

void main() {
  test('a still frame, resolved, has edges no single frame has', () {
    final plain = _staged();
    final hard = _between(_draw(plain, _settings(temporal: false)).pixels);

    final it = _staged();
    late ({Uint8List pixels, FrameResult result}) last;
    for (var i = 0; i < 32; i++) {
      last = _draw(it, _settings());
    }
    expect(last.result.antiAliasing.temporal, isTrue);
    expect(last.result.antiAliasing.msaaSamples, 1);
    // Mutation: pass nought as the history weight. Each frame is shown as
    // drawn, jittered and hard-edged, and the count falls back to the plain
    // frame's.
    expect(_between(last.pixels), greaterThan(hard + 20));
  });

  test('a still frame settles', () {
    final it = _staged();
    for (var i = 0; i < 48; i++) {
      _draw(it, _settings());
    }
    final a = _draw(it, _settings()).pixels;
    final b = _draw(it, _settings()).pixels;
    var worst = 0;
    for (var i = 0; i < a.length; i++) {
      // Colour only: the frame's alpha is not part of the picture.
      if (i % 4 == 3) continue;
      final d = (a[i] - b[i]).abs();
      if (d > worst) worst = d;
    }
    // The jitter keeps moving; a settled history moves with it by a few grey
    // levels at the edges and not at all inside the box.
    expect(worst, lessThan(40));
  });

  test('a cut drops the history', () {
    final it = _staged();
    late Uint8List settled;
    for (var i = 0; i < 32; i++) {
      settled = _draw(it, _settings()).pixels;
    }
    it.view.cut = true;
    final cut = _draw(it, _settings()).pixels;
    it.view.cut = false;
    // Only this frame's jittered samples, read between texels: a softened
    // staircase with far fewer edge greys than the history had built up.
    // Mutation: ignore `view.cut` in `_encodeTemporalResolve`.
    expect(_between(cut) * 2, lessThan(_between(settled)));
  });

  test('the robust sharpen after it moves the edges and not the flats', () {
    RenderSettings sharpened(double amount) => _settings().copyWith(
      antiAlias: AntiAliasSettings(
        temporal: TemporalSettings(enabled: true, sharpen: amount),
      ),
    );
    Uint8List settle(double amount) {
      final it = _staged();
      late Uint8List last;
      for (var i = 0; i < 24; i++) {
        last = _draw(it, sharpened(amount)).pixels;
      }
      return last;
    }

    final soft = settle(0.0);
    final sharp = settle(1.0);
    var edges = 0;
    for (var i = 0; i < soft.length; i += 4) {
      if (soft[i + 1] != sharp[i + 1]) edges++;
    }
    // Mutation: drop the `sharpen.y` branch in `fxaa.frag`'s mirror. The
    // older kernel runs instead and a different set of pixels moves; with
    // the node's condition dropped as well, none do.
    expect(edges, greaterThan(0));
    // The box's middle and the background far from it are flat, and a
    // kernel that cannot ring leaves them exactly where they were.
    final middle = (_height ~/ 2 * _width + _width ~/ 2) * 4;
    expect(sharp[middle + 1], soft[middle + 1]);
    expect(sharp[1], soft[1]);
  });

  test('under a render scale the frame comes back at the asked-for size', () {
    final it = _staged();
    final scaled = _draw(it, _settings(renderScale: 0.5));
    expect(scaled.result.frame.width, _width);
    expect(scaled.result.frame.height, _height);

    // Off, the frame is the smaller one it has always been.
    final off = _draw(_staged(), _settings(temporal: false, renderScale: 0.5));
    expect(off.result.frame.width, _width ~/ 2);
  });
}
