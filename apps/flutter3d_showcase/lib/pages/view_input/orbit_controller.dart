/// Framing a model automatically, and swinging the view to a new angle
/// instead of jumping to it.
///
/// Quoted by `orbit_controller.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class OrbitControllerDemo extends ShowcaseDemo {
  late final Aabb3 _bounds;
  late final OrbitController _orbit;
  late final double _startYaw;

  @override
  Scene build(DemoContext context) {
    _orbit = context.orbit;
    final Material stone = Material(
      name: 'stone',
      baseColor: Vector4(0.6, 0.66, 0.7, 1.0),
      roughness: 0.7,
    );
    final MeshNode box = MeshNode(
      DeviceMesh.upload(
        context.device,
        CuboidShape(size: Vector3(1.0, 2.0, 1.0)).build(),
      ),
      stone,
      name: 'box',
    );

    // #region bounds
    _bounds = Aabb3.centerAndHalfExtents(
      Vector3.zero(),
      Vector3(0.5, 1.0, 0.5),
    );
    // #endregion bounds

    // #region frame
    context.orbit.frameBounds(_bounds);
    // #endregion frame

    _startYaw = context.orbit.yaw;
    // #region swing
    context.orbit.animateTo(yaw: context.orbit.yaw + math.pi, seconds: 1.2);
    // #endregion swing

    return Scene()
      ..add(box)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
      );
  }

  // #region advance
  @override
  void update(DemoContext context, double dt) {
    context.orbit.advance(dt);
  }
  // #endregion advance

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'Swing to the other side',
      value: () => context.orbit.isTurning,
      onChanged: (bool _) =>
          context.orbit.animateTo(yaw: context.orbit.yaw + math.pi),
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the box was not drawn');
    }
    // frameBounds places the camera at radius / sin(fov / 2) * margin, using
    // its own default field of view and margin. Recomputing that formula for
    // this box's own radius has to land on the distance the orbit actually
    // holds.
    final Vector3 extent = (_bounds.max - _bounds.min)..scale(0.5);
    final double radius = math.max(extent.length, 1e-4);
    final double expected = radius / math.sin(math.pi / 4 * 0.5) * 1.25;
    if ((_orbit.distance - expected).abs() > 1e-6) {
      throw StateError(
        'frameBounds put the camera at ${_orbit.distance}, expected $expected',
      );
    }
    // The camera also spent one frame turning towards the other side, so its
    // yaw must have moved away from wherever frameBounds first pointed it,
    // and the turn must still be in flight after a sixtieth of a second of a
    // 1.2 second swing.
    if (_orbit.yaw == _startYaw || !_orbit.isTurning) {
      throw StateError('advance did not step the turn animateTo started');
    }
  }
}
