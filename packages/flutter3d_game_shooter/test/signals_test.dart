import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

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

Collider _volume(CollisionWorld world, Vector3 at, [double size = 2.0]) =>
    world.add(
      Collider(
        shape: CollisionBox(Vector3.all(size / 2.0)),
        position: at,
        kind: ColliderKind.trigger,
        layer: CollisionLayers.trigger,
        mask: CollisionLayers.player,
      ),
    );

/// A body that can walk about and carry things.
///
/// **A real `Player`, and that is the whole point of this helper.** It used to
/// put an `Inventory` straight into `userData`, which is the arrangement the
/// game had before a collider started answering *who* it is rather than what it
/// holds. These tests went on passing against the old shape while every pickup
/// in the running game silently stopped working. A harness that does not build
/// what the game builds is a harness that tests itself.
Collider _player(CollisionWorld world, Vector3 at, {Inventory? carrying}) {
  final player = Player(
    body: CharacterController(world: world, position: at),
    inventory: carrying,
  );
  return player.body.collider;
}

Door _door(
  ({MechanismWorld mechanisms, CollisionWorld world}) w,
  String name, {
  String? key,
}) => w.mechanisms.add(
  Door(
    name: name,
    collider: w.world.add(
      Collider(
        shape: CollisionBox(Vector3(1.0, 1.5, 0.15)),
        position: Vector3(0.0, 0.0, -20.0),
      ),
    ),
    travel: Vector3(0.0, 3.0, 0.0),
    speed: 9.0,
    wait: 0.0,
    key: key,
  ),
);

/// A blue key lying at [at].
Pickup _key(
  ({MechanismWorld mechanisms, CollisionWorld world}) w,
  Vector3 at,
) => Pickup(
  gift: const KeyGift(),
  amount: 1.0,
  detail: 'blue',
  collider: _volume(w.world, at, 0.6),
);

