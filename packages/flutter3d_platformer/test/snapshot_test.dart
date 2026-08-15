/// `PlatformerSimulation.save/restore`, which had no test at all.
///
/// A snapshot is the same object three times over — a save, a network packet
/// and a test's input — so a field it forgets is wrong in three places at once.
/// The rule this file follows comes from the shooter's own hard lesson: **a
/// field is only under test at a moment when it is not zero.** So nothing is
/// snapshotted at the start; every state is put somewhere interesting first.
library;

import 'dart:convert';

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_platformer/flutter3d_platformer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

/// A floor, a pit beyond it, a coin, a checkpoint, and a runner.
final class _World {
  _World() {
    world.addBox(Vector3(0.0, -0.5, 4.0), Vector3(20.0, 1.0, 12.0));
    mechanisms = MechanismWorld(world);

    coin = mechanisms.add(
      Collectible(
        name: 'coin',
        what: 'coin',
        collider: _trigger(Vector3(0.0, 0.9, 2.0), CollisionLayers.pickup),
      ),
    );
    checkpoint = mechanisms.add(
      Checkpoint(
        name: 'post',
        order: 1,
        at: Vector3(0.0, 0.0, 4.0),
        collider: _trigger(Vector3(0.0, 1.0, 4.0), CollisionLayers.trigger),
      ),
    );

    runner = Runner(
      body: CharacterController(world: world, position: Vector3(0.0, 0.9, 0.0)),
    );
    sim = PlatformerSimulation(
      runner: runner,
      collision: world,
      input: input,
      startAt: Vector3.zero(),
      mechanisms: mechanisms,
    );
  }

  Collider _trigger(Vector3 at, int layer) => world.add(
        Collider(
          shape: CollisionBox(Vector3.all(0.5)),
          position: at,
          kind: ColliderKind.trigger,
          layer: layer,
          mask: CollisionLayers.player,
        ),
      );

  final CollisionWorld world = CollisionWorld();
  final InputState input = InputState();
  late final MechanismWorld mechanisms;
  late final Runner runner;
  late final Collectible coin;
  late final Checkpoint checkpoint;
  late final PlatformerSimulation sim;

  bool _forward = false;

  void run(int steps, {bool forward = true}) {
    for (var i = 0; i < steps; i++) {
      input.beginStep();
      if (forward != _forward) {
        forward
            ? input.press(GameAction.moveForward)
            : input.release(GameAction.moveForward);
        _forward = forward;
      }
      sim.step(_dt);
      input.endStep();
    }
  }
}

/// A save, encoded and decoded, because that is what a save really is.
Snapshot _throughText(Snapshot from) =>
    Snapshot(jsonDecode(jsonEncode(from.data)) as Map<String, Object?>);

void main() {
  test('a run restores where it was saved', () {
    // Walked far enough to have taken the coin, passed the checkpoint and be
    // somewhere that is not the origin — see the note at the top of the file.
    final first = _World()..run(90);
    expect(first.runner.purse['coin'], 1, reason: 'the moment must not be zero');
    expect(first.checkpoint.isReached, isTrue);

    final saved = _throughText(first.sim.save());

    final second = _World()..sim.restore(saved);

    expect(second.runner.position.z, closeTo(first.runner.position.z, 0.01));
    expect(second.runner.purse['coin'], 1);
    expect(second.coin.isTaken, isTrue, reason: 'a taken coin stays taken');
    expect(second.checkpoint.isReached, isTrue);
    expect(second.sim.respawnPoint.z, closeTo(4.0, 0.01));
  });

  test('a restored world does not hand out the coin twice', () {
    // The failure this guards: mechanism state restores, the collider does not
    // leave the world, and walking back over an already-taken coin pays again.
    final first = _World()..run(90);
    final saved = _throughText(first.sim.save());

    final second = _World()..sim.restore(saved);
    second.run(60, forward: false);
    second.run(90);

    expect(second.runner.purse['coin'], 1);
  });

  test('deaths and the fallen state come back', () {
    // Mutation: drop `deaths` from `save`. A player who reloads has their
    // count reset, and a level that ends on "no deaths" hands out a medal.
    final first = _World()..run(400);
    expect(first.sim.deaths, greaterThan(0), reason: 'it should walk off the end');

    final saved = _throughText(first.sim.save());
    final second = _World()..sim.restore(saved);

    expect(second.sim.deaths, first.sim.deaths);
  });

  test('a restore leaves the broadphase agreeing with the bodies', () {
    // `restore` re-indexes and updates on purpose. Without it the runner is
    // where the save said and the grid thinks it is where it was, so the first
    // step after a load can walk through a wall.
    final first = _World()..run(90);
    final saved = _throughText(first.sim.save());

    final second = _World()..sim.restore(saved);
    final wasAt = second.runner.position.clone();
    second.run(1, forward: false);

    expect((second.runner.position - wasAt).length, lessThan(0.2),
        reason: 'the first step after a load is not a teleport');
  });
}
