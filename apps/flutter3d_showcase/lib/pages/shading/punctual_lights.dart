/// The three punctual light types: directional, point and spot, each with
/// its own sphere so the difference is easy to read.
///
/// Quoted by `punctual_lights.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class PunctualLightsDemo extends ShowcaseDemo {
  double pointRange = 4.0;
  double spotOuterDegrees = 25.0;

  late final LightNode _point;
  late final LightNode _spot;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 7.0
      ..pitch = 0.25;
  }

  @override
  Scene build(DemoContext context) {
    final DeviceMesh sphere = DeviceMesh.upload(
      context.device,
      SphereShape(segments: 32, rings: 16).build(),
    );
    final Scene scene = Scene()
      ..add(
        MeshNode(
          sphere,
          Material(baseColor: Vector4(0.8, 0.8, 0.8, 1.0)),
          name: 'sun ball',
        )..setPosition(-2.2, 0.0, 0.0),
      )
      ..add(
        MeshNode(
          sphere,
          Material(baseColor: Vector4(0.8, 0.8, 0.8, 1.0)),
          name: 'point ball',
        )..setPosition(0.0, 0.0, 0.0),
      )
      ..add(
        MeshNode(
          sphere,
          Material(baseColor: Vector4(0.8, 0.8, 0.8, 1.0)),
          name: 'spot ball',
        )..setPosition(2.2, 0.0, 0.0),
      );

    // #region directional
    final LightNode sun = LightNode(
      name: 'sun',
      type: LightType.directional,
      intensity: 2.0,
    )..setLocalForward(Vector3(-0.3, -0.6, -0.7));
    // #endregion directional

    // #region point
    _point = LightNode(
      name: 'lamp',
      type: LightType.point,
      intensity: 6.0,
      range: pointRange,
    )..setPosition(0.0, 1.6, 1.2);
    // #endregion point

    // #region spot
    _spot = LightNode(
      name: 'torch',
      type: LightType.spot,
      intensity: 10.0,
      range: 6.0,
      innerConeAngle: 0.0,
      outerConeAngle: spotOuterDegrees * math.pi / 180.0,
    )..setPosition(2.2, 2.2, 1.6);
    _spot.lookAt(Vector3(2.2, 0.0, 0.0));
    // #endregion spot

    return scene
      ..add(sun)
      ..add(_point)
      ..add(_spot);
  }

  @override
  void update(DemoContext context, double dt) {
    // #region live
    _point.range = pointRange;
    _spot.outerConeAngle = spotOuterDegrees * math.pi / 180.0;
    // #endregion live
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Point range',
      min: 1,
      max: 10,
      value: () => pointRange,
      onChanged: (double v) => pointRange = v,
    ),
    SliderControl(
      'Spot cone (degrees)',
      min: 5,
      max: 60,
      value: () => spotOuterDegrees,
      onChanged: (double v) => spotOuterDegrees = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    final Set<LightType> types = <LightType>{
      for (final LightNode light in scene.lights) light.type,
    };
    if (types.length != 3) {
      throw StateError('expected all three punctual types, found $types');
    }
    if (_point.range != pointRange) {
      throw StateError('the point light range did not track the slider');
    }
    if (frame.drawCalls < 3) {
      throw StateError('not every ball was drawn');
    }
    // #endregion check
  }
}
