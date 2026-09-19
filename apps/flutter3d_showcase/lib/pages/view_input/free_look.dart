/// Turning the head from where the camera stands, and walking it there, as
/// opposed to orbiting a point somebody else chose.
///
/// Quoted by `free_look.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class FreeLookDemo extends ShowcaseDemo {
  bool walkingForward = true;

  late final FreeLook _freeLook;
  late Vector3 _targetBefore;
  double _stepSeconds = 0.0;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 4.0
      ..pitch = 0.2;
  }

  @override
  Scene build(DemoContext context) {
    // #region freelook
    _freeLook = FreeLook(context.orbit);
    // #endregion freelook

    final Material stone = Material(
      name: 'stone',
      baseColor: Vector4(0.65, 0.62, 0.58, 1.0),
      roughness: 0.8,
    );
    final Scene scene = Scene();
    final DeviceMesh post = DeviceMesh.upload(
      context.device,
      CuboidShape(size: Vector3(0.4, 2.5, 0.4)).build(),
    );
    for (var i = 0; i < 5; i++) {
      scene.add(
        MeshNode(post, stone, name: 'post $i')..setPosition(0.0, 0.0, -i * 4.0),
      );
    }
    scene.add(
      LightNode(name: 'sun', intensity: 3.0)
        ..setLocalForward(Vector3(-0.3, -1.0, -0.4)),
    );
    return scene;
  }

  // #region walk
  @override
  void update(DemoContext context, double dt) {
    _targetBefore = context.orbit.target.clone();
    _stepSeconds = dt;
    if (walkingForward) {
      _freeLook.walk(forward: 1.0, seconds: dt);
    }
  }
  // #endregion walk

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'Walk forward',
      value: () => walkingForward,
      onChanged: (bool v) => walkingForward = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the posts were not drawn');
    }
    if (!walkingForward) return;
    // walk moves the target by metresPerSecond * seconds along the view
    // axis. The distance actually covered has to match that number exactly,
    // rather than only be nonzero.
    final double moved = (_freeLook.orbit.target - _targetBefore).length;
    final double expected = _freeLook.metresPerSecond * _stepSeconds;
    if ((moved - expected).abs() > 1e-6) {
      throw StateError('walking moved $moved, expected $expected');
    }
  }
}
