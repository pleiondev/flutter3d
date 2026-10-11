/// The scene the plugin is tried in: an oak ball dropped on a granite
/// floor, its contacts on the bus, and a body in the world that follows it
/// with a material state of its own.
library;

import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

/// Stages the scene in [loop]: the bodies, the step that moves them and
/// publishes their contacts, and the entity that follows the ball. The
/// bodies are a snapshot part of their own, so a rollback and the
/// double-step check put them back with the world.
void dropBall(EngineLoop loop, {double height = 0.6}) {
  final world = CollisionWorld()
    ..add(
      Collider(
        shape: CollisionBox(Vector3(4.0, 0.5, 4.0)),
        position: Vector3(0.0, -0.5, 0.0),
        material: Materials.granite,
      ),
    );
  final ball = RigidBody(
    world: world,
    shape: CollisionSphere(0.25),
    position: Vector3(0.25, height, 0.0),
    material: Materials.oak,
  );
  final dynamics = Dynamics(world: world)..add(ball);
  declareSimulationEvents(loop.events);
  loop.snapshots.add(
    SnapshotPart.of(
      id: 'scene.bodies',
      capture: () => <String, Object?>{
        'ball': ball.save(),
        'dynamics': dynamics.saveState(),
      },
      restore: (Object? data, int _) {
        final saved = data! as Map<String, Object?>;
        ball.restore(saved['ball']! as Map<String, Object?>);
        dynamics.restoreState(saved['dynamics']);
      },
    ),
  );
  final follower = loop.world.spawn();
  loop.world
    ..set(follower, WorldPosition(ball.position.x, height, ball.position.z))
    ..set(follower, const MaterialStateComponent(MaterialState.standard));
  loop.addSystem('scene.drop', LoopPhase.physics, (LoopContext context) {
    dynamics.step(context.dt);
    ContactEvent.publishAll(dynamics.contacts, context.publish);
    final at = ball.position;
    context.world.set(follower, WorldPosition(at.x, at.y, at.z));
  });
}
