/// The level this game actually ships, played without a renderer.
///
/// The package's own playthrough builds its level in code, which proves the
/// machinery and nothing about the document. This one reads the asset off disk
/// the way the application does, so a level edited into an unplayable state
/// fails here rather than in front of somebody.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_platformer/flutter3d_platformer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

Level _shipped() => Level.fromJson(
      jsonDecode(File('assets/levels/ascent.json').readAsStringSync())
          as Map<String, Object?>,
    );

/// Everything `main.dart` assembles, minus anything that draws.
final class _Game {
  _Game() {
    LevelValidator(registry: platformerRegistry(), rules: platformerRules())
        .assertValid(level);

    level.addTo(world);
    mechanisms = MechanismWorld(world);
    level.spawnInto(
      SpawnContext(
        world: world,
        actors: ActorSystem(world: world),
        mechanisms: mechanisms,
      ),
      registry: platformerRegistry(),
    );

    final start = level.playerStart?.position ?? Vector3.zero();
    runner = Runner(
      body: CharacterController(
        world: world,
        position: start + Vector3(0.0, 0.9, 0.0),
      ),
    );
    sim = PlatformerSimulation(
      runner: runner,
      collision: world,
      input: input,
      startAt: runner.body.position.clone(),
      mechanisms: mechanisms,
    );
  }

  final Level level = _shipped();
  final CollisionWorld world = CollisionWorld();
  final InputState input = InputState();
  late final MechanismWorld mechanisms;
  late final Runner runner;
  late final PlatformerSimulation sim;

  bool _forward = false;
  bool _jump = false;

  /// Edges only, the way a keyboard produces them. See the package's own
  /// playthrough for what happens when a harness releases on every step.
  void step({bool forward = false, bool jump = false}) {
    input.beginStep();
    if (forward != _forward) {
      forward ? input.press(GameAction.moveForward) : input.release(GameAction.moveForward);
      _forward = forward;
    }
    if (jump != _jump) {
      jump ? input.press(GameAction.jump) : input.release(GameAction.jump);
      _jump = jump;
    }
    sim.step(_dt);
    input.endStep();
  }
}

void main() {
  test('the level this game ships has no errors in it', () {
    final issues =
        LevelValidator(registry: platformerRegistry(), rules: platformerRules())
            .validate(_shipped());

    expect(
      issues.where((LevelIssue i) => i.isError).map((LevelIssue i) => i.message),
      isEmpty,
    );
  });

  test('the whole game builds without a renderer', () {
    final game = _Game();
    expect(game.sim.state, RunState.running);
    expect(game.runner.purse['coin'], 0);
  });

  test('the coins in the first room are reachable on foot', () {
    // Not the whole level: getting to the summit needs a double jump timed
    // against a moving platform, and a script that plays it would be a script
    // that has to be rewritten every time the level is edited. What is worth
    // pinning is that the level loads, spawns, and can be walked in.
    final game = _Game();
    for (var i = 0; i < 300; i++) {
      game.step(forward: true);
      if (game.runner.purse['coin'] > 0) break;
    }

    expect(game.runner.purse['coin'], greaterThan(0));
  });

  test('walking off the edge is survivable, because there is a checkpoint', () {
    final game = _Game();
    // Forward until it falls in the drop and comes back.
    for (var i = 0; i < 600 && game.sim.deaths == 0; i++) {
      game.step(forward: true);
    }
    expect(game.sim.deaths, greaterThan(0), reason: 'the drop should catch it');

    game.step();
    expect(game.sim.state, RunState.running);
    expect(game.runner.health.isAlive, isTrue);
    // Back at the checkpoint before the gap rather than at the level's start.
    expect(game.runner.position.z, greaterThan(3.0));
  });
}
