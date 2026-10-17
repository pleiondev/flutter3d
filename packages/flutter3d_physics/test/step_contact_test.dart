// A step's contacts on the reference: what began, persisted and ended, in
// the world's order, with the impulse and the velocity a game reads.
import 'dart:convert';

import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const double dt = 1.0 / 60.0;

CollisionWorld floored() =>
    CollisionWorld()..addBox(Vector3(0.0, -0.5, 0.0), Vector3(20.0, 1.0, 20.0));

RigidBody ball(Dynamics dynamics, Vector3 at, {double radius = 0.25}) =>
    dynamics.add(
      RigidBody(
        world: dynamics.world,
        shape: CollisionSphere(radius),
        position: at,
      ),
    );

void main() {
  test('a phase is open, named on the wire, and read back by name', () {
    expect(ContactPhase.values.map((p) => p.name), <String>[
      'begin',
      'persist',
      'end',
    ]);
    expect(ContactPhase.byName('persist'), ContactPhase.persist);
    expect(ContactPhase.byName('slide'), isNull);
    expect('${ContactPhase.end}', 'ContactPhase.end');
  });

  test('a contact is said from the collider the world numbered first', () {
    final world = CollisionWorld();
    final first = world.addBox(Vector3.zero(), Vector3.all(1.0));
    final second = world.addBox(Vector3(0.0, 1.0, 0.0), Vector3.all(1.0));
    final contact = StepContact(
      a: second,
      b: first,
      idA: world.idOf(second)!,
      idB: world.idOf(first)!,
      phase: ContactPhase.begin,
      point: Vector3(0.0, 0.5, 0.0),
      normal: Vector3(0.0, 1.0, 0.0),
      impulse: 2.0,
      relativeVelocity: Vector3(0.0, -3.0, 0.0),
    );
    // Mutation: keep the order given, and two backends that found the pair
    // the other way round report two different contacts.
    expect(contact.a, same(first));
    expect(contact.normal, Vector3(0.0, -1.0, 0.0));
    expect(contact.relativeVelocity, Vector3(0.0, 3.0, 0.0));
    expect(contact.impulse, 2.0);
  });

  test('an id a contact names leads back to the collider and the body, '
      'and to nothing once it is gone', () {
    // Mutation: drop the reverse map, or leave a removed collider in it,
    // and a game cannot get from a contact event to the actor it hit.
    final world = floored();
    final dynamics = Dynamics(world: world);
    final body = ball(dynamics, Vector3(0.0, 0.3, 0.0));
    for (var i = 0; i < 60 && dynamics.contacts.isEmpty; i++) {
      dynamics.step(dt);
    }
    final contact = dynamics.contacts.first;
    expect(world.colliderOf(contact.idA), same(contact.a));
    expect(world.colliderOf(contact.idB), same(body.collider));
    expect(dynamics.bodyOfId(contact.idB), same(body));
    // The floor is level geometry: a collider, and no body.
    expect(dynamics.bodyOfId(contact.idA), isNull);
    expect(world.colliderOf(9999), isNull);
    final id = world.idOf(body.collider)!;
    dynamics.remove(body);
    expect(world.colliderOf(id), isNull);
    expect(dynamics.bodyOfId(id), isNull);
    world.clear();
    expect(world.colliderOf(contact.idA), isNull);
  });

  test('a ball dropped on the floor begins once, at the speed it fell at, '
      'and then rests on it', () {
    final world = floored();
    final dynamics = Dynamics(world: world);
    final body = ball(dynamics, Vector3(0.0, 1.0, 0.0));
    final phases = <ContactPhase>[];
    StepContact? begun;
    for (var i = 0; i < 90; i++) {
      dynamics.step(dt);
      for (final contact in dynamics.contacts) {
        phases.add(contact.phase);
        if (contact.phase == ContactPhase.begin) begun = contact;
      }
    }
    expect(phases.where((p) => p == ContactPhase.begin), hasLength(1));
    expect(phases.where((p) => p == ContactPhase.end), isEmpty);
    // The floor was added first: it is a, the ball b, the normal down out of
    // the ball, and the floor's point meets the falling ball upwards.
    expect(begun!.b, same(body.collider));
    expect(begun.normal.y, closeTo(-1.0, 1e-9));
    expect(begun.relativeVelocity.y, inInclusiveRange(3.0, 4.2));
    expect(begun.impulse, greaterThan(0.0));
    // Caught by the speculative contact up to a step's fall short of the
    // floor, so halfway across that gap at most: under four centimetres at
    // the speed it fell at.
    expect(begun.point.y, inInclusiveRange(-0.005, 0.04));
    // At rest, the floor holds the ball's weight over the step — or nothing,
    // asleep, the pair held as it was.
    final last = dynamics.contacts.single;
    expect(last.phase, ContactPhase.persist);
    if (body.isAsleep) {
      expect(last.impulse, 0.0);
    } else {
      expect(last.impulse, closeTo(9.81 * dt, 0.02));
    }
  });

  test('a sleeping pile persists, and a body taken out ends its contacts', () {
    final world = floored();
    final dynamics = Dynamics(world: world);
    final lower = dynamics.add(
      RigidBody(
        world: world,
        shape: CollisionBox(Vector3.all(0.5)),
        position: Vector3(0.0, 0.5, 0.0),
      ),
    );
    final upper = dynamics.add(
      RigidBody(
        world: world,
        shape: CollisionBox(Vector3.all(0.5)),
        position: Vector3(0.0, 1.5, 0.0),
      ),
    );
    for (var i = 0; i < 240; i++) {
      dynamics.step(dt);
    }
    expect(lower.isAsleep && upper.isAsleep, isTrue);
    dynamics.step(dt);
    // Mutation: drop a sleeper's pairs, and a resting pile ends its contacts
    // the moment it falls asleep.
    expect(dynamics.contacts.map((c) => c.phase), <ContactPhase>[
      ContactPhase.persist,
      ContactPhase.persist,
    ]);
    // In the world's order: floor–lower, then lower–upper.
    expect(dynamics.contacts.first.b, same(lower.collider));
    expect(dynamics.contacts.last.a, same(lower.collider));
    expect(dynamics.contacts.last.b, same(upper.collider));
    // A shared face, under the upper crate's middle.
    expect(dynamics.contacts.last.point.x, closeTo(0.0, 1e-9));
    expect(dynamics.contacts.last.point.y, closeTo(1.0, 0.01));

    dynamics.remove(upper);
    dynamics.step(dt);
    final ended = dynamics.contacts.where((c) => c.phase == ContactPhase.end);
    expect(ended.single.b, same(upper.collider));
    expect(ended.single.impulse, 0.0);
    dynamics.step(dt);
    expect(dynamics.contacts.single.b, same(lower.collider));
  });

  test('a contact names the materials the colliders are made of', () {
    final world = CollisionWorld()
      ..add(
        Collider(
          shape: CollisionBox(Vector3(10.0, 0.5, 10.0)),
          position: Vector3(0.0, -0.5, 0.0),
          material: Materials.granite,
        ),
      );
    final dynamics = Dynamics(world: world);
    dynamics.add(
      RigidBody(
        world: world,
        shape: CollisionSphere(0.25),
        position: Vector3(0.0, 0.252, 0.0),
        material: Materials.oak,
      ),
    );
    dynamics.step(dt);
    final contact = dynamics.contacts.single;
    expect(contact.materialA, Materials.granite.id);
    expect(contact.materialB, Materials.oak.id);
  });

  test(
    'a save keeps the step before: a restored run tells the same phases',
    () {
      final world = floored();
      final dynamics = Dynamics(world: world);
      final body = ball(dynamics, Vector3(0.0, 0.252, 0.0));
      dynamics
        ..step(dt)
        ..step(dt);
      expect(dynamics.contacts.single.phase, ContactPhase.persist);
      final saved = dynamics.saveState();
      final at = body.save();
      // Through JSON, as a save goes to disk.
      final written = jsonDecode(jsonEncode(saved));
      dynamics.step(dt);
      final first = dynamics.contacts.single;
      body.restore(at);
      // Mutation: forget the ledger on a restore, and this begins.
      dynamics
        ..restoreState(written)
        ..step(dt);
      final again = dynamics.contacts.single;
      expect(again.phase, ContactPhase.persist);
      expect(again.phase, first.phase);
      expect(again.point, first.point);
      // A save from before contacts were saved begins every contact.
      body.restore(at);
      dynamics
        ..restoreState(<String, Object?>{'world': world.properties.toJson()})
        ..step(dt);
      expect(dynamics.contacts.single.phase, ContactPhase.begin);
    },
  );

  test('a contact that ends after a restore ends where the save had it', () {
    final world = floored();
    final dynamics = Dynamics(world: world);
    final body = ball(dynamics, Vector3(0.0, 0.252, 0.0));
    for (var i = 0; i < 5; i++) {
      dynamics.step(dt);
    }
    final rested = dynamics.contacts.single;
    final saved = jsonDecode(jsonEncode(dynamics.saveState()));
    final at = body.save();
    dynamics.step(dt);
    body.restore(at);
    dynamics
      ..restoreState(saved)
      ..remove(body)
      ..step(dt);
    final ended = dynamics.contacts.single;
    expect(ended.phase, ContactPhase.end);
    expect(ended.point, rested.point);
    expect(ended.normal, rested.normal);
  });

  test('a contact is a value: what reads it does not change it', () {
    final world = floored();
    final dynamics = Dynamics(world: world);
    ball(dynamics, Vector3(0.0, 0.252, 0.0));
    dynamics.step(dt);
    final contact = dynamics.contacts.single;
    final point = contact.point.clone();
    // Mutation: hand out the vector it holds, and this moves the contact.
    contact.point.add(Vector3.all(1.0));
    contact.normal.scale(-1.0);
    expect(contact.point, point);
    expect(contact.normal.y, closeTo(-1.0, 1e-12));
  });
}
