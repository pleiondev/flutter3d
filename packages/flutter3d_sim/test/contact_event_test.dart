/// The contact event: a step's contacts on the bus, digested on the tape
/// and carried to a view as plain values, as `ActorHurt` is.
///
///     dart test test/contact_event_test.dart
library;

import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A loop whose rules phase steps a ball dropped from [height] onto a
/// granite floor and publishes what it touched.
EngineLoop _dropping(double height) {
  final world = CollisionWorld()
    ..add(
      Collider(
        shape: CollisionBox(Vector3(10.0, 0.5, 10.0)),
        position: Vector3(0.0, -0.5, 0.0),
        material: Materials.granite,
      ),
    );
  final dynamics = Dynamics(world: world)
    ..add(
      RigidBody(
        world: world,
        shape: CollisionSphere(0.25),
        position: Vector3(0.0, height, 0.0),
        material: Materials.oak,
      ),
    );
  final loop = EngineLoop(input: InputState());
  declareSimulationEvents(loop.events);
  return loop..addSystem('drop', LoopPhase.rules, (c) {
    dynamics.step(c.dt);
    ContactEvent.publishAll(dynamics.contacts, c.publish);
  });
}

ContactEvent _event({ContactPhase phase = ContactPhase.begin}) => ContactEvent(
  bodyA: 0,
  bodyB: 3,
  feature: 1,
  materialA: 'granite',
  materialB: 'acme.cheese',
  phase: phase,
  point: Vector3(1.0, 2.0, 3.0),
  normal: Vector3(0.0, -1.0, 0.0),
  impulse: 0.25,
  relativeVelocity: Vector3(0.5, 3.75, -0.125),
);

void main() {
  test('its codec reads back every field, and refuses a phase it cannot '
      'name', () {
    final codec = ContactEvent.codec;
    final back = codec.decode(codec.encode(_event()), codec.version)!;
    expect(
      <Object?>[
        back.bodyA,
        back.bodyB,
        back.feature,
        back.materialA,
        back.materialB,
        back.phase,
        back.point,
        back.normal,
        back.impulse,
        back.relativeVelocity,
      ],
      <Object?>[
        0,
        3,
        1,
        'granite',
        'acme.cheese',
        ContactPhase.begin,
        Vector3(1.0, 2.0, 3.0),
        Vector3(0.0, -1.0, 0.0),
        0.25,
        Vector3(0.5, 3.75, -0.125),
      ],
    );
    // A later build's phase is not one this build hands on as another.
    final later = List<Object?>.of(codec.encode(_event())! as List<Object?>);
    later[5] = 'slide';
    expect(codec.decode(later, codec.version), isNull);
    expect(codec.decode('not a contact', 1), isNull);
  });

  test('a genre shares it: declared on the engine with its codec', () {
    final loop = EngineLoop(input: InputState());
    declareSimulationEvents(loop.events);
    final declaration = loop.events.declared.singleWhere(
      (d) => d.name == ContactEvent.eventName,
    );
    expect(declaration.declaredBy, 'app');
    expect(declaration.codec, same(ContactEvent.codec));
  });

  test('a dropped ball begins one contact on the bus, naming the bodies and '
      'their materials, and then persists', () {
    final loop = _dropping(1.0);
    final heard = <ContactEvent>[];
    loop.events.onStep<ContactEvent>('test', (d) => heard.add(d.event));
    loop.runSteps(60);
    final begun = heard.where((e) => e.phase == ContactPhase.begin).toList();
    expect(begun, hasLength(1));
    expect(begun.single.materialA, Materials.granite.id);
    expect(begun.single.materialB, Materials.oak.id);
    expect(begun.single.relativeVelocity.y, greaterThan(3.0));
    expect(heard.last.phase, ContactPhase.persist);
  });

  test('it is on the tape: two runs digest alike, and a ball dropped from '
      'elsewhere diverges at the step it lands', () {
    // Mutation: declare it without its codec, or publish none — the event
    // trace of the two drops agrees and a replay cannot tell them apart.
    EventTrace traced(double height) {
      final loop = _dropping(height);
      final trace = EventTrace();
      loop
        ..onStepEnd(
          (s) => trace.observe(s.step, count: s.count, digest: s.digest),
        )
        ..runSteps(40);
      return trace;
    }

    final once = traced(1.0);
    expect(once.isEmpty, isFalse);
    expect(traced(1.0).divergenceFrom(once), isNull);
    final other = traced(0.6).divergenceFrom(once);
    expect(other, isNotNull);
    expect(other!.step, lessThan(once.steps.first + 1));
  });

  test('the step where a game runs its bodies raises what they touched', () {
    // Mutation: step the dynamics in `WorldStep.index` and raise nothing,
    // and no genre's bus hears a contact.
    final world = CollisionWorld()
      ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(20.0, 1.0, 20.0));
    final dynamics = Dynamics(world: world)
      ..add(
        RigidBody(
          world: world,
          shape: CollisionSphere(0.25),
          position: Vector3(0.0, 0.252, 0.0),
        ),
      );
    final raised = <GameEvent>[];
    final step = WorldStep(
      collision: world,
      dynamics: dynamics,
      raise: raised.add,
    );
    for (var i = 0; i < 3; i++) {
      step
        ..movers(1 / 60)
        ..index(1 / 60)
        ..settle()
        ..publish();
    }
    final contacts = raised.whereType<ContactEvent>().toList();
    expect(contacts.map((e) => e.phase), <ContactPhase>[
      ContactPhase.begin,
      ContactPhase.persist,
      ContactPhase.persist,
    ]);
    final last = dynamics.contacts.single;
    expect(contacts.last.bodyA, last.idA);
    expect(contacts.last.bodyB, last.idB);
    expect(contacts.last.point, last.point);
  });

  test('it crosses to a view encoded, and reads back as the same event', () {
    // Mutation: an event published with no codec — the view gets its name
    // and nothing it can read.
    final loop = _dropping(0.252);
    // A view reading it is what turns publishing on.
    expect(loop.published.events, isEmpty);
    loop.runSteps(1);
    final wire = PublishedState.fromWire(loop.published.toWire());
    final events = <ContactEvent>[
      for (final event in wire.eventsNamed(ContactEvent.eventName))
        ?event.decode(ContactEvent.codec),
    ];
    expect(events, hasLength(1));
    expect(events.single.phase, ContactPhase.begin);
    expect(events.single.materialB, Materials.oak.id);
    expect(events.single.normal.y, closeTo(-1.0, 1e-12));
  });
}
