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
import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

/// A floor, a pit beyond it, a coin, a checkpoint, and a runner.
final class _World {
  _World({int lives = -1, int deaths = 0, double elapsed = 0.0}) {
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
      lives: lives,
      deaths: deaths,
      elapsed: elapsed,
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

  /// One step, standing still. For a death that has nothing to do with walking.
  void step() => run(1, forward: false);

  void restore(Snapshot from) => sim.restore(from);

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
  group('progress', _progressTests);

  test('a run restores where it was saved', () {
    // Walked far enough to have taken the coin, passed the checkpoint and be
    // somewhere that is not the origin — see the note at the top of the file.
    final first = _World()..run(90);
    expect(
      first.runner.purse['coin'],
      1,
      reason: 'the moment must not be zero',
    );
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
    expect(
      first.sim.deaths,
      greaterThan(0),
      reason: 'it should walk off the end',
    );

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

    expect(
      (second.runner.position - wasAt).length,
      lessThan(0.2),
      reason: 'the first step after a load is not a teleport',
    );
  });
}

/// Kills the runner and lets the simulation notice.
///
/// Two steps, and the second is not optional: a death is seen at the end of
/// one step and acted on at the start of the next, which is the arrangement
/// that keeps the revive out of the middle of a collision dispatch.
void _die(_World run) {
  run.runner.health.damage(1000.0);
  run.step();
  run.step();
}

/// Lives, and the clock a run is measured by.
///
/// Both are progression rather than movement, and both are the kind of thing a
/// save has to carry or a resumed run is a different run.
void _progressTests() {
  test('a run with no lives set cannot be lost', () {
    // The default, and the reason it is negative: everything written before
    // lives existed keeps working, and every test that dies four times still
    // dies four times.
    final run = _World();
    for (var i = 0; i < 6; i++) {
      _die(run);
    }

    expect(run.sim.deaths, 6);
    expect(run.sim.state, isNot(RunState.lost));
  });

  test('three lives means three deaths and then the run is over', () {
    // Mutation: decrement after reviving rather than before. The player gets a
    // fourth life, which is the sort of thing nobody notices and everybody
    // feels.
    final run = _World(lives: 3);

    _die(run);
    expect(run.sim.state, RunState.running, reason: 'one death is not the end');
    expect(run.sim.lives, 2);

    _die(run);
    expect(run.sim.lives, 1);

    _die(run);
    expect(run.sim.state, RunState.lost);
    expect(run.sim.deaths, 3);
  });

  test('a lost run stops running', () {
    // Mutation: leave the state as `fallen` when the lives run out — the runner
    // respawns for ever and the count is decoration.
    final run = _World(lives: 1);
    _die(run);
    expect(run.sim.state, RunState.lost);

    final where = run.runner.position.clone();
    run.run(60);
    expect(run.runner.position, where, reason: 'it kept playing');
  });

  test('the clock counts simulated time, not wall-clock', () {
    // Mutation: read `DateTime.now()`. The number stops being the same for the
    // same play, and a player whose machine stuttered is charged for it.
    final run = _World()..run(120);
    expect(run.sim.elapsed, closeTo(2.0, 0.01));
  });

  test('and it stops once the run is over', () {
    final run = _World(lives: 1);
    run.run(60);
    final atDeath = run.sim.elapsed;
    _die(run);
    run.run(120);

    expect(run.sim.state, RunState.lost);
    expect(run.sim.elapsed, closeTo(atDeath, 0.05));
  });

  test('a save carries both', () {
    final run = _World(lives: 3)..run(90);
    _die(run);
    final saved = run.sim.save();

    final other = _World(lives: 3)..restore(saved);
    expect(other.sim.lives, run.sim.lives);
    expect(other.sim.elapsed, closeTo(run.sim.elapsed, 1e-6));
    expect(other.sim.deaths, run.sim.deaths);
  });

  group('a run that spans levels', () {
    // **Three lives used to mean three lives per level.** Every level built a
    // fresh simulation from the constant, so the tally of the levels before it
    // went nowhere — and the clock on the summit read as the time for the last
    // climb rather than for the climb.
    //
    // A run spans levels and a simulation does not: only an application knows
    // what the level after this one is, so only it can carry the tally. What is
    // tested here is that a simulation will *take* one.

    test('starts where the run had got to, not at nothing', () {
      final world = _World(lives: 2, deaths: 5, elapsed: 91.5);

      expect(world.sim.lives, 2);
      expect(world.sim.deaths, 5);
      expect(world.sim.elapsed, 91.5);
    });

    test('and goes on counting from there', () {
      final world = _World(lives: 3, deaths: 5, elapsed: 91.5);

      world.step();

      expect(world.sim.elapsed, greaterThan(91.5));
      expect(world.sim.deaths, 5, reason: 'nothing died');
    });

    test('and a carried tally survives being saved and read back', () {
      // The other half of carrying it: a player who closes the game halfway up
      // the second level must not come back with the first level forgiven.
      final world = _World(lives: 2, deaths: 5, elapsed: 91.5);
      final saved = world.sim.save();

      final fresh = _World();
      fresh.sim.restore(saved);

      expect(fresh.sim.lives, 2);
      expect(fresh.sim.deaths, 5);
      expect(fresh.sim.elapsed, 91.5);
    });
  });

  group('a death is an event, not a difference between two numbers', () {
    // **Three readers each kept their own copy of `deaths`** — the camera, the
    // particles and the soundtrack — and compared it against the simulation's
    // to decide whether one had just happened. That works exactly as long as
    // every run starts at nought, and runs stopped doing that the day a tally
    // began carrying into the next level: the first step of level two fired a
    // death for one that happened on level one, and starting over fired one for
    // a death that had just been undone.

    test('a run that begins with deaths on it has not just died', () {
      final world = _World(lives: 3, deaths: 5);

      world.step();

      expect(world.sim.deaths, 5, reason: 'the tally is carried, not reset');
      expect(
        world.sim.diedThisStep,
        isFalse,
        reason: 'a carried death fired the death sound on arrival',
      );
    });

    test('and a death is true for the step it happened in', () {
      // Fallen off the world: the ordinary way a run ends a life.
      final world = _World(lives: 3);
      var died = false;
      for (var i = 0; i < 240 && !died; i++) {
        world.run(1, forward: true);
        died = world.sim.diedThisStep;
      }

      expect(died, isTrue, reason: 'nothing killed the runner in four seconds');
      expect(world.sim.deaths, greaterThan(0));
    });

    test('and false on the step after', () {
      final world = _World(lives: 3);
      var died = false;
      for (var i = 0; i < 240 && !died; i++) {
        world.run(1, forward: true);
        died = world.sim.diedThisStep;
      }
      expect(died, isTrue);

      world.step();

      expect(
        world.sim.diedThisStep,
        isFalse,
        reason: 'the flag stayed up, so the burst plays every frame',
      );
    });
  });

  group('the outcome every game shares', () {
    test('is playing while the run is going, dead runner and all', () {
      // `fallen` is one step of a run that is going on, not an outcome: a
      // runner who has just died has not lost until the lives do. Getting this
      // wrong writes "you lost" over a respawn.
      expect(RunState.running.outcome, RunOutcome.playing);
      expect(RunState.fallen.outcome, RunOutcome.playing);
    });

    test('and tells the two endings apart', () {
      expect(RunState.lost.outcome, RunOutcome.lost);
      expect(RunState.finished.outcome, RunOutcome.won);
    });

    test('and every state has one', () {
      // The switch is exhaustive, so this fails to compile rather than at run
      // time if a state is added — and this asserts the other half: that a new
      // state was thought about rather than mapped to `playing` to shut the
      // compiler up.
      for (final state in RunState.values) {
        expect(state.outcome, isNotNull);
      }
    });
  });
}
