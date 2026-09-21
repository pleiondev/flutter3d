/// A [RigidBodyComponent] keeps a real [RigidBody]'s position mirrored onto
/// both a flutter3d [SceneNode] and its own Flame [position], every frame.
library;

import 'package:flame_flutter3d/src/physics/rigid_body_component.dart';
import 'package:flame_flutter3d/src/transform/object3d_component.dart';
import 'package:flame_flutter3d/src/transform/plane.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' hide Plane;

void main() {
  test('defaults to sceneToFlame — the body is authoritative', () {
    final world = CollisionWorld();
    final body = RigidBody(
      world: world,
      shape: CollisionBox(Vector3(0.5, 0.5, 0.5)),
      position: Vector3.zero(),
    );
    final component = RigidBodyComponent(
      body: body,
      node: SceneNode(),
      scene: Scene(),
      plane: BridgePlane.ground(),
    );

    expect(component.direction, SyncDirection.sceneToFlame);
  });

  test(
    'mounting adds the node to the scene, the same as any Object3dComponent',
    () {
      final world = CollisionWorld();
      final body = RigidBody(
        world: world,
        shape: CollisionBox(Vector3(0.5, 0.5, 0.5)),
        position: Vector3.zero(),
      );
      final scene = Scene();
      final node = SceneNode();
      final component = RigidBodyComponent(
        body: body,
        node: node,
        scene: scene,
        plane: BridgePlane.ground(),
      );

      component.onMount();

      expect(node.parent, scene.root);
    },
  );

  test('update copies the body position, after applyImpulse and a Dynamics '
      'step, onto both the node and the Flame position', () {
    final world = CollisionWorld();
    final dynamics = Dynamics(world: world, gravity: Vector3.zero());
    final body = dynamics.add(
      RigidBody(
        world: world,
        shape: CollisionBox(Vector3(0.5, 0.5, 0.5)),
        position: Vector3(0.0, 5.0, 0.0),
      ),
    );
    final scene = Scene();
    final node = SceneNode();
    final plane = BridgePlane.ground();
    final component = RigidBodyComponent(
      body: body,
      node: node,
      scene: scene,
      plane: plane,
    )..onMount();

    body.applyImpulse(Vector3(6.0, 0.0, 0.0));
    dynamics.step(1 / 60);
    // The body actually moved — otherwise this test would pass even if
    // `update` copied nothing.
    expect(body.position.x, isNot(0.0));

    component.update(1 / 60);

    expect(node.readPosition(), body.position);
    expect(component.position, plane.to2d(body.position));
  });

  test('a second update tracks a body that keeps moving', () {
    final world = CollisionWorld();
    final dynamics = Dynamics(world: world, gravity: Vector3.zero());
    final body = dynamics.add(
      RigidBody(
        world: world,
        shape: CollisionBox(Vector3(0.5, 0.5, 0.5)),
        position: Vector3.zero(),
      ),
    );
    final scene = Scene();
    final node = SceneNode();
    final plane = BridgePlane.ground();
    final component = RigidBodyComponent(
      body: body,
      node: node,
      scene: scene,
      plane: plane,
    )..onMount();

    body.applyImpulse(Vector3(4.0, 0.0, 2.0));
    dynamics.step(1 / 60);
    component.update(1 / 60);
    final firstX = node.readPosition().x;

    dynamics.step(1 / 60);
    component.update(1 / 60);

    expect(node.readPosition(), body.position);
    expect(node.readPosition().x, isNot(firstX));
    expect(component.position, plane.to2d(body.position));
  });
}