void main() {
  _eventTests();

  group('a button', () {
    test('fires what it points at', () {
      final w = _world();
      final door = _door(w, 'gate');
      final button = w.mechanisms.add(
        Button(
          target: 'gate',
          collider: _volume(w.world, Vector3(3.0, 1.0, 0.0)),
        ),
      );

      expect(button.activate(const Activation()), isA<Activated>());
      _run(w.mechanisms, 1.0);
      expect(door.state, MoverState.open);
    });

    test('a locked one refuses and does not fire', () {
      final w = _world();
      final door = _door(w, 'gate');
      final button = w.mechanisms.add(
        Button(
          target: 'gate',
          collider: _volume(w.world, Vector3(3.0, 1.0, 0.0)),
          key: 'red',
        ),
      );

      expect(button.activate(const Activation()), isA<Refused>());
      _run(w.mechanisms, 1.0);
      expect(door.state, MoverState.closed);
    });

    test('a one-shot button spends itself, but only on success', () {
      final w = _world();
      _door(w, 'gate', key: 'blue');
      final button = w.mechanisms.add(
        Button(
          target: 'gate',
          collider: _volume(w.world, Vector3(3.0, 1.0, 0.0)),
          once: true,
        ),
      );

      // The door behind it refuses, so the player has not used up their turn.
      expect(button.activate(const Activation()), isA<Refused>());
      expect(button.isSpent, isFalse);

      expect(
        button.activate(const Activation(keys: <String>{'blue'})),
        isA<Activated>(),
      );
      expect(button.isSpent, isTrue);
      expect(button.activate(const Activation()), isA<NothingToDo>());
    });

    test('pointing at nothing is quiet rather than fatal', () {
      final w = _world();
      final button = w.mechanisms.add(
        Button(
          target: 'a lift that was deleted',
          collider: _volume(w.world, Vector3.zero()),
        ),
      );

      expect(button.activate(const Activation()), isA<NothingToDo>());
    });
  });

  group('a trigger volume', () {
    test('fires when a body walks into it', () {
      final w = _world();
      final door = _door(w, 'gate');
      w.mechanisms.add(
        TriggerVolume(
          target: 'gate',
          collider: _volume(w.world, Vector3(0.0, 1.0, 0.0), 3.0),
        ),
      );

      final player = _player(w.world, Vector3(0.0, 1.0, 8.0));
      _run(w.mechanisms, 0.2);
      expect(door.state, MoverState.closed);

      player.moveTo(Vector3(0.0, 1.0, 0.0));
      _run(w.mechanisms, 1.0);

      expect(door.state, MoverState.open);
    });

    test('ignores a monster unless the level says otherwise', () {
      final w = _world();
      final door = _door(w, 'gate');
      w.mechanisms.add(
        TriggerVolume(
          target: 'gate',
          collider: _volume(w.world, Vector3(0.0, 1.0, 0.0), 3.0),
        ),
      );

      w.world.add(
        Collider(
          shape: CollisionCapsule(radius: 0.35, halfHeight: 0.55),
          position: Vector3(0.0, 1.0, 0.0),
          layer: CollisionLayers.actor,
        ),
      );
      _run(w.mechanisms, 1.0);

      expect(door.state, MoverState.closed);
    });

    test('carries the walker keys through to what it fires', () {
      // A trigger in front of a locked door has to open it for a player who
      // has the key and refuse one who does not, and it never sees the door.
      final w = _world();
      final door = _door(w, 'gate', key: 'blue');
      final trigger = w.mechanisms.add(
        TriggerVolume(
          target: 'gate',
          collider: _volume(w.world, Vector3(0.0, 1.0, 0.0), 3.0),
          once: false,
        ),
      );

      final empty = _player(
        w.world,
        Vector3(0.0, 1.0, 0.0),
        carrying: Inventory(),
      );
      _run(w.mechanisms, 0.5);
      expect(door.state, MoverState.closed);
      expect(trigger.takeOutcome(), isA<Refused>());

      w.world.remove(empty);
      final carrying = Inventory()..keyRing.take('blue');
      _player(w.world, Vector3(0.0, 1.0, 0.0), carrying: carrying);
      _run(w.mechanisms, 1.0);

      expect(door.state, MoverState.open);
    });

    test('an outcome is reported once, not for as long as you stand there', () {
      final w = _world();
      _door(w, 'gate');
      final trigger = w.mechanisms.add(
        TriggerVolume(
          target: 'gate',
          collider: _volume(w.world, Vector3(0.0, 1.0, 0.0), 3.0),
        ),
      );

      _player(w.world, Vector3(0.0, 1.0, 0.0));
      _run(w.mechanisms, 0.2);

      expect(trigger.takeOutcome(), isA<Activated>());
      _run(w.mechanisms, 0.5);
      expect(trigger.takeOutcome(), isNull);
    });

    test('by default it arms once, because a trap should not rearm', () {
      final w = _world();
      final door = _door(w, 'gate');
      final trigger = w.mechanisms.add(
        TriggerVolume(
          target: 'gate',
          collider: _volume(w.world, Vector3(0.0, 1.0, 0.0), 3.0),
          once: true,
        ),
      );

      final player = _player(w.world, Vector3(0.0, 1.0, 0.0));
      _run(w.mechanisms, 1.0);
      expect(door.state, MoverState.open);
      expect(trigger.isSpent, isTrue);

      // Shut it by hand and walk through again.
      door.reset();
      player.moveTo(Vector3(0.0, 1.0, 8.0));
      _run(w.mechanisms, 0.2);
      player.moveTo(Vector3(0.0, 1.0, 0.0));
      _run(w.mechanisms, 1.0);

      expect(door.state, MoverState.closed);
    });
  });

  group('a key', () {
    test('is picked up by walking over it, once', () {
      final w = _world();
      final carrying = Inventory();
      final key = w.mechanisms.add(_key(w, Vector3(0.0, 0.5, 0.0)));

      final player = _player(
        w.world,
        Vector3(0.0, 0.9, 4.0),
        carrying: carrying,
      );
      _run(w.mechanisms, 0.2);
      expect(carrying.keyRing.has('blue'), isFalse);

      player.moveTo(Vector3(0.0, 0.9, 0.0));
      _run(w.mechanisms, 0.1);

      expect(carrying.keyRing.has('blue'), isTrue);
      expect(key.isTaken, isTrue);
    });

    test('and stops being in the world once it is taken', () {
      final w = _world();
      final carrying = Inventory();
      final key = w.mechanisms.add(_key(w, Vector3(0.0, 0.9, 0.0)));
      _player(w.world, Vector3(0.0, 0.9, 0.0), carrying: carrying);
      _run(w.mechanisms, 0.2);
      expect(key.isTaken, isTrue);

      final found = <Collider>[];
      w.world.overlap(
        CollisionBox(Vector3.all(2.0)),
        Vector3(0.0, 0.9, 0.0),
        found,
      );
      expect(found, isNot(contains(key.collider)));
    });

    test('opens the door it was made for', () {
      // The whole point, end to end: the key on the floor, the ring in the
      // player's pocket, and the lock that reads it.
      final w = _world();
      final carrying = Inventory();
      final door = _door(w, 'gate', key: 'blue');
      w.mechanisms.add(_key(w, Vector3(0.0, 0.9, 0.0)));
      final player = _player(
        w.world,
        Vector3(0.0, 0.9, 6.0),
        carrying: carrying,
      );

      expect(door.activate(w.mechanisms.activationBy(player)), isA<Refused>());

      player.moveTo(Vector3(0.0, 0.9, 0.0));
      _run(w.mechanisms, 0.2);

      expect(
        door.activate(w.mechanisms.activationBy(player)),
        isA<Activated>(),
      );
    });
  });

  group('looking at things', () {
    // Every one of these steps the world once first: the grid of everything
    // that moves is rebuilt by update(), and a collider added since the last
    // one is not in it yet.
    test('the crosshair finds the button in front of it', () {
      final w = _world();
      final button = w.mechanisms.add(
        Button(
          target: 'gate',
          collider: _volume(w.world, Vector3(0.0, 1.6, -2.0), 1.0),
        ),
      );

      _run(w.mechanisms, 0.02);

      expect(
        w.mechanisms.underCrosshair(
          Vector3(0.0, 1.6, 0.0),
          Vector3(0.0, 0.0, -1.0),
        ),
        same(button),
      );
    });

    test('and not one across the room', () {
      final w = _world();
      w.mechanisms.add(
        Button(
          target: 'gate',
          collider: _volume(w.world, Vector3(0.0, 1.6, -9.0), 1.0),
        ),
      );

      _run(w.mechanisms, 0.02);

      expect(
        w.mechanisms.underCrosshair(
          Vector3(0.0, 1.6, 0.0),
          Vector3(0.0, 0.0, -1.0),
        ),
        isNull,
      );
    });

    test('or one behind a wall', () {
      final w = _world();
      w.mechanisms.add(
        Button(
          target: 'gate',
          collider: _volume(w.world, Vector3(0.0, 1.6, -2.0), 1.0),
        ),
      );
      w.world.add(
        Collider(
          shape: CollisionBox(Vector3(2.0, 2.0, 0.1)),
          position: Vector3(0.0, 1.6, -1.0),
        ),
      );

      _run(w.mechanisms, 0.02);

      expect(
        w.mechanisms.underCrosshair(
          Vector3(0.0, 1.6, 0.0),
          Vector3(0.0, 0.0, -1.0),
        ),
        isNull,
      );
    });
  });
}

