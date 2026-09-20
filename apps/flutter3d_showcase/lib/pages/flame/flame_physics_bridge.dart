/// `RigidBodyComponent` and `CollisionBridge` carrying a falling
/// `RigidBody`'s own physics, and its landing, onto Flame.
///
/// Quoted by `flame_physics_bridge.md` and shown whole in the Source tab.
library;

import 'package:flame/components.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_flame/flutter3d_flame.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

/// Records the first collision this bridged crate hears about.
final class _TrackingRigidBodyComponent extends RigidBodyComponent {
  _TrackingRigidBodyComponent({
    required super.body,
    required super.node,
    required super.scene,
    required super.plane,
  });

  bool collided = false;
  PositionComponent? other;

  @override
  void onCollisionStart(
    Set<Vector2> intersectionPoints,
    PositionComponent other,
  ) {
    super.onCollisionStart(intersectionPoints, other);
    collided = true;
    this.other = other;
  }
}

final class FlamePhysicsBridgeDemo extends ShowcaseDemo {
  late final String _report;
  late final double _crateHeight;
  late final bool _collided;

  @override
  Scene build(DemoContext context) {
    final (String report, double height, bool collided) = _run(context.device);
    _report = report;
    _crateHeight = height;
    _collided = collided;

    final node = MeshNode(
      DeviceMesh.upload(
        context.device,
        CuboidShape(size: Vector3(0.6, 0.6, 0.6)).build(),
      ),
      Material(name: 'crate', baseColor: Vector4(0.7, 0.5, 0.3, 1.0)),
    )..setPosition(0.0, _crateHeight, 0.0);

    return Scene()
      ..add(node)
      ..add(
        LightNode(name: 'sun', intensity: 2.5)
          ..setLocalForward(Vector3(-0.3, -0.6, -0.4)),
      );
  }

  static (String, double, bool) _run(GraphicsDevice device) {
    // #region world
    final world = CollisionWorld();
    world.addBox(Vector3(0.0, -0.5, 0.0), Vector3(6.0, 1.0, 6.0));
    // A thin trigger embedded just above the floor, so the crate's fall
    // genuinely overlaps something: `Dynamics` stops a falling body exactly
    // at the surface it lands on, never inside it, so the floor itself never
    // reports an overlap to relay. `Dynamics.step` ignores triggers entirely
    // (`includeTriggers: false` in its own contact queries), so this sensor
    // never affects how or where the crate actually lands.
    final landingSensor = world.add(
      Collider(
        shape: CollisionBox(Vector3(3.0, 0.05, 3.0)),
        position: Vector3(0.0, 0.02, 0.0),
        kind: ColliderKind.trigger,
      ),
    );
    final dynamics = Dynamics(world: world);
    // #endregion world

    // #region body
    final body = dynamics.add(
      RigidBody(
        world: world,
        shape: CollisionBox(Vector3(0.3, 0.3, 0.3)),
        position: Vector3(0.0, 2.0, 0.0),
        mass: 1.0,
      ),
    );
    // #endregion body

    // #region bridge
    final scene = Scene();
    final node = MeshNode(
      DeviceMesh.upload(
        device,
        CuboidShape(size: Vector3(0.6, 0.6, 0.6)).build(),
      ),
      Material(name: 'bridged-crate', baseColor: Vector4(0.7, 0.5, 0.3, 1.0)),
    );
    scene.add(node);
    final component = _TrackingRigidBodyComponent(
      body: body,
      node: node,
      scene: scene,
      plane: BridgePlane.ground(),
    );
    // A Flame component standing in for the landing sensor, so the bridge
    // below has somewhere real to hand back — a collider with no Flame side
    // of its own would make `resolveOther` answer null, and the bridge
    // calls nothing when it does.
    final landingMarker = PositionComponent();
    CollisionBridge(
      collider: body.collider,
      component: component,
      resolveOther: (Collider other) =>
          other == landingSensor ? landingMarker : null,
    );
    // #endregion bridge

    // #region fall
    // Falls, lands, and the world dispatches the overlap each step — the
    // same two calls `physics_particles/collision_layers.dart` already makes
    // by hand, now feeding a Flame collision callback instead of a listener
    // this page owns directly.
    const double step = 1 / 60;
    for (var i = 0; i < 180; i++) {
      dynamics.step(step);
      world.update();
    }
    component.update(step);
    // #endregion fall

    return (
      'the crate settled at y=${body.position.y}; the bridge heard about '
          'the landing: ${component.collided}',
      body.position.y,
      component.collided,
    );
  }

  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) =>
      Container(
        color: const Color(0xFF14161A),
        padding: const EdgeInsets.all(24),
        alignment: Alignment.topLeft,
        child: DefaultTextStyle(
          style: const TextStyle(color: Color(0xFFE8E8EC), fontSize: 16),
          child: Text(_report),
        ),
      );

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the crate marker was not drawn');
    }
    // Compared as numbers and booleans, not read back out of `_report`: see
    // `sim_audio_xr/actors.dart` for why.
    if ((_crateHeight - 0.3).abs() > 0.05) {
      throw StateError(
        'the crate should have settled at y = 0.3, got $_crateHeight',
      );
    }
    if (!_collided) {
      throw StateError(
        'CollisionBridge should have relayed the landing to the Flame '
        'component',
      );
    }
  }
}
