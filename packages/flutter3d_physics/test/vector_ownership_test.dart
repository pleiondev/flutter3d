/// Who owns a vector the physics hands out (docs/CONTRACTS.md, "Space").
///
///     dart test test/vector_ownership_test.dart
///
/// A getter answers a copy, a public `final` field is the live state. Each
/// test writes into what it was given and checks the body did not move, or
/// did, as the shape of the member says.
library;

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('a rigid body\'s position and orientation are copies', () {
    final world = CollisionWorld();
    final body = RigidBody(
      world: world,
      shape: CollisionBox(Vector3.all(0.5)),
      position: Vector3(1.0, 2.0, 3.0),
      canRotate: true,
    );
    // Mutation: return `collider.position` from `RigidBody.position`. The
    // write below moves the body without the broadphase hearing of it.
    body.position.setValues(9.0, 9.0, 9.0);
    // Mutation: return `_orientation` from `RigidBody.orientation`. The
    // turn below leaves the inertia tensor describing the old one.
    body.orientation.setAxisAngle(Vector3(0.0, 1.0, 0.0), 1.0);
    expect(body.collider.position, Vector3(1.0, 2.0, 3.0));
    expect(body.orientation.w, closeTo(1.0, 1e-12));

    // The collider's field is the live one.
    body.collider.position.setValues(4.0, 5.0, 6.0);
    expect(body.position, Vector3(4.0, 5.0, 6.0));
  });

  test('a character\'s extents and ground normal are copies', () {
    final world = CollisionWorld()
      ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(20.0, 1.0, 20.0))
      ..update();
    final player = CharacterController(
      world: world,
      shape: CollisionBox(Vector3(0.3, 0.9, 0.3)),
      position: Vector3(0.0, 0.9, 0.0),
    );
    // Mutation: return `_shape.boundsHalfExtents` from `halfExtents`. The
    // scale below grows the box the sweeps use.
    player.halfExtents.scale(10.0);
    // Mutation: return `_groundNormal` from `groundNormal`.
    player.groundNormal.setValues(1.0, 0.0, 0.0);
    expect(player.halfExtents, Vector3(0.3, 0.9, 0.3));
    expect(player.groundNormal, Vector3(0.0, 1.0, 0.0));
  });
}
