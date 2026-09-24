import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import '../level_scene.dart';
import 'light_views.dart';

/// A level drawn by the software rasteriser under any set of lights, in
/// linear light: the renderer the light optimizer asks what a light does.
///
/// **Linear, because lights add.** With the tone curve off and the exposure
/// at one, the frame is the scene's radiance behind nothing but the sRGB
/// encode, which is undone here exactly — so the picture under two lights is
/// the picture under each added together, shadows and all. That sum is what
/// lets [LightOptimizer] render every light once and then try thousands of
/// strengths without drawing again; the frozen visibility the optimizer
/// works under is exactly this: a light's shadow is the one it cast when it
/// was drawn.
///
/// The level's own lights are taken out of the scene it builds: which lights
/// a picture has is the question every call answers differently.
final class LightShading {
  LightShading._(
    this._device,
    this._renderer,
    this._scene,
    this.width,
    this.height,
  );

  /// The level's brushes and probes, ready to be lit.
  factory LightShading.of(Level level, {int width = 160, int height = 100}) {
    final it = cpuTestDevice(width: width, height: height);
    final parts = const LevelScene().build(level, device: it.device);
    for (final light in parts.lights) {
      parts.scene.remove(light);
    }
    return LightShading._(
      it.device,
      Renderer.create(
        device: it.device,
        fallbackAlbedo: it.albedo,
        fallbackNormal: it.normal,
      ),
      parts.scene,
      width,
      height,
    );
  }

  final CpuDevice _device;
  final Renderer _renderer;
  final Scene _scene;
  final int width;
  final int height;

  /// Pixels in one picture.
  int get pixels => width * height;

  /// Nothing after the lighting that is not linear in it: no tone curve, an
  /// exposure of one, no bloom — whose threshold lets a bright pixel glow
  /// and a dim one not — and no dither, whose step of a byte, added after
  /// the encode, is a large share of a dark pixel once the encode is undone.
  /// The rest of the defaults leave every non-linear effect off.
  static const RenderSettings settings = RenderSettings(
    tonemap: false,
    exposure: 1.0,
    bloom: BloomSettings(enabled: false),
    look: LookSettings(dither: 0.0),
  );

  /// [view] under [lights], as linear RGB, three floats a pixel from the top
  /// left.
  Float32List render(LightView view, Iterable<LevelLight> lights) {
    // **Never no lights at all.** A scene with none draws a few pixels along
    // the seams where brushes meet differently from the same scene with any
    // light in it, so the unlit picture was not the zero of the sum and the
    // pictures did not add up there. A light a billionth as strong as a
    // candle puts the frame on the same path and adds nothing measurable.
    final nodes = <LightNode>[
      for (final light in lights) LevelScene.lightOf(light),
      if (lights.isEmpty)
        LevelScene.lightOf(
          LevelLight(position: view.from, intensity: 1e-9, castsShadow: false),
        ),
    ];
    for (final node in nodes) {
      _scene.add(node);
    }
    final eye = CameraNode(
      projection: const PerspectiveProjection(
        fovYRadians: 1.2,
        near: 0.05,
        far: 200.0,
      ),
    )..setPositionFrom(view.from);
    eye.lookAt(view.at);
    _scene.add(eye);
    try {
      final result = _renderer.render(
        width: width,
        height: height,
        scene: _scene,
        views: <RenderView>[
          RenderView(camera: eye, clearColor: Vector4(0.0, 0.0, 0.0, 1.0)),
        ],
        settings: settings,
      );
      final rgba = _device.readHdrPixels(result.frame);
      final out = Float32List(pixels * 3);
      for (var p = 0; p < pixels; p++) {
        out[p * 3] = linearOf(rgba[p * 4]);
        out[p * 3 + 1] = linearOf(rgba[p * 4 + 1]);
        out[p * 3 + 2] = linearOf(rgba[p * 4 + 2]);
      }
      return out;
    } finally {
      _scene.remove(eye);
      for (final node in nodes) {
        _scene.remove(node);
      }
    }
  }

  /// The composite's sRGB encode undone: the curve `color.glsl` writes,
  /// run backwards, including the stretch past one it applies to a value
  /// the tone curve would have rolled off.
  static double linearOf(double encoded) => encoded <= 0.04045
      ? math.max(encoded, 0.0) / 12.92
      : math.pow((encoded + 0.055) / 1.055, 2.4).toDouble();

  /// A linear value as a display byte would show it at [exposure]: exposed,
  /// clipped and encoded — what the difference between two pictures is
  /// measured in, since that is where a person sees it.
  static double displayOf(double linear, {double exposure = 1.0}) {
    final c = (linear * exposure).clamp(0.0, 1.0);
    return c < 0.0031308
        ? c * 12.92
        : 1.055 * math.pow(c, 1.0 / 2.4).toDouble() - 0.055;
  }
}
