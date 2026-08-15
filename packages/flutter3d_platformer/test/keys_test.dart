/// Locked doors, and the line that was missing for them to work at all.
///
/// The engine has had keyed doors and keyed exits since the shooter; a
/// platformer's runner simply never answered the question, so every locked door
/// in this genre was locked for ever. Nobody noticed because no level had one —
/// which is the argument for a test that authors one.
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_platformer/flutter3d_platformer.dart';
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
}
