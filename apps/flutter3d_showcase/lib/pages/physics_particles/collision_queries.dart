/// A raycast, a sweep and an overlap against the same small level, reported
/// as text: three questions a `CollisionWorld` answers exactly rather than
/// a picture asking you to take its word for it.
///
/// Quoted by `collision_queries.md` and shown whole in the Source tab.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class CollisionQueriesDemo extends ShowcaseDemo {
  late final CollisionWorld _world;
  late final Collider _pickup;

  final RayHit _ray = RayHit();
  final SweepHit _sweep = SweepHit();
  final List<Collider> _overlapping = <Collider>[];

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 8.0
      ..pitch = 0.25
      ..yaw = 0.6;
  }

  @override
  Scene build(DemoContext context) {
    // #region world
    _world = CollisionWorld();
    final Collider wall = _world.add(
      Collider(
        shape: CollisionBox(Vector3(2.0, 1.0, 0.2)),
        position: Vector3(0.0, 1.0, 0.0),
      ),
    );
    _pickup = _world.add(
      Collider(
        shape: CollisionSphere(0.4),
        position: Vector3(2.0, 0.5, 2.0),
        kind: ColliderKind.trigger,
      ),
    );
    // A trigger is not level geometry: `add` files anything that is not
    // `ColliderKind.static` as a mover, and a mover's grid cell is only
    // filled in when the world is asked to index it.
    _world.reindex();
    // #endregion world

    // #region raycast
    _world.raycast(Vector3(0.0, 1.0, 5.0), Vector3(0.0, 0.0, -1.0), 10.0, _ray);
    // #endregion raycast

    // #region sweep
    _world.sweep(
      CollisionBox(Vector3(0.3, 0.5, 0.3)),
      Vector3(0.0, 0.5, 3.0),
      Vector3(0.0, 0.0, -4.0),
      _sweep,
    );
    // #endregion sweep

    // #region overlap
    _world.overlap(
      CollisionBox(Vector3(0.1, 0.1, 0.1)),
      _pickup.position,
      _overlapping,
    );
    // #endregion overlap

    return Scene()
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            CuboidShape(size: Vector3(4.0, 2.0, 0.4)).build(),
          ),
          Material(name: 'wall', baseColor: Vector4(0.5, 0.5, 0.6, 1.0)),
          name: 'wall',
        )..setPositionFrom(wall.position),
      )
      ..add(
        LightNode(name: 'sun', intensity: 2.5)
          ..setLocalForward(Vector3(-0.3, -0.6, -0.4)),
      );
  }

  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) {
    String vec3(Vector3 v) =>
        '(${v.x.toStringAsFixed(2)}, ${v.y.toStringAsFixed(2)}, '
        '${v.z.toStringAsFixed(2)})';
    return Container(
      color: const Color(0xFF14161A),
      padding: const EdgeInsets.all(24),
      alignment: Alignment.topLeft,
      child: DefaultTextStyle(
        style: const TextStyle(color: Color(0xFFE8E8EC), fontSize: 15),
        child: Text(
          'raycast: ${_ray.hit ? 'hit at ${vec3(_ray.point)}' : 'miss'}\n'
          'sweep: ${_sweep.hit ? 'stopped at fraction ${_sweep.fraction.toStringAsFixed(3)}, '
                    'normal ${vec3(_sweep.normal)}' : 'clear'}\n'
          'overlap: ${_overlapping.length} collider(s) at the pickup',
        ),
      ),
    );
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    if (!_ray.hit || (_ray.distance - 4.8).abs() > 0.01) {
      throw StateError('the ray should meet the wall 4.8m out');
    }
    if (!_sweep.hit || _sweep.normal.z < 0.9) {
      throw StateError('the sweep should stop on the wall\'s near face');
    }
    if (_overlapping.length != 1 || !identical(_overlapping.first, _pickup)) {
      throw StateError('the overlap should find only the pickup');
    }
    // #endregion check
    if (frame.drawCalls < 1) {
      throw StateError('the wall did not reach the frame');
    }
  }
}
