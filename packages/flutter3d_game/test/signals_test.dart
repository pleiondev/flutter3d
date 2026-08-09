import 'package:flutter3d_game/flutter3d_game.dart';
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

/// A body that can walk about and carry keys.
Collider _player(CollisionWorld world, Vector3 at, {KeyRing? keys}) => world.add(
      Collider(
        shape: CollisionCapsule(radius: 0.35, halfHeight: 0.55),
        position: at,
        // Kinematic, not static: a static collider that moves leaves the
        // static grid pointing at where it used to be.
        kind: ColliderKind.kinematic,
        layer: CollisionLayers.player,
        userData: keys,
      ),
    );

Door _door(({MechanismWorld mechanisms, CollisionWorld world}) w, String name,
        {String? key}) =>
    w.mechanisms.add(
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

void main() {
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
          layer: CollisionLayers.monster,
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

      final empty = _player(w.world, Vector3(0.0, 1.0, 0.0), keys: KeyRing());
      _run(w.mechanisms, 0.5);
      expect(door.state, MoverState.closed);
      expect(trigger.takeOutcome(), isA<Refused>());

      w.world.remove(empty);
      final ring = KeyRing()..take('blue');
      _player(w.world, Vector3(0.0, 1.0, 0.0), keys: ring);
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
      final ring = KeyRing();
      final key = w.mechanisms.add(
        KeyPickup(
          colour: 'blue',
          collider: _volume(w.world, Vector3(0.0, 0.5, 0.0), 0.6),
        ),
      );

      final player = _player(w.world, Vector3(0.0, 0.9, 4.0), keys: ring);
      _run(w.mechanisms, 0.2);
      expect(ring.has('blue'), isFalse);

      player.moveTo(Vector3(0.0, 0.9, 0.0));
      _run(w.mechanisms, 0.1);

      expect(ring.has('blue'), isTrue);
      expect(key.isTaken, isTrue);
    });

    test('and stops being in the world once it is taken', () {
      final w = _world();
      final ring = KeyRing();
      final key = w.mechanisms.add(
        KeyPickup(
          colour: 'blue',
          collider: _volume(w.world, Vector3(0.0, 0.9, 0.0), 0.6),
        ),
      );
      _player(w.world, Vector3(0.0, 0.9, 0.0), keys: ring);
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
      final ring = KeyRing();
      final door = _door(w, 'gate', key: 'blue');
      w.mechanisms.add(
        KeyPickup(
          colour: 'blue',
          collider: _volume(w.world, Vector3(0.0, 0.9, 0.0), 0.6),
        ),
      );
      final player = _player(w.world, Vector3(0.0, 0.9, 6.0), keys: ring);

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
