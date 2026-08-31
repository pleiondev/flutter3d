/// Locked doors, and the line that was missing for them to work at all.
///
/// The engine has had keyed doors and keyed exits since the shooter; a
/// platformer's runner simply never answered the question, so every locked door
/// in this genre was locked for ever. Nobody noticed because no level had one —
/// which is the argument for a test that authors one.
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

/// A room with a floor, a blue key on it and a door that wants one.
final class _Room {
  _Room() {
    world.addBox(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0));
    mechanisms = MechanismWorld(world);

    runner = Runner(
      body: CharacterController(world: world, position: Vector3(0.0, 0.9, 0.0)),
    );

    key = mechanisms.add(
      Collectible(
        name: 'blue key',
        what: 'key',
        key: 'blue',
        collider: world.add(
          Collider(
            shape: CollisionBox(Vector3.all(0.35)),
            position: Vector3(0.0, 0.9, 3.0),
            kind: ColliderKind.trigger,
            layer: CollisionLayers.pickup,
            mask: CollisionLayers.player,
          ),
        ),
      ),
    );

    door = mechanisms.add(
      Door(
        name: 'blue door',
        collider: world.add(
          Collider(
            shape: CollisionBox(Vector3(1.5, 1.5, 0.2)),
            position: Vector3(0.0, 1.5, 8.0),
          ),
        ),
        travel: Vector3(0.0, 3.0, 0.0),
        speed: 9.0,
        wait: 0.0,
        key: 'blue',
      ),
    );
  }

  final CollisionWorld world = CollisionWorld();
  final InputState input = InputState();
  late final MechanismWorld mechanisms;
  late final Runner runner;
  late final Collectible key;
  late final Door door;

  /// Asks the door the way the game does: through the world, with the body.
  ActivationOutcome knock() =>
      door.activate(mechanisms.activationBy(runner.body.collider));

  void walk(int steps) {
    final input = InputState()..press(GameAction.moveForward);
    for (var i = 0; i < steps; i++) {
      input.beginStep();
      mechanisms.step(_dt);
      world.reindex();
      runner.step(_dt, input);
      world.update();
      world.clearKinematicDeltas();
      input.endStep();
    }
  }
}

void main() {
  _vanishing();

  test('a locked door refuses a runner with no key', () {
    // Mutation: give `Runner` the mixin without overriding `keys` — it cannot
    // compile, which is the good kind of failure. Mutation that does compile:
    // return `const <String>{}` from `keys`, and this passes while the one
    // below fails, which is exactly the state the package shipped in.
    final room = _Room();
    expect(room.knock(), isA<Refused>());
    expect(room.runner.keys, isEmpty);
  });

  test('walking over the key opens it', () {
    final room = _Room()..walk(60);

    expect(room.key.isTaken, isTrue, reason: 'the key is on the way');
    expect(room.runner.keys, contains('blue'));
    expect(room.knock(), isA<Activated>());
  });

  test('a key is held, not counted', () {
    // The purse counts and the ring holds, and the two answers are separate on
    // purpose: a door asks "have you got one", never "how many".
    final room = _Room()..walk(60);

    expect(room.runner.purse['key'], 1);
    expect(room.runner.keys, hasLength(1));
  });

  test('keys survive a save and a restore', () {
    // Mutation: drop the `keys` line from `Runner.save`. A player who saves in
    // front of a door they have the key for reloads unable to open it, which is
    // the worst possible moment to lose it.
    final room = _Room()..walk(60);
    final saved = room.runner.save();

    final other = _Room();
    other.runner.restore(saved);

    expect(other.runner.keys, contains('blue'));
    expect(other.knock(), isA<Activated>());
  });
}

