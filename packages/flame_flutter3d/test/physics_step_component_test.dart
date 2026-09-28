/// [PhysicsStepComponent] steps, then runs its seam, then dispatches.
library;

import 'package:flame_flutter3d/flame_flutter3d.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

final class _Log with CollisionListener {
  _Log(this.log);

  final List<String> log;

  @override
  void onCollisionStart(Collider self, Collider other) => log.add('contact');
}

void main() {
  test('one update steps the bodies, then runs afterStep, then dispatches '
      'the contacts afterStep made', () {
    // A body flying along X and a trigger that rides five metres above it,
    // put there by `afterStep`. A marker waits where the body will be after
    // one step. The contact can only be reported if the step ran first, the
    // sensor was moved second and the world dispatched last. Mutation:
    // dispatch before the step, or before `afterStep`, and the log has no
    // contact.
    final world = CollisionWorld();
    final dynamics = Dynamics(world: world, gravity: Vector3.zero());
    final body = dynamics.add(
      RigidBody(
        world: world,
        shape: CollisionBox(Vector3.all(0.5)),
        position: Vector3.zero(),
        mass: 1.0,
      ),
    );
    body.velocity.setValues(60.0, 0.0, 0.0);
    final log = <String>[];
    final sensor = world.add(
      Collider(
        shape: CollisionBox(Vector3.all(0.3)),
        position: Vector3(0.0, 5.0, 0.0),
        kind: ColliderKind.trigger,
        listener: _Log(log),
      ),
    );
    world.add(
      Collider(
        shape: CollisionBox(Vector3.all(0.1)),
        position: Vector3(1.0, 5.0, 0.0),
      ),
    );

    PhysicsStepComponent(
      dynamics: dynamics,
      world: world,
      afterStep: () {
        log.add('after');
        sensor.position.setFrom(body.position + Vector3(0.0, 5.0, 0.0));
      },
    ).update(1 / 60);

    expect(body.position.x, greaterThan(0.7), reason: 'the body never moved');
    expect(log, <String>['after', 'contact']);
  });

  test('with no afterStep it still steps and dispatches', () {
    final world = CollisionWorld();
    final dynamics = Dynamics(world: world, gravity: Vector3(0.0, -9.8, 0.0));
    final body = dynamics.add(
      RigidBody(
        world: world,
        shape: CollisionBox(Vector3.all(0.5)),
        position: Vector3(0.0, 5.0, 0.0),
        mass: 1.0,
      ),
    );

    PhysicsStepComponent(dynamics: dynamics, world: world).update(1 / 60);

    expect(body.position.y, lessThan(5.0));
  });
}
