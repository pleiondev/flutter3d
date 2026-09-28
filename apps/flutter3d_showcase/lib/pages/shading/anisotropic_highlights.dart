/// One highlight round, the same highlight stretched: the anisotropy layer.
///
/// Quoted by `anisotropic_highlights.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class AnisotropicHighlightsDemo extends ShowcaseDemo {
  double strength = 0.9;
  double rotation = 0.0;

  late final Material _brushed;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 3.4
      ..yaw = 0.0
      ..pitch = 0.1;
  }

  @override
  Scene build(DemoContext context) {
    // #region materials
    final Material plain = Material(
      name: 'plain',
      lighting: LightingModel.pbrLayered,
      baseColor: Vector4(0.8, 0.05, 0.05, 1.0),
      roughness: 0.3,
    );
    _brushed = Material(
      name: 'brushed',
      lighting: LightingModel.pbrLayered,
      baseColor: Vector4(0.8, 0.05, 0.05, 1.0),
      roughness: 0.3,
      extensions: MaterialExtensions(
        anisotropyStrength: strength,
        anisotropyRotation: rotation,
      ),
    );
    // #endregion materials

    // #region mesh
    // A sphere from `SphereShape` carries a tangent at every vertex, running
    // around the sphere along its lines of latitude.
    final DeviceMesh ball = DeviceMesh.upload(
      context.device,
      SphereShape(radius: 0.5, segments: 48, rings: 24).build(),
    );
    // #endregion mesh

    return Scene()
      ..ambientIntensity = 0.15
      ..add(MeshNode(ball, plain, name: 'plain')..setPosition(-0.6, 0.0, 0.0))
      ..add(
        MeshNode(ball, _brushed, name: 'brushed')..setPosition(0.6, 0.0, 0.0),
      )
      ..add(
        LightNode(name: 'key', intensity: 3.0)
          ..setLocalForward(Vector3(-0.35, -0.45, -1.0).normalized()),
      );
  }

  @override
  void update(DemoContext context, double dt) {
    // #region live
    _brushed.extensions = MaterialExtensions(
      anisotropyStrength: strength,
      anisotropyRotation: rotation,
    );
    // #endregion live
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Strength',
      min: 0,
      max: 1,
      value: () => strength,
      onChanged: (double v) => strength = v,
    ),
    SliderControl(
      'Rotation',
      min: 0,
      max: math.pi,
      value: () => rotation,
      onChanged: (double v) => rotation = v,
      format: (double v) => '${(v * 180 / math.pi).round()}°',
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    final MeshNode brushed = scene.meshes.firstWhere(
      (MeshNode m) => m.name == 'brushed',
    );
    if (!identical(brushed.material.lighting, LightingModel.pbrLayered)) {
      throw StateError('the brushed sphere is not on the layered model');
    }
    if ((brushed.material.extensions?.anisotropyStrength ?? 0.0) <= 0.0) {
      throw StateError('the brushed sphere has no anisotropy');
    }
    if (frame.drawCalls < 2) {
      throw StateError('the two spheres were not both drawn');
    }
  }
}
