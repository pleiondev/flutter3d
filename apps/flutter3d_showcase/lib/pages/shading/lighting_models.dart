/// The six lighting models the engine ships, one sphere each.
///
/// Quoted by `lighting_models.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class LightingModelsDemo extends ShowcaseDemo {
  double roughness = 0.4;
  double sunIntensity = 3.0;

  late final List<Material> _materials;
  late final LightNode _sun;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 5.6
      ..pitch = 0.2
      ..yaw = 0.0
      ..apply();
  }

  @override
  Scene build(DemoContext context) {
    // #region models
    _materials = <Material>[
      for (final LightingModel model in LightingModel.builtIn)
        Material(
          name: model.label,
          lighting: model,
          baseColor: Vector4(0.85, 0.45, 0.3, 1.0),
          roughness: roughness,
        ),
    ];
    // #endregion models

    // #region row
    final DeviceMesh sphere = DeviceMesh.upload(
      context.device,
      const SphereShape(segments: 40, rings: 20).build(),
    );
    final Scene scene = Scene();
    for (var i = 0; i < _materials.length; i++) {
      scene.add(
        MeshNode(sphere, _materials[i], name: _materials[i].name)
          ..setPosition((i % 3 - 1) * 1.35, i < 3 ? 0.7 : -0.7, 0.0),
      );
    }
    // #endregion row

    // #region light
    _sun = LightNode(name: 'sun', intensity: sunIntensity)
      ..setLocalForward(Vector3(-0.4, -0.6, -0.7));
    scene.add(_sun);
    // #endregion light
    return scene;
  }

  @override
  void update(DemoContext context, double dt) {
    // #region live
    for (final Material material in _materials) {
      material.roughness = roughness;
    }
    _sun.intensity = sunIntensity;
    // #endregion live
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Roughness',
      min: 0.05,
      max: 1,
      value: () => roughness,
      onChanged: (double v) => roughness = v,
    ),
    SliderControl(
      'Sun',
      min: 0,
      max: 6,
      value: () => sunIntensity,
      onChanged: (double v) => sunIntensity = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    final int models = LightingModel.builtIn.length;
    final FramePass drawn = frame.passes.firstWhere(
      (FramePass pass) => pass.name == 'scene',
    );
    if (drawn.drawCalls != models) {
      throw StateError('${drawn.drawCalls} draws for $models spheres');
    }
    if (drawn.pipelineSwitches != models) {
      throw StateError(
        'the $models models used ${drawn.pipelineSwitches} pipelines; '
        'each model is a shader of its own',
      );
    }
  }
}