/// What the level's machinery reports about itself.
///
/// Replaces a walk the application used to do by hand over every mechanism in
/// the level, type-testing as it went and diffing `Mover.isMoving` against a
/// map of sounds. The comment there said "a mover has no events"; it has now,
/// and each mechanism reports its own rather than being interrogated.
Collider _eventBox(CollisionWorld world) => world.add(
  Collider(
    shape: CollisionBox(Vector3(2.0, 3.0, 0.3)),
    position: Vector3(4.0, 1.0, 0.0),
    kind: ColliderKind.kinematic,
  ),
);

/// A mechanism that is nowhere, which the base class allows.
final class _Placeless extends Mechanism {
  @override
  ActivationOutcome activate(Activation by) => const NothingToDo();

  /// Nothing: a test fixture that exists to have no place.
  @override
  Map<String, Object?> save() => const <String, Object?>{};

  @override
  void restore(Map<String, Object?> from) {}
}

void _eventTests() {
  group('published events', () {
    test(
      'a door started by a button is reported in that step, not the next',
      () {
        // The reason `publish()` is not called from `step()`. A button pressed
        // with the use key is activated *after* mechanisms have stepped, so the
        // door it starts is not yet moving when `step` returns.
        //
        // Mutation: call `publish()` at the end of `MechanismWorld.step`. The
        // door then appears one step late and this fails.
        final world = CollisionWorld();
        final mechanisms = MechanismWorld(world);
        final door = Door(
          name: 'door',
          collider: _eventBox(world),
          travel: Vector3(0, 3, 0),
          speed: 2.0,
        );
        mechanisms.add(door);

        mechanisms.step(1 / 60);
        mechanisms.publish();
        expect(mechanisms.events.started, isEmpty);

        // The use key, after the step — which is where the application puts it.
        door.activate(const Activation());
        mechanisms.publish();

        expect(mechanisms.events.started, <Mechanism>[door]);
      },
    );

    test('a mover that keeps going is reported once, not every step', () {
      final world = CollisionWorld();
      final mechanisms = MechanismWorld(world);
      final door = Door(
        name: 'door',
        collider: _eventBox(world),
        travel: Vector3(0, 3, 0),
        speed: 1.0,
      );
      mechanisms.add(door);
      door.activate(const Activation());

      var starts = 0;
      for (var i = 0; i < 30; i++) {
        mechanisms.step(1 / 60);
        mechanisms.publish();
        starts += mechanisms.events.started.length;
      }

      expect(starts, 1, reason: 'a grinding sound restarted every step');
      expect(mechanisms.events.stopped, isEmpty, reason: 'still travelling');
    });

    test('and reported stopped exactly once when it arrives', () {
      final world = CollisionWorld();
      final mechanisms = MechanismWorld(world);
      final door = Door(
        name: 'door',
        collider: _eventBox(world),
        travel: Vector3(0, 1, 0),
        speed: 4.0,
      );
      mechanisms.add(door);
      door.activate(const Activation());

      var stops = 0;
      for (var i = 0; i < 120; i++) {
        mechanisms.step(1 / 60);
        mechanisms.publish();
        stops += mechanisms.events.stopped.length;
      }

      expect(stops, 1);
    });

    test('a mechanism with no place reports none', () {
      // `origin` is nullable because a mechanism need not be anywhere: a relay
      // wired between two others is in the level file and nowhere in the world.
      // The base class answers null, and a caller placing a sound has to cope.
      expect(_Placeless().origin, isNull);
    });
  });
}
