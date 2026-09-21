/// [ActorComponent] keeps a Flame position in step with the body a real
/// flutter3d_sim [Actor] simulates.
library;

import 'package:flame_flutter3d/src/ecs/actor_component.dart';
import 'package:flame_flutter3d/src/transform/plane.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' hide Plane;

ActorSystem _system() =>
    ActorSystem(world: CollisionWorld(), random: GameRandom(1));

void main() {
  test('copies the actor body position onto the Flame position each frame', () {
    final scene = Scene();
    final node = SceneNode();
    final system = _system();
    final body = CharacterController(world: system.world);
    final actor = system.spawn(body: body);

    final component = ActorComponent(
      actor: actor,
      node: node,
      scene: scene,
      plane: BridgePlane.ground(),
    )..onMount();

    body.position.setValues(3.0, 0.0, 4.0);
    component.update(1 / 60);

    expect(component.position, Vector2(3.0, 4.0));
    // The node was updated too, not only the Flame side — the body's
    // position reaches it through `node`, not around it.
    expect(node.readPosition(), Vector3(3.0, 0.0, 4.0));
  });

  test('leaves the Flame position untouched when the actor has no body', () {
    final scene = Scene();
    final node = SceneNode()..setPosition(1.0, 0.0, 2.0);
    final system = _system();
    final actor = system.spawn();

    final component = ActorComponent(
      actor: actor,
      node: node,
      scene: scene,
      plane: BridgePlane.ground(),
    )..onMount();

    component.update(1 / 60);

    expect(component.position, Vector2(1.0, 2.0));
  });

  test('onRemove detaches the node without throwing after despawn', () {
    final scene = Scene();
    final node = SceneNode();
    final system = _system();
    final body = CharacterController(world: system.world);
    final actor = system.spawn(body: body);

    final component = ActorComponent(
      actor: actor,
      node: node,
      scene: scene,
      plane: BridgePlane.ground(),
    )..onMount();

    system.remove(actor);
    expect(actor.exists, isFalse);

    expect(component.onRemove, returnsNormally);
    expect(node.parent, isNull);
  });

  test('update does not throw once its actor has been despawned', () {
    final scene = Scene();
    final node = SceneNode();
    final system = _system();
    final body = CharacterController(world: system.world);
    final actor = system.spawn(body: body);

    final component = ActorComponent(
      actor: actor,
      node: node,
      scene: scene,
      plane: BridgePlane.ground(),
    )..onMount();

    system.remove(actor);

    // actor.body now reads null; update must treat that as "nothing to
    // copy", the same as an actor that never had a body.
    expect(() => component.update(1 / 60), returnsNormally);
  });
}
