/// An [Object3dComponent] keeps a Flame position and a flutter3d [SceneNode]
/// at the same place, on whichever side [SyncDirection] names.
library;

import 'package:flame/components.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_flame/flutter3d_flame.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' hide Plane;

void main() {
  test('mounting adds the node to the scene, once', () {
    final scene = Scene();
    final node = SceneNode();
    final component = Object3dComponent(
      node: node,
      scene: scene,
      plane: BridgePlane.ground(),
    );

    component.onMount();

    expect(node.parent, scene.root);
  });

  test('removing detaches the node from the scene', () {
    final scene = Scene();
    final node = SceneNode();
    final component = Object3dComponent(
      node: node,
      scene: scene,
      plane: BridgePlane.ground(),
    )..onMount();

    component.onRemove();

    expect(node.parent, isNull);
  });

  test('sceneToFlame copies the node onto the Flame position each frame', () {
    final scene = Scene();
    final node = SceneNode()..setPosition(1.0, 0.0, 2.0);
    final component = Object3dComponent(
      node: node,
      scene: scene,
      plane: BridgePlane.ground(),
    )..onMount();

    node.setPosition(3.0, 0.0, 4.0);
    component.update(1 / 60);

    expect(component.position, Vector2(3.0, 4.0));
  });

  test('flameToScene copies the Flame position onto the node each frame', () {
    final scene = Scene();
    final node = SceneNode();
    final component = Object3dComponent(
      node: node,
      scene: scene,
      plane: BridgePlane.ground(height: 1.5),
      direction: SyncDirection.flameToScene,
    )..onMount();

    component.position = Vector2(5.0, 6.0);
    component.update(1 / 60);

    final read = node.readPosition();
    expect(read.x, 5.0);
    expect(read.y, 1.5);
    expect(read.z, 6.0);
  });

  test('a sceneToFlame component leaves the node alone on update', () {
    final scene = Scene();
    final node = SceneNode()..setPosition(9.0, 0.0, 9.0);
    final component = Object3dComponent(
      node: node,
      scene: scene,
      plane: BridgePlane.ground(),
    )..onMount();

    component.update(1 / 60);

    expect(node.readPosition(), Vector3(9.0, 0.0, 9.0));
  });
}
