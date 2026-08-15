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
      startAt: start,
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

  /// Runs forward jumping as high and as often as it can, for [steps] or until
  /// [until].
  ///
  /// **A rhythm rather than a route.** A script keyed to the level's own
  /// coordinates has to be rewritten every time somebody moves a ledge, and
  /// then it fails in a way that says nothing about what broke. Twenty-two
  /// steps of held jump is a full ascent, the eight that follow are the release
  /// that both ends the jump and makes the next press an edge — so this clears
  /// a gap and double-jumps a ledge without being told where either is.
  void autopilot(int steps, {bool Function(_Game game)? until}) {
    for (var i = 0; i < steps; i++) {
      if (until != null && until(this)) return;
      step(forward: true, jump: i % 30 < 22);
    }
  }

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

  test('the summit can be reached', () {
    // The half of the level a person plays and a script did not: over the
    // drop, onto the ledge that takes two jumps, and into the exit. Without
    // this, a level edited into an unfinishable state ships.
    final game = _Game()
      ..autopilot(900, until: (_Game g) => g.sim.state == RunState.finished);

    expect(game.sim.state, RunState.finished);
    expect(game.sim.deaths, 0, reason: 'the route does not require dying');
    // The only level there is, so the exit names nothing to go on to. Asserted
    // rather than left unsaid: the first version of this test expected a next
    // level, copied from the package's own fixture, and passed on nothing.
    expect(game.sim.nextLevel, isNull);
  });

  test('the brass pad over the drop can actually be jumped onto', () {
    // **A player could not, and the arithmetic says why:** a single jump rises
    // 1.88 m and the pad's top was at 1.80, so it was clearable for the one
    // instant of the apex and no longer. A platform you can only reach on a
    // frame-perfect apex is not a platform.
    //
    // Mutation: put the pad back at 1.6 (top 1.8) and this fails.
    final game = _Game();
    // On the floor, in line with the pad, short of the edge.
    game.runner.body.teleport(Vector3(-3.0, 0.9, 5.8));

    // Jump, and steer forward for a third of a second. Holding forward the
    // whole way is what a running jump is, and a running jump clears the pad
    // entirely — six metres a second carries 4.7 m through the air and the pad
    // is 2.2 m across. Landing on it is a hop, and that is a fair thing for a
    // level to ask.
    for (var i = 0; i < 90; i++) {
      game.step(forward: i < 20, jump: i < 24);
    }

    expect(game.runner.isGrounded, isTrue, reason: 'it should have landed');
    expect(game.runner.position.y, closeTo(2.0, 0.15),
        reason: 'a body half a metre high standing on a pad topped at 1.1');
    expect(game.runner.position.z, inInclusiveRange(6.9, 9.1),
        reason: 'on the pad, not past it');
    expect(game.runner.purse['coin'], 1, reason: 'the coin sits over the pad');
    expect(game.sim.deaths, 0);
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
