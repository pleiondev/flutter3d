/// Light that comes from the surroundings: a cube map of the sky, blurred once
/// per roughness, is all that lights these spheres.
///
/// Quoted by `image_based_lighting.md` and shown whole in the Source tab.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class ImageBasedLightingDemo extends ShowcaseDemo {
  bool lit = true;
  int source = 0;
  double strength = 1.0;
  double metallic = 1.0;

  ({TextureHandle texture, int levels})? _fromSky;
  ({TextureHandle texture, int levels})? _fromPanorama;
  late final List<Material> _balls;
  late final Scene _scene;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 7.5
      ..pitch = 0.1
      ..yaw = 0.0;
    context.orbit.target.setValues(0.0, 0.0, 0.0);
    context.orbit.apply();
  }

  @override
  Scene build(DemoContext context) {
    // #region environments
    _fromSky = EnvironmentMap.fromSky(
      context.device,
      const SkySettings(enabled: true, glowStrength: 0.4, sunIntensity: 2.0),
    );
    _fromPanorama = EnvironmentMap.fromPanorama(
      context.device,
      _studioPanorama(),
      width: 64,
      height: 32,
    );
    // #endregion environments

    // #region balls
    final DeviceMesh sphere = DeviceMesh.upload(
      context.device,
      SphereShape(radius: 0.8, segments: 32, rings: 16).build(),
    );
    final Scene scene = _scene = Scene();
    _balls = <Material>[];
    for (var i = 0; i < 5; i++) {
      final Material material = Material(
        name: 'ball $i',
        lighting: LightingModel.pbr,
        baseColor: Vector4(0.95, 0.75, 0.45, 1.0),
        metallic: metallic,
        roughness: 0.05 + i * 0.24,
      );
      _balls.add(material);
      scene.add(
        MeshNode(sphere, material, name: 'ball $i')
          ..setPosition(i * 1.9 - 3.8, 0.0, 0.0),
      );
    }
    // #endregion balls
    return scene;
  }

  @override
  void update(DemoContext context, double dt) {
    // #region use
    final ({TextureHandle texture, int levels})? chosen = source == 0
        ? _fromSky
        : _fromPanorama;
    _scene
      ..environment = lit ? chosen?.texture : null
      ..environmentLevels = chosen?.levels ?? 0
      ..ambientIntensity = strength;
    // #endregion use
    for (final Material ball in _balls) {
      ball.metallic = metallic;
    }
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'Environment on',
      value: () => lit,
      onChanged: (bool v) => lit = v,
    ),
    ChoiceControl(
      'Environment',
      options: const <String>['Sky', 'Studio panorama'],
      index: () => source,
      onChanged: (int i) => source = i,
    ),
    SliderControl(
      'Strength',
      min: 0,
      max: 2,
      value: () => strength,
      onChanged: (double v) => strength = v,
    ),
    SliderControl(
      'Metallic',
      min: 0,
      max: 1,
      value: () => metallic,
      onChanged: (double v) => metallic = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    if (scene.lights.isNotEmpty) {
      throw StateError('this page has no direct light on purpose');
    }
    if (scene.environment == null || scene.environmentLevels < 1) {
      throw StateError('the environment cube was not built or not bound');
    }
  }
}

// A 64 by 32 equirectangular picture: a cool sky, a warm floor and one bright
// window to the side, so the two halves of the spheres differ.
ByteData _studioPanorama() {
  const int width = 64;
  const int height = 32;
  final ByteData pixels = ByteData(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final bool sky = y < height ~/ 2;
      final bool window = x > 40 && x < 52 && y > 8 && y < 16;
      final (int, int, int) rgb = window
          ? (255, 250, 235)
          : sky
          ? (70, 100, 150)
          : (110, 80, 60);
      final int at = (y * width + x) * 4;
      pixels
        ..setUint8(at, rgb.$1)
        ..setUint8(at + 1, rgb.$2)
        ..setUint8(at + 2, rgb.$3)
        ..setUint8(at + 3, 255);
    }
  }
  return pixels;
}
