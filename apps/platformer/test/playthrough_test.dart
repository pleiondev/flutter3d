/// The level this game actually ships, played without a renderer.
///
/// The package's own playthrough builds its level in code, which proves the
/// machinery and nothing about the document. This one reads the asset off disk
/// the way the application does, so a level edited into an unplayable state
/// fails here rather than in front of somebody.
///
/// It does **not** try to finish the level. The field is a hundred and twenty
/// metres across and two hundred and sixty long, with a locked gate, a ferry
/// and a shaft in it; a script for that is a script rewritten every time a
/// brush moves, and the package already proves a level can be finished. What is
/// pinned here is that the document loads, that its first zone is crossable
/// only by jumping, and that everything the level is built around is in it.
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
    final kinds = platformerRegistry();
    LevelValidator(registry: kinds, rules: platformerRules()).assertValid(level);

    level.addTo(world);
    mechanisms = MechanismWorld(world);
    (kinds[PlatformerEntities.crate] as CrateKind?)?.dynamics = dynamics;
    level.spawnInto(
      SpawnContext(
        world: world,
        actors: ActorSystem(world: world),
        mechanisms: mechanisms,
      ),
      registry: kinds,
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
      dynamics: dynamics,
    );
  }

  final Level level = _shipped();
  final CollisionWorld world = CollisionWorld();
  late final Dynamics dynamics = Dynamics(world: world);
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
      forward
          ? input.press(GameAction.moveForward)
          : input.release(GameAction.moveForward);
      _forward = forward;
    }
    if (jump != _jump) {
      jump ? input.press(GameAction.jump) : input.release(GameAction.jump);
      _jump = jump;
    }
    sim.step(_dt);
    input.endStep();
  }

  /// Runs forward jumping on a rhythm: twenty-two steps held, eight released,
  /// which is a full ascent and then the release that makes the next press an
  /// edge. A rhythm rather than a route — a script keyed to the level's own
  /// coordinates is rewritten every time somebody moves a brush.
  void autopilot(int steps, {bool Function(_Game game)? until}) {
    for (var i = 0; i < steps; i++) {
      if (until != null && until(this)) return;
      step(forward: true, jump: i % 30 < 22);
    }
  }

  /// Walks forward, and only forward, until [until] or [steps] run out.
  void walk(int steps, {bool Function(_Game game)? until}) {
    for (var i = 0; i < steps; i++) {
      if (until != null && until(this)) return;
      step(forward: true);
    }
  }

  T? named<T extends Mechanism>(String name) {
    final found = mechanisms[name];
    return found is T ? found : null;
  }
}

void main() {
  group('the document', () {
    test('the level this game ships has no errors in it', () {
      final issues = LevelValidator(
        registry: platformerRegistry(),
        rules: platformerRules(),
      ).validate(_shipped());

      expect(
        issues
            .where((LevelIssue i) => i.isError)
            .map((LevelIssue i) => i.message),
        isEmpty,
      );
    });

    test('the whole game builds without a renderer', () {
      final game = _Game();
      expect(game.sim.state, RunState.running);
      expect(game.runner.purse['coin'], 0);
    });

    test('the field is as big as the level says', () {
      // Written down so that shrinking the level by accident — a brush resized,
      // a wall moved in — fails rather than merely looking different.
      final level = _shipped();
      var minX = double.infinity, maxX = -double.infinity;
      var minZ = double.infinity, maxZ = -double.infinity;
      for (final brush in level.brushes) {
        if (brush.min.x < minX) minX = brush.min.x;
        if (brush.max.x > maxX) maxX = brush.max.x;
        if (brush.min.z < minZ) minZ = brush.min.z;
        if (brush.max.z > maxZ) maxZ = brush.max.z;
      }

      expect(maxX - minX, greaterThan(118.0));
      expect(maxZ - minZ, greaterThan(260.0));
    });

    test('everything the level is built around is in it', () {
      // One assertion per thing a player is meant to meet, so a level edited
      // into "no springs" or "no gate" says which one went.
      final game = _Game();

      expect(game.named<Spring>('the first pad'), isNotNull);
      expect(game.named<Spring>('the cold pad'), isNotNull);
      expect(game.named<Door>('the blue gate')?.isLocked, isTrue);
      expect(game.named<MovingPlatform>('the ferry'), isNotNull);
      expect(game.named<Collectible>('the blue key')?.key, 'blue');
      expect(game.named<Checkpoint>('the brink')?.order, 1);
      expect(game.named<Checkpoint>('the foot of the stair')?.order, 4);
      expect(game.named<Hazard>('the spikes')?.instant, isFalse,
          reason: 'spikes hurt, the drop kills');
      expect(game.dynamics.bodies, hasLength(2), reason: 'two crates');
    });

    test('the gate is shut until the key is carried', () {
      // The engine has had keyed doors since the shooter and this genre could
      // not open one until the runner grew a key ring. Asserted through the
      // world, with the body, the way the game asks.
      final game = _Game();
      final gate = game.named<Door>('the blue gate')!;

      expect(gate.activate(game.mechanisms.activationBy(game.runner.body.collider)),
          isA<Refused>());

      game.runner.keyRing.take('blue');
      expect(gate.activate(game.mechanisms.activationBy(game.runner.body.collider)),
          isA<Activated>());
    });
  });

  group('the first zone', () {
    test('the coins on the way out are collected on foot', () {
      final game = _Game()
        ..walk(400, until: (_Game g) => g.runner.purse['coin'] > 0);

      expect(game.runner.purse['coin'], greaterThan(0));
    });

    test('a collected coin shrinks away rather than blinking out', () {
      final game = _Game()
        ..walk(400, until: (_Game g) => g.runner.purse['coin'] > 0);
      final coin = game.named<Collectible>('coin one')!;

      expect(coin.isTaken, isTrue);
      expect(coin.sinceTaken, lessThan(0.1), reason: 'it went just now');

      game.walk(30);
      expect(coin.sinceTaken, closeTo(0.5, 0.15));
    });

    test('the drop is crossed by jumping and not by walking', () {
      // Both halves, because the first without the second proves nothing.
      final jumped = _Game()
        ..autopilot(900, until: (_Game g) => g.runner.position.z > 33.0);
      expect(jumped.runner.position.z, greaterThan(33.0));
      expect(jumped.sim.deaths, 0, reason: 'the rhythm clears it');

      final walked = _Game()..walk(900, until: (_Game g) => g.sim.deaths > 0);
      expect(walked.sim.deaths, greaterThan(0), reason: 'the drop is a drop');
    });

    test('falling in puts the runner back at the checkpoint, not the start', () {
      final game = _Game()..walk(900, until: (_Game g) => g.sim.deaths > 0);
      expect(game.sim.deaths, greaterThan(0));

      game.step();
      expect(game.sim.state, RunState.running);
      expect(game.runner.health.isAlive, isTrue);
      expect(game.runner.position.z, closeTo(18.0, 1.5),
          reason: 'the brink said 18, and the level starts at -22');
    });

    test('a crate is where the level put it, and shoves', () {
      final game = _Game();
      final crate = game.dynamics.bodies.first;
      final before = crate.position.clone();

      // Walked into from beside it rather than from the spawn: what is under
      // test is the crate, not the route to it.
      game.runner.body.teleport(Vector3(before.x, 0.9, before.z - 2.0));
      game.walk(200);

      expect(crate.position.z, greaterThan(before.z + 0.5));
      expect(crate.position.y, closeTo(before.y, 0.3), reason: 'and stays down');
    });
  });
}
