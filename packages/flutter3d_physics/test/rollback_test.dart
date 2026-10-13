// A rollback steps to the bits the run it rewound took: a save, a step, a
// restore and the same step again end where the first step did, through the
// first contact and the contacts that persist after it.
import 'dart:typed_data';

import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const double dt = 1.0 / 60.0;

/// An oak ball dropped on a granite floor, the scene that drifted.
({Dynamics dynamics, RigidBody ball}) oakOnGranite() {
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
    position: Vector3(0.25, 0.6, 0.0),
    material: Materials.oak,
  );
  return (dynamics: Dynamics(world: world)..add(ball), ball: ball);
}

/// The ball's state as bits, so a difference in the last one shows. Read as
/// 32-bit halves: the browser has no Uint64List, and two halves hold every
/// bit of a double just the same.
List<int> bitsOf(RigidBody ball) => Float64List.fromList(<double>[
  ...ball.position.storage,
  ...ball.velocity.storage,
]).buffer.asUint32List().toList();

void main() {
  test('every step taken twice from one save ends in the same bits, '
      'through the first contact and the rest that follows it', () {
    final scene = oakOnGranite();
    final dynamics = scene.dynamics, ball = scene.ball;
    for (var step = 0; step < 60; step++) {
      final savedBall = ball.save();
      final savedWorld = dynamics.saveState();
      dynamics.step(dt);
      final first = bitsOf(ball);
      final contacts = dynamics.contacts.map((c) => c.impulse).toList();

      ball.restore(savedBall);
      dynamics.restoreState(savedWorld);
      dynamics.step(dt);
      // Mutation: leave the warm starts out of the save, and the step that
      // begins the contact (15 here) is the first whose bits differ, because
      // the second try starts its solver from the first try's impulse.
      expect(bitsOf(ball), first, reason: 'step $step');
      expect(
        dynamics.contacts.map((c) => c.impulse).toList(),
        contacts,
        reason: 'step $step',
      );
    }
    expect(dynamics.contacts, isNotEmpty);
  });

  test('a run rewound to a save in contact goes on as the run it was saved '
      'from', () {
    final straight = oakOnGranite();
    final rewound = oakOnGranite();
    for (var step = 0; step < 20; step++) {
      straight.dynamics.step(dt);
      rewound.dynamics.step(dt);
    }
    expect(straight.dynamics.contacts, isNotEmpty);
    // Saved in contact, carried on, then put back: what it carried on to is
    // forgotten, and what it was saved with is not.
    final savedBall = rewound.ball.save();
    final savedWorld = rewound.dynamics.saveState();
    for (var step = 0; step < 7; step++) {
      rewound.dynamics.step(dt);
    }
    rewound.ball.restore(savedBall);
    rewound.dynamics.restoreState(savedWorld);
    for (var step = 0; step < 40; step++) {
      straight.dynamics.step(dt);
      rewound.dynamics.step(dt);
      expect(bitsOf(rewound.ball), bitsOf(straight.ball), reason: 'step $step');
    }
  });
}