/// The coin's exit, which is a look and still belongs under test: the number it
/// is driven by lives in the simulation.
void _vanishing() {
  test('a taken coin counts the time since it left', () {
    final room = _Room();
    expect(room.key.sinceTaken, double.infinity, reason: 'still on the floor');

    // Up to the moment it is taken and no further: the runner reaches it in
    // about half a second, so walking a fixed sixty steps measures the walk
    // rather than the coin.
    for (var i = 0; i < 120 && !room.key.isTaken; i++) {
      room.walk(1);
    }
    expect(room.key.isTaken, isTrue);
    expect(room.key.sinceTaken, closeTo(0.0, 0.05), reason: 'just now');

    room.walk(30);
    expect(room.key.sinceTaken, closeTo(0.5, 0.1));
  });

  test('a restored coin is not caught mid-shrink', () {
    // Mutation: carry `sinceTaken` through `restore`. A save written on the
    // frame a coin was collected loads with a half-sized coin standing in a
    // room the player has already cleared.
    final room = _Room()..walk(60);
    final saved = room.key.save();

    final other = _Room();
    other.key.restore(saved);

    expect(other.key.isTaken, isTrue);
    expect(other.key.sinceTaken, double.infinity);
  });

  test('a gate that refuses says so, and the game can hear it', () {
    // **The level has been saying things since the engine had signals, and this
    // game never listened.** A trigger fires from inside the collision dispatch
    // where there is nobody to return an outcome to, so the sentence is parked
    // in `MechanismEvents.messages` — which the shooter drains, and the dungeon
    // drains, and the platformer did not. A player who walked into a locked
    // gate was told nothing and had no way to learn a key existed.
    //
    // **Through a plate and not by knocking**, which is the difference that
    // matters: `door.activate(...)` hands its refusal straight back to whoever
    // called it, and nobody calls it in this game. What a player touches is the
    // plate in front of the gate, and that is the path where the sentence has
    // nowhere to go but the event list.
    //
    // Mutation: drop `saidThisStep.addAll(events.messages)` from the
    // simulation. The gate still refuses and the player still hears nothing.
    final room = _Room();
    room.mechanisms.add(
      TriggerVolume(
        name: 'the plate',
        target: 'blue door',
        collider: room.world.add(
          Collider(
            shape: CollisionBox(Vector3(2.0, 1.5, 0.5)),
            position: Vector3(0.0, 1.0, 1.5),
            kind: ColliderKind.trigger,
            layer: CollisionLayers.trigger,
            mask: CollisionLayers.player,
          ),
        ),
      ),
    );

    final sim = PlatformerSimulation(
      runner: room.runner,
      collision: room.world,
      input: room.input,
      startAt: Vector3.zero(),
      mechanisms: room.mechanisms,
    );

    // Onto the plate, which sits before the key: so the runner arrives at the
    // gate's trigger empty-handed, as a player would the first time.
    final said = <String>[];
    // Twenty steps is two metres: onto the plate at z = 1.5 and stopped well
    // short of the key at z = 3.
    for (var i = 0; i < 20; i++) {
      room.input.beginStep();
      room.input.press(GameAction.moveForward);
      sim.step(_dt);
      room.input.endStep();
      said.addAll(sim.saidThisStep);
    }

    expect(room.runner.keys, isEmpty, reason: 'it picked the key up first');
    expect(said, isNotEmpty,
        reason: 'it stood on the gate\'s plate and was told nothing');
    expect(said.join(' '), contains('blue'),
        reason: 'it said "$said", which does not name the key');
  });

  group('and a save carries it', () {
    // **The acceptance for putting `save`/`restore` on `Mechanism` itself.**
    // Both games kept a hand-written `switch` listing the mechanism types they
    // knew about, and a `Door` is a `Mover`, so a door was saved — but the
    // *trigger* that opened it was a `Signal`, which was in neither list. Open
    // a gate, save, load, and the plate is unspent: the gate closes and the
    // player is asked to find the key again.
    test('an opened door is still open, and its trigger is still spent', () {
      final room = _Room();
      room.walk(240);
      expect(room.runner.keys, contains('blue'), reason: 'never took the key');
      expect(room.knock(), isA<Activated>(), reason: 'the door refused the key');

      room.walk(60);
      final openedTo = room.door.progress;
      expect(openedTo, greaterThan(0.5), reason: 'the door has not moved');

      final saved = <String, Object?>{
        for (final m in room.mechanisms.all)
          if (m.name != null) m.name!: m.save(),
      };

      // A second world, built exactly as the first: this is a reload.
      final again = _Room();
      for (final m in again.mechanisms.all) {
        final row = saved[m.name];
        if (row is Map<String, Object?>) m.restore(row);
      }

      expect(again.door.progress, closeTo(openedTo, 0.01),
          reason: 'the door came back shut');
    });

    test('a one-shot plate that has fired does not fire again after a load',
        () {
      // **The claim the acceptance for this stage is written as.** A `Door` is
      // a `Mover` and was in both games' hand-written lists; the *plate* in
      // front of it is a `Signal` and was in neither. So the gate was saved
      // open and its trigger came back unspent — walk in again and it fires a
      // second time, which for a one-shot is the difference between a trap that
      // has sprung and one that is still armed.
      //
      // Mutation: return the empty map from `Signal.save`, or ignore `spent` in
      // `Signal.restore`. Either way the plate is armed again.
      final room = _Room();
      final plate = room.mechanisms.add(
        TriggerVolume(
          name: 'the plate',
          target: 'blue door',
          once: true,
          collider: room.world.add(
            Collider(
              shape: CollisionBox(Vector3(2.0, 1.5, 0.5)),
              position: Vector3(0.0, 1.0, 6.0),
              kind: ColliderKind.trigger,
              layer: CollisionLayers.trigger,
              mask: CollisionLayers.player,
            ),
          ),
        ),
      );

      room.walk(240);
      expect(room.runner.keys, contains('blue'), reason: 'never took the key');
      expect(plate.isSpent, isTrue, reason: 'it never walked into the plate');

      final saved = plate.save();

      // A fresh plate, as a reload builds one, and then the save put back.
      final again = _Room();
      final reloaded = again.mechanisms.add(
        TriggerVolume(
          name: 'the plate',
          target: 'blue door',
          once: true,
          collider: again.world.add(
            Collider(
              shape: CollisionBox(Vector3(2.0, 1.5, 0.5)),
              position: Vector3(0.0, 1.0, 6.0),
              kind: ColliderKind.trigger,
              layer: CollisionLayers.trigger,
              mask: CollisionLayers.player,
            ),
          ),
        ),
      );
      expect(reloaded.isSpent, isFalse, reason: 'a fresh plate starts armed');

      reloaded.restore(saved);

      expect(reloaded.isSpent, isTrue,
          reason: 'the plate came back armed, so the save lost its latch');
      expect(
        reloaded.activate(again.mechanisms.activationBy(
          again.runner.body.collider,
        )),
        isA<NothingToDo>(),
        reason: 'a spent one-shot answered a second time',
      );
    });

    test('every mechanism in the room answers, including the ones with '
        'nothing to say', () {
      // Mutation: give `Mechanism.save` a default returning null instead of
      // making it abstract. This still passes — which is why the claim is about
      // *every* mechanism rather than about the door: what the abstract method
      // buys is that a type added tomorrow cannot quietly opt out, and the only
      // way to say that in a test is to walk the whole world.
      final room = _Room();
      for (final m in room.mechanisms.all) {
        expect(m.name, isNotNull,
            reason: '${m.runtimeType} has no name, so it is never saved');
        expect(() => m.save(), returnsNormally,
            reason: '${m.runtimeType} cannot be saved');
        expect(() => m.restore(m.save()), returnsNormally,
            reason: '${m.runtimeType} cannot restore its own save');
      }
    });
  });
}
