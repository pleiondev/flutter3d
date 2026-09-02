import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

/// Runs the world for [seconds], the way the game loop would.
void _run(MechanismWorld mechanisms, double seconds) {
  final steps = (seconds / _dt).round();
  for (var i = 0; i < steps; i++) {
    mechanisms.step(_dt);
    mechanisms.collisions.update();
    mechanisms.collisions.clearKinematicDeltas();
  }
}

({MechanismWorld mechanisms, CollisionWorld world}) _world() {
  final world = CollisionWorld();
  return (mechanisms: MechanismWorld(world), world: world);
}

Collider _box(CollisionWorld world, Vector3 at, Vector3 size) =>
    world.add(Collider(shape: CollisionBox(size / 2.0), position: at));

void main() {
  _removalTests();

  group('a door', () {
    test('starts closed and stays closed until asked', () {
      final w = _world();
      final door = w.mechanisms.add(
        Door(
          collider: _box(w.world, Vector3.zero(), Vector3(2.0, 3.0, 0.3)),
          travel: Vector3(0.0, 3.0, 0.0),
        ),
      );

      _run(w.mechanisms, 5.0);

      expect(door.state, MoverState.closed);
      expect(door.collider.position.y, closeTo(0.0, 1e-9));
    });

    test('opens, waits, and closes itself', () {
      final w = _world();
      final door = w.mechanisms.add(
        Door(
          collider: _box(w.world, Vector3.zero(), Vector3(2.0, 3.0, 0.3)),
          travel: Vector3(0.0, 3.0, 0.0),
          speed: 3.0,
          wait: 1.0,
        ),
      );

      expect(door.activate(const Activation()), isA<Activated>());

      _run(w.mechanisms, 0.5);
      expect(door.state, MoverState.opening);

      // Three metres at three metres a second.
      _run(w.mechanisms, 0.7);
      expect(door.state, MoverState.open);
      expect(door.collider.position.y, closeTo(3.0, 1e-6));

      _run(w.mechanisms, 1.1);
      expect(door.state, MoverState.closing);

      _run(w.mechanisms, 1.1);
      expect(door.state, MoverState.closed);
      expect(door.collider.position.y, closeTo(0.0, 1e-6));
    });

    test('a locked one refuses, and says what is missing', () {
      final w = _world();
      final door = w.mechanisms.add(
        Door(
          collider: _box(w.world, Vector3.zero(), Vector3(2.0, 3.0, 0.3)),
          travel: Vector3(0.0, 3.0, 0.0),
          key: 'blue',
        ),
      );

      final refused = door.activate(const Activation());
      expect(refused, isA<Refused>());
      expect(refused.message, contains('blue'));

      _run(w.mechanisms, 2.0);
      expect(door.state, MoverState.closed);

      expect(
        door.activate(const Activation(keys: <String>{'blue'})),
        isA<Activated>(),
      );
      _run(w.mechanisms, 3.0);
      expect(door.state, MoverState.open);
    });

    test('reopens rather than closing on somebody standing in it', () {
      // The failure this exists for is a door that kills the player through no
      // mistake of theirs.
      final w = _world();
      final door = w.mechanisms.add(
        Door(
          collider: _box(w.world, Vector3.zero(), Vector3(2.0, 3.0, 0.6)),
          travel: Vector3(0.0, 3.0, 0.0),
          speed: 3.0,
          wait: 0.5,
        ),
      );
      door.activate(const Activation());
      _run(w.mechanisms, 1.2);
      expect(door.state, MoverState.open);

      // Somebody steps into the opening while it is up.
      w.world.add(
        Collider(
          shape: CollisionCapsule(radius: 0.35, halfHeight: 0.55),
          position: Vector3(0.0, 0.9, 0.0),
          layer: CollisionLayers.player,
        ),
      );

      _run(w.mechanisms, 3.0);

      expect(door.state, isNot(MoverState.closed));
      expect(door.collider.position.y, greaterThan(1.0));
    });

    test('closes once they step out', () {
      final w = _world();
      final door = w.mechanisms.add(
        Door(
          collider: _box(w.world, Vector3.zero(), Vector3(2.0, 3.0, 0.6)),
          travel: Vector3(0.0, 3.0, 0.0),
          speed: 3.0,
          wait: 0.5,
        ),
      );
      door.activate(const Activation());
      _run(w.mechanisms, 1.2);

      // Into the opening only once it is up: a body standing where the closed
      // door is would have blocked it from opening at all, which is correct
      // and not what this test is about.
      final body = w.world.add(
        Collider(
          shape: CollisionCapsule(radius: 0.35, halfHeight: 0.55),
          position: Vector3(0.0, 0.9, 0.0),
          layer: CollisionLayers.player,
        ),
      );
      _run(w.mechanisms, 3.0);
      expect(door.state, isNot(MoverState.closed));

      body.moveTo(Vector3(0.0, 0.9, 4.0));
      _run(w.mechanisms, 4.0);

      expect(door.state, MoverState.closed);
    });

    test('a door with no wait stays open', () {
      final w = _world();
      final door = w.mechanisms.add(
        Door(
          collider: _box(w.world, Vector3.zero(), Vector3(2.0, 3.0, 0.3)),
          travel: Vector3(0.0, 3.0, 0.0),
          speed: 6.0,
          wait: 0.0,
        ),
      )..activate(const Activation());

      _run(w.mechanisms, 10.0);
      expect(door.state, MoverState.open);
    });
  });

  group('a lift', () {
    test('is a toggle rather than a request', () {
      final w = _world();
      final lift = w.mechanisms.add(
        Lift(
          collider: _box(w.world, Vector3.zero(), Vector3(3.0, 0.5, 3.0)),
          travel: Vector3(0.0, 4.0, 0.0),
          speed: 4.0,
          wait: 0.0,
        ),
      );

      lift.activate(const Activation());
      _run(w.mechanisms, 1.2);
      expect(lift.collider.position.y, closeTo(4.0, 1e-6));

      lift.activate(const Activation());
      _run(w.mechanisms, 1.2);
      expect(lift.collider.position.y, closeTo(0.0, 1e-6));
    });

    test('ignores a call made halfway', () {
      // A lift that changes its mind mid-travel drops its passenger.
      final w = _world();
      final lift = w.mechanisms.add(
        Lift(
          collider: _box(w.world, Vector3.zero(), Vector3(3.0, 0.5, 3.0)),
          travel: Vector3(0.0, 4.0, 0.0),
          speed: 2.0,
          wait: 0.0,
        ),
      );

      lift.activate(const Activation());
      _run(w.mechanisms, 1.0);
      final halfway = lift.collider.position.y;
      expect(halfway, greaterThan(0.5));
      expect(halfway, lessThan(3.5));

      expect(lift.activate(const Activation()), isA<NothingToDo>());
      _run(w.mechanisms, 2.0);
      expect(lift.collider.position.y, closeTo(4.0, 1e-6));
    });

    test('returns by itself after its wait', () {
      final w = _world();
      final lift = w.mechanisms.add(
        Lift(
          collider: _box(w.world, Vector3.zero(), Vector3(3.0, 0.5, 3.0)),
          travel: Vector3(0.0, 4.0, 0.0),
          speed: 4.0,
          wait: 1.0,
        ),
      )..activate(const Activation());

      _run(w.mechanisms, 1.2);
      expect(lift.collider.position.y, closeTo(4.0, 1e-6));

      _run(w.mechanisms, 2.4);
      expect(lift.collider.position.y, closeTo(0.0, 1e-6));
    });
  });

  group('a platform', () {
    test('runs on its own without anyone asking', () {
      final w = _world();
      final platform = w.mechanisms.add(
        MovingPlatform(
          collider: _box(w.world, Vector3.zero(), Vector3(2.0, 0.4, 2.0)),
          travel: Vector3(6.0, 0.0, 0.0),
          speed: 3.0,
          wait: 0.5,
        ),
      );

      _run(w.mechanisms, 2.1);
      expect(platform.collider.position.x, closeTo(6.0, 1e-6));

      _run(w.mechanisms, 2.7);
      expect(platform.collider.position.x, closeTo(0.0, 1e-6));
    });

    test('stalls rather than reversing when something is in the way', () {
      // A platform that turned back whenever a monster wandered under it would
      // never complete a circuit, and the level would stop working.
      final w = _world();
      final platform = w.mechanisms.add(
        MovingPlatform(
          collider: _box(w.world, Vector3.zero(), Vector3(2.0, 2.0, 2.0)),
          travel: Vector3(6.0, 0.0, 0.0),
          speed: 3.0,
          wait: 0.0,
        ),
      );
      w.world.add(
        Collider(
          shape: CollisionBox(Vector3.all(0.5)),
          position: Vector3(2.5, 0.0, 0.0),
          layer: CollisionLayers.actor,
        ),
      );

      _run(w.mechanisms, 4.0);

      expect(platform.collider.position.x, lessThan(1.1));
      expect(platform.goal, 1.0);
    });

    test('a phase offset staggers a row of them', () {
      final w = _world();
      MovingPlatform make(double phase) {
        final p = w.mechanisms.add(
          MovingPlatform(
            collider: _box(
              w.world,
              Vector3(0.0, 0.0, phase),
              Vector3(2.0, 0.4, 2.0),
            ),
            travel: Vector3(0.0, 4.0, 0.0),
            speed: 2.0,
            wait: 0.0,
          ),
        );
        return p..offsetBy(phase);
      }

      final first = make(0.0);
      final second = make(1.0);

      expect(second.progress, greaterThan(first.progress + 0.3));
      // And the offset is not left as motion for a passenger to be dragged by.
      expect(second.collider.delta.length, 0.0);
    });
  });

  group('resetting', () {
    test('puts a mover back where it was authored', () {
      final w = _world();
      final door = w.mechanisms.add(
        Door(
          collider: _box(w.world, Vector3(1.0, 2.0, 3.0), Vector3.all(1.0)),
          travel: Vector3(0.0, 3.0, 0.0),
          speed: 9.0,
          wait: 0.0,
        ),
      )..activate(const Activation());
      _run(w.mechanisms, 1.0);
      expect(door.state, MoverState.open);

      door.reset();

      expect(door.state, MoverState.closed);
      expect(door.collider.position, Vector3(1.0, 2.0, 3.0));
    });
  });
}

