/// A crate that falls, lands, settles, and can be wound back to any of those
/// moments through a snapshot.
///
/// Quoted by `rigid_bodies.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class RigidBodiesDemo extends ShowcaseDemo {
  late final CollisionWorld _world;
  late final Dynamics _dynamics;
  late final RigidBody _crate;
  late final MeshNode _mesh;

  Map<String, Object?>? _settled;
  double _settledHeight = 0.0;

  static const double _step = 1 / 60;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 5.0
      ..pitch = 0.2
      ..yaw = 0.6;
  }

  @override
  Scene build(DemoContext context) {
    // #region world
    _world = CollisionWorld();
    _world.addBox(Vector3(0.0, -0.5, 0.0), Vector3(6.0, 1.0, 6.0));
    _dynamics = Dynamics(world: _world);
    // #endregion world

    // #region body
    _crate = _dynamics.add(
      RigidBody(
        world: _world,
        shape: CollisionBox(Vector3(0.4, 0.4, 0.4)),
        position: Vector3(0.0, 2.0, 0.0),
        mass: 2.0,
        friction: 0.7,
      ),
    );
    // #endregion body

    // #region fall
    // Two hundred and forty steps of a sixtieth of a second: four seconds,
    // comfortably enough for a fall of this height to land, settle below the
    // sleep threshold and actually fall asleep.
    for (var i = 0; i < 240; i++) {
      _dynamics.step(_step);
    }
    // #endregion fall

    // #region snapshot
    _settled = _crate.save();
    _settledHeight = _crate.position.y;
    // #endregion snapshot

    // #region perturb
    // Push it, so it is no longer where the snapshot says it was.
    _crate.applyImpulse(Vector3(3.0, 4.0, 0.0));
    _dynamics.step(_step);
    // #endregion perturb

    // #region restore
    _crate.restore(_settled!);
    // #endregion restore

    _mesh = MeshNode(
      DeviceMesh.upload(
        context.device,
        CuboidShape(size: Vector3(0.8, 0.8, 0.8)).build(),
      ),
      Material(name: 'crate', baseColor: Vector4(0.7, 0.5, 0.3, 1.0)),
      name: 'crate',
    )..setPositionFrom(_crate.position);

    return Scene()
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            CuboidShape(size: Vector3(6.0, 1.0, 6.0)).build(),
          ),
          Material(name: 'floor', baseColor: Vector4(0.5, 0.55, 0.5, 1.0)),
          name: 'floor',
        )..setPosition(0.0, -0.5, 0.0),
      )
      ..add(_mesh)
      ..add(
        LightNode(name: 'sun', intensity: 2.5)
          ..setLocalForward(Vector3(-0.3, -0.6, -0.4)),
      );
  }

  @override
  void update(DemoContext context, double dt) {
    _mesh.setPositionFrom(_crate.position);
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    // It should have come to rest on the floor, not fallen through it or
    // stayed hanging in the air.
    if ((_settledHeight - 0.4).abs() > 0.05) {
      throw StateError(
        'the crate should have settled at y = 0.4, got $_settledHeight',
      );
    }
    // The restore should have undone the impulse exactly.
    if ((_crate.position.y - _settledHeight).abs() > 1e-9) {
      throw StateError('restore should have put the crate back where it was');
    }
    if (_crate.velocity.length2 != 0.0) {
      throw StateError(
        'the settled snapshot should have carried zero velocity',
      );
    }
    // #endregion check
    if (frame.drawCalls < 1) {
      throw StateError('the crate did not reach the frame');
    }
  }
}
