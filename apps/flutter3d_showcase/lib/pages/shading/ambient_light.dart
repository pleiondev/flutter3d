/// `Scene.ambientColor` and `Scene.ambientIntensity`: the flat term a surface
/// falls back to wherever no direct light reaches it.
///
/// Quoted by `ambient_light.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class AmbientLightDemo extends ShowcaseDemo {
  double ambientIntensity = 0.35;

  late final Scene _scene;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 4.5
      ..yaw = 1.4
      ..pitch = 0.1;
  }

  @override
  Scene build(DemoContext context) {
    final MeshNode ball = MeshNode(
      DeviceMesh.upload(
        context.device,
        SphereShape(segments: 40, rings: 20).build(),
      ),
      Material(baseColor: Vector4(0.7, 0.7, 0.75, 1.0), roughness: 0.6),
      name: 'ball',
    );

    // #region ambient
    // One light from one side only, so the far side of the ball is lit by
    // nothing but the ambient term below.
    _scene = Scene()
      ..add(ball)
      ..add(
        LightNode(name: 'key', intensity: 3.0)
          ..setLocalForward(Vector3(-0.8, -0.2, -0.2)),
      )
      ..ambientColor = Vector3(0.55, 0.65, 1.0)
      ..ambientIntensity = ambientIntensity;
    // #endregion ambient

    return _scene;
  }

  @override
  void update(DemoContext context, double dt) {
    // #region live
    _scene.ambientIntensity = ambientIntensity;
    // #endregion live
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Ambient intensity',
      min: 0,
      max: 1,
      value: () => ambientIntensity,
      onChanged: (double v) => ambientIntensity = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    if (scene.ambientIntensity != ambientIntensity) {
      throw StateError('the scene ambient did not track the slider');
    }
    if (scene.lights.length != 1) {
      throw StateError(
        'this page needs exactly one direct light to leave a '
        'side for the ambient term to fill',
      );
    }
    if (frame.drawCalls < 1) {
      throw StateError('the ball was not drawn');
    }
    // #endregion check
  }
}