/// Removing a collider renumbers the grid that indexes it.
///
/// This is the bug that killed the game loop: a collected pickup removed
/// itself, and the next query — an occlusion raycast in the same step — walked
/// a grid still holding indices into the longer list and read past its end.
/// The exception fired every frame, which took the input with it.
void _removalTests() {
  group('removing a collider', () {
    test('leaves the broadphase safe to query at once', () {
      final world = CollisionWorld();
      final movers = <Collider>[
        for (var i = 0; i < 12; i++)
          world.add(
            Collider(
              shape: CollisionBox(Vector3.all(0.5)),
              position: Vector3(i.toDouble(), 0.0, 0.0),
              kind: ColliderKind.kinematic,
            ),
          ),
      ];
      world.update();

      // The first one, so every remaining index shifts.
      world.remove(movers.first);

      final hit = RayHit();
      expect(
        () => world.raycast(
          Vector3(-5.0, 0.0, 0.0),
          Vector3(1.0, 0.0, 0.0),
          40.0,
          hit,
        ),
        returnsNormally,
      );
    });

    test('and the same for an overlap query', () {
      final world = CollisionWorld();
      final movers = <Collider>[
        for (var i = 0; i < 12; i++)
          world.add(
            Collider(
              shape: CollisionBox(Vector3.all(0.5)),
              position: Vector3(i.toDouble(), 0.0, 0.0),
              kind: ColliderKind.trigger,
            ),
          ),
      ];
      world.update();
      world.remove(movers[3]);

      final found = <Collider>[];
      expect(
        () => world.overlap(
          CollisionBox(Vector3.all(20.0)),
          Vector3.zero(),
          found,
        ),
        returnsNormally,
      );
      expect(found, isNot(contains(movers[3])));
    });

    test('a pickup collecting itself does not break the next query', () {
      // The shape of the real failure, end to end: removal is deferred out of
      // the collision callback, drained inside update(), and something queries
      // afterwards in the same step.
      final world = CollisionWorld();
      for (var i = 0; i < 8; i++) {
        world.add(
          Collider(
            shape: CollisionBox(Vector3.all(0.4)),
            position: Vector3(i.toDouble(), 0.0, 4.0),
            kind: ColliderKind.trigger,
          ),
        );
      }
      final collected = world.add(
        Collider(
          shape: CollisionBox(Vector3.all(0.4)),
          position: Vector3.zero(),
          kind: ColliderKind.trigger,
        ),
      );
      world.update();

      world.removeLater(collected);
      world.update();

      final hit = RayHit();
      expect(
        () => world.raycast(
          Vector3(0.0, 0.0, -8.0),
          Vector3(0.0, 0.0, 1.0),
          30.0,
          hit,
          includeTriggers: true,
        ),
        returnsNormally,
      );
    });
  });
}
