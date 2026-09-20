/// A [CollisionBridge] re-fires flutter3d's own [CollisionListener] events as
/// calls into a [RigidBodyComponent]'s Flame-side [CollisionCallbacks], and
/// stays silent when the caller's own registry has nothing bridged for the
/// other side.
library;

import 'package:flame/components.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_flame/src/physics/collision_bridge.dart';
import 'package:flutter3d_flame/src/physics/rigid_body_component.dart';
import 'package:flutter3d_flame/src/transform/plane.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fires onCollisionStart on the resolved component when two real '
      'colliders overlap after world.update()', () {
    final world = CollisionWorld();
    final scene = Scene();
    final plane = BridgePlane.ground();

    final bodyA = RigidBody(
      world: world,
      shape: CollisionBox(Vector3(0.5, 0.5, 0.5)),
      position: Vector3(0.0, 0.0, 0.0),
    );
    final bodyB = RigidBody(
      world: world,
      shape: CollisionBox(Vector3(0.5, 0.5, 0.5)),
      position: Vector3(0.2, 0.0, 0.0),
    );

    final componentA = RigidBodyComponent(
      body: bodyA,
      node: SceneNode(),
      scene: scene,
      plane: plane,
    );
    final componentB = RigidBodyComponent(
      body: bodyB,
      node: SceneNode(),
      scene: scene,
      plane: plane,
    );

    final registry = <Collider, PositionComponent>{
      bodyA.collider: componentA,
      bodyB.collider: componentB,
    };
    PositionComponent? resolve(Collider other) => registry[other];

    CollisionBridge(
      collider: bodyA.collider,
      component: componentA,
      resolveOther: resolve,
    );
    CollisionBridge(
      collider: bodyB.collider,
      component: componentB,
      resolveOther: resolve,
    );

    world.update();

    expect(componentA.isColliding, isTrue);
    expect(componentA.collidingWith(componentB), isTrue);
    expect(componentB.collidingWith(componentA), isTrue);
  });

  test('reports a plausible 2D point: the midpoint of the two colliders, '
      'projected through the plane', () {
    final world = CollisionWorld();
    final scene = Scene();
    final plane = BridgePlane.ground();

    final bodyA = RigidBody(
      world: world,
      shape: CollisionBox(Vector3(0.5, 0.5, 0.5)),
      position: Vector3(0.0, 0.0, 0.0),
    );
    final bodyB = RigidBody(
      world: world,
      shape: CollisionBox(Vector3(0.5, 0.5, 0.5)),
      position: Vector3(0.2, 0.0, 0.5),
    );

    final componentA = RigidBodyComponent(
      body: bodyA,
      node: SceneNode(),
      scene: scene,
      plane: plane,
    );
    final componentB = RigidBodyComponent(
      body: bodyB,
      node: SceneNode(),
      scene: scene,
      plane: plane,
    );

    final registry = <Collider, PositionComponent>{
      bodyA.collider: componentA,
      bodyB.collider: componentB,
    };

    Set<Vector2>? capturedPoints;
    componentA.onCollisionStartCallback = (points, other) {
      capturedPoints = points;
    };

    CollisionBridge(
      collider: bodyA.collider,
      component: componentA,
      resolveOther: (other) => registry[other],
    );
    CollisionBridge(
      collider: bodyB.collider,
      component: componentB,
      resolveOther: (other) => registry[other],
    );

    world.update();

    final expectedMidpoint = plane.to2d(
      (bodyA.position + bodyB.position) * 0.5,
    );
    expect(capturedPoints, {expectedMidpoint});
  });

  test('calls nothing when resolveOther finds no bridged component for the '
      'other side', () {
    final world = CollisionWorld();
    final scene = Scene();
    final plane = BridgePlane.ground();

    final bodyA = RigidBody(
      world: world,
      shape: CollisionBox(Vector3(0.5, 0.5, 0.5)),
      position: Vector3(0.0, 0.0, 0.0),
    );
    // Overlaps bodyA, but nothing on the Flame side is registered for it.
    RigidBody(
      world: world,
      shape: CollisionBox(Vector3(0.5, 0.5, 0.5)),
      position: Vector3(0.2, 0.0, 0.0),
    );

    final componentA = RigidBodyComponent(
      body: bodyA,
      node: SceneNode(),
      scene: scene,
      plane: plane,
    );

    CollisionBridge(
      collider: bodyA.collider,
      component: componentA,
      resolveOther: (_) => null,
    );

    world.update();

    expect(componentA.isColliding, isFalse);
  });

  test('fires onCollisionEnd once the two colliders separate', () {
    final world = CollisionWorld();
    final scene = Scene();
    final plane = BridgePlane.ground();

    final bodyA = RigidBody(
      world: world,
      shape: CollisionBox(Vector3(0.5, 0.5, 0.5)),
      position: Vector3(0.0, 0.0, 0.0),
    );
    final bodyB = RigidBody(
      world: world,
      shape: CollisionBox(Vector3(0.5, 0.5, 0.5)),
      position: Vector3(0.2, 0.0, 0.0),
    );

    final componentA = RigidBodyComponent(
      body: bodyA,
      node: SceneNode(),
      scene: scene,
      plane: plane,
    );
    final componentB = RigidBodyComponent(
      body: bodyB,
      node: SceneNode(),
      scene: scene,
      plane: plane,
    );

    final registry = <Collider, PositionComponent>{
      bodyA.collider: componentA,
      bodyB.collider: componentB,
    };
    PositionComponent? resolve(Collider other) => registry[other];

    CollisionBridge(
      collider: bodyA.collider,
      component: componentA,
      resolveOther: resolve,
    );
    CollisionBridge(
      collider: bodyB.collider,
      component: componentB,
      resolveOther: resolve,
    );

    world.update();
    expect(componentA.collidingWith(componentB), isTrue);

    bodyB.collider.moveTo(Vector3(20.0, 0.0, 0.0));
    world.update();

    expect(componentA.collidingWith(componentB), isFalse);
    expect(componentB.collidingWith(componentA), isFalse);
  });
}
