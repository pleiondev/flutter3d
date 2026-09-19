/// The part of a chasing view every chasing view has: easing towards where
/// it should be, carrying a knock or a shake that fades, and staying out of
/// the walls.
///
/// Quoted by `camera_shake.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

// #region tuning
/// The six numbers `CameraRig` needs to place itself, gathered under a name
/// this page's own view uses.
final class _ChaseTuning extends RigTuning {
  const _ChaseTuning()
    : super(
        distance: 4.0,
        height: 1.5,
        aimHeight: 1.0,
        lag: 8.0,
        nearClearance: 0.3,
        minDistance: 1.0,
      );
}
// #endregion tuning

final class CameraShakeDemo extends ShowcaseDemo {
  bool shaken = false;

  late final CameraRig _rig;
  late final MeshNode _ball;
  final Vector3 _target = Vector3.zero();

  @override
  Scene build(DemoContext context) {
    // #region rig
    _rig = CameraRig(world: CollisionWorld());
    // #endregion rig

    final material = Material(
      name: 'runner',
      baseColor: Vector4(0.6, 0.6, 0.9, 1.0),
    );
    _ball = MeshNode(
      DeviceMesh.upload(context.device, SphereShape(segments: 16).build()),
      material,
    );
    return Scene()
      ..add(_ball)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
      );
  }

  @override
  void configureView(DemoContext context) => context.orbit.frameBounds(
    Aabb3.minMax(Vector3(-2, -2, -2), Vector3(2, 2, 2)),
  );

  // #region place
  static const _tuning = _ChaseTuning();

  void _place(double dt) {
    if (shaken) {
      _rig.kick(Vector3(0, -0.4, 0));
      _rig.shake(0.05, seconds: 0.3);
      shaken = false;
    }
    final desiredEye = Vector3(0, _tuning.height, _tuning.distance);
    _rig.place(
      desiredEye: desiredEye,
      desiredTarget: _target,
      lag: _tuning.lag,
      dt: dt,
    );
  }
  // #endregion place

  @override
  void update(DemoContext context, double dt) {
    _place(dt);
    _ball.setPositionFrom(_rig.eye);
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'Kick the rig',
      value: () => shaken,
      onChanged: (bool v) => shaken = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the marker was not drawn');
    }
    // #region settle
    // Placed enough times with nothing disturbing it, the rig settles to
    // within a few millimetres of the free eye it is chasing.
    for (var i = 0; i < 240; i++) {
      _place(1 / 60);
    }
    final settledGap = (_rig.eye - _rig.freeEye).length;
    // #endregion settle
    if (settledGap > 0.01) {
      throw StateError(
        'an undisturbed rig should settle onto its free eye, '
        'gap was $settledGap',
      );
    }
  }
}
