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

/// A ball of 0.5 kg bounced on the floor by arithmetic alone, its height
/// and speed a component of the world: the scene the conformance suite
/// steps twice from one state.
///
/// **Not the rigid bodies of [dropBall], and why.** A body restored from
/// its save starts its next step with no motion carried in its collider,
/// where the live body had the last step's, so the impulse of the contact
/// it begins differs in its last bits after a rollback, and the double-step
/// check names the step. That is the physics package's to close; this
/// scene keeps the plugin's checks about the plugin.
void bounceBall(EngineLoop loop) {
  loop.world.components.register<_Ball>(_Ball.codec);
  declareSimulationEvents(loop.events);
  final ball = loop.world.spawn();
  loop.world
    ..set(ball, const _Ball(0.6, 0.0))
    ..set(ball, const WorldPosition(0.25, 0.6, 0.0))
    ..set(ball, const MaterialStateComponent(MaterialState.standard));
  loop.addSystem('scene.bounce', LoopPhase.physics, (LoopContext context) {
    final world = context.world;
    final was = world.get<_Ball>(ball)!;
    final dt = context.dt;
    final falling = was.speed - 9.81 * dt;
    final y = was.height + falling * dt;
    if (y > _Ball.radius) {
      world
        ..set(ball, _Ball(y, falling))
        ..set(ball, WorldPosition(0.25, y, 0.0));
      return;
    }
    // On the floor: it bounces back at half its speed, or rests and
    // presses on the floor with its weight.
    final rebound = -falling * 0.5 < 0.05 ? 0.0 : -falling * 0.5;
    final impulse = rebound == 0.0
        ? _Ball.mass * 9.81 * dt
        : _Ball.mass * (rebound - falling);
    world
      ..set(ball, _Ball(_Ball.radius, rebound))
      ..set(ball, const WorldPosition(0.25, _Ball.radius, 0.0));
    context.publish(
      ContactEvent(
        bodyA: 0,
        bodyB: 1,
        materialA: Materials.granite.id,
        materialB: Materials.oak.id,
        phase: was.height > _Ball.radius
            ? ContactPhase.begin
            : ContactPhase.persist,
        point: Vector3(0.25, 0.0, 0.0),
        normal: Vector3(0.0, 1.0, 0.0),
        impulse: impulse,
        relativeVelocity: Vector3(0.0, -falling, 0.0),
      ),
    );
  });
}

/// The bounced ball's height above the floor, in metres, and its upward
/// speed, in metres a second.
final class _Ball {
  const _Ball(this.height, this.speed);

  static const double radius = 0.25;
  static const double mass = 0.5;

  final double height;
  final double speed;

  static final ComponentCodec<_Ball> codec = ComponentCodec<_Ball>.of(
    id: 'scene.ball',
    encode: (_Ball ball) => <double>[ball.height, ball.speed],
    decode: (Object? data, int _) => switch (data) {
      [final num height, final num speed] => _Ball(
        height.toDouble(),
        speed.toDouble(),
      ),
      _ => null,
    },
  );
}
