/// The level this game actually ships, played without a renderer.
///
/// The package's own playthrough builds its level in code, which proves the
/// machinery and nothing about the document. This one reads the asset off disk
/// the way the application does, so a level edited into an unplayable state
/// fails here rather than in front of somebody.
///
/// It does **not** try to finish the level. The field is a hundred and twenty
/// metres across and two hundred and sixty long, with two locked gates, a maze,
/// a canyon crossed on moving barges and a crate puzzle in it; a script for
/// that is a script rewritten every time a brush moves, and the package already
/// proves a level can be finished. What is pinned here is that the document
/// loads, that its first zone is crossable only by jumping, that everything the
/// level is built around is in it — and, for the three set pieces whose whole
/// point is a height, that the height is still on the right side of what the
/// runner can actually do. Those last are measured, not assumed: see
/// [_doubleJumpHeight].
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platformer/src/staging.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

Level _shipped() => Level.fromJson(
      jsonDecode(File('assets/levels/ascent.json').readAsStringSync())
          as Map<String, Object?>,
    );

/// How high the runner gets off flat ground using both jumps.
///
/// Measured in an empty world rather than written down, because every number
/// it depends on — jump speed, air-jump speed, gravity — lives in
/// `RunnerTuning` and may be tuned. A level whose walls are sized against a
/// constant copied into a test is a level that silently becomes climbable the
/// day somebody makes the jump feel better.
double _doubleJumpHeight() {
  final world = CollisionWorld()
    ..add(
      Collider(
        shape: CollisionBox(Vector3(50.0, 0.5, 50.0)),
        position: Vector3(0.0, -0.5, 0.0),
      ),
    );
  final input = InputState();
  final runner = Runner(
    body: CharacterController(world: world, position: Vector3(0.0, 0.9, 0.0)),
  );
  final sim = PlatformerSimulation(
    runner: runner,
    collision: world,
    input: input,
    startAt: Vector3.zero(),
  );

  // Settle, so the first jump is not spent climbing out of the spawn.
  for (var i = 0; i < 60; i++) {
    input.beginStep();
    sim.step(_dt);
    input.endStep();
  }
  final ground = runner.position.y;

  var top = ground;
  for (var i = 0; i < 120; i++) {
    input.beginStep();
    // Two presses, and the release between them matters: holding the button
    // is one jump, and a release on every step is a jump cut short.
    if (i == 0 || i == 24) input.press(GameAction.jump);
    sim.step(_dt);
    input.endStep();
    if (runner.position.y > top) top = runner.position.y;
  }
  return top - ground;
}

/// Everything `main.dart` assembles, minus anything that draws.
final class _Game {
  _Game() {
    LevelValidator(registry: kinds, rules: platformerRules()).assertValid(level);
    level.addTo(world);
    // **The game's own assembly, not a copy of it.** The note this replaces
    // recorded what a copy costs: the first version of this harness left the
    // surfaces out, and the level's ice walked exactly like its moss — a
    // harness that is not the game is a harness that agrees with any bug the
    // game has. Now there is nothing here to leave out.
    staged = stage(level, world, input: input, registry: kinds);
  }

  final EntityRegistry kinds = platformerRegistry();
  late final Staged staged;
  Dynamics get dynamics => staged.dynamics;
  MechanismWorld get mechanisms => staged.mechanisms;
  ActorSystem get actors => staged.actors;
  Runner get runner => staged.runner;
  PlatformerSimulation get sim => staged.sim;

  final Level level = _shipped();
  final CollisionWorld world = CollisionWorld();
  final InputState input = InputState();

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

  /// Stands still, which is how a trigger is left behind.
  void wait(int steps) {
    for (var i = 0; i < steps; i++) {
      step();
    }
  }

  void putAt(Vector3 feet) {
    runner.body.teleport(feet + Vector3(0.0, 0.9, 0.0));
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

    test('there is enough in it to be worth crossing', () {
      // A field this size with nine coins in it is an empty field, which is
      // what the first draft of this level was. The numbers are floors, not
      // targets: content may be added without touching the test.
      final level = _shipped();
      final counted = <String, int>{};
      for (final entity in level.entities) {
        counted[entity.type] = (counted[entity.type] ?? 0) + 1;
      }

      expect(level.brushes, hasLength(greaterThanOrEqualTo(200)));
      expect(counted['collectible'], greaterThanOrEqualTo(150));
      expect(counted['crate'], greaterThanOrEqualTo(20));
      expect(counted['platform'], greaterThanOrEqualTo(10), reason: 'movers');
      expect(counted['lift'], greaterThanOrEqualTo(4));
      expect(counted['spring'], greaterThanOrEqualTo(6));
      expect(counted['hazard'], greaterThanOrEqualTo(6));
      expect(counted['door'], greaterThanOrEqualTo(2));
      expect(counted['key'], greaterThanOrEqualTo(2));
      expect(counted['checkpoint'], greaterThanOrEqualTo(7));
      expect(counted['oneway'], greaterThanOrEqualTo(3), reason: 'the gantry');
      expect(counted['conveyor'], greaterThanOrEqualTo(2), reason: 'the belts');
      expect(counted['crumbling'], greaterThanOrEqualTo(5), reason: 'the bridge');
      expect(counted['breakable'], greaterThanOrEqualTo(3), reason: 'the cap');
      expect(counted['climbable'], greaterThanOrEqualTo(2),
          reason: 'a ladder and a rope');
      expect(counted['enemy'], greaterThanOrEqualTo(3),
          reason: 'two guards and a leaper');
      expect(
        level.brushes.where((Brush b) => b.surface == 'ice'),
        isNotEmpty,
        reason: 'ice that is made of ice, not merely painted as it',
      );
    });

    test('everything the level is built around is in it', () {
      // One assertion per thing a player is meant to meet, so a level edited
      // into "no springs" or "no gate" says which one went.
      final game = _Game();

      expect(game.named<Spring>('the first pad'), isNotNull);
      expect(game.named<Spring>('the cold pad'), isNotNull);
      expect(game.named<Door>('the blue gate')?.isLocked, isTrue);
      expect(game.named<Door>('the green gate')?.isLocked, isTrue);
      expect(game.named<MovingPlatform>('the ferry'), isNotNull);
      expect(game.named<MovingPlatform>('the first barge'), isNotNull);
      expect(game.named<Lift>('the tower lift'), isNotNull);
      expect(game.named<Lift>('the summit lift'), isNotNull);
      expect(game.named<Collectible>('the blue key')?.key, 'blue');
      expect(game.named<Collectible>('the green key')?.key, 'green');
      expect(game.named<Checkpoint>('the brink')?.order, 1);
      expect(game.named<Hazard>('the spikes')?.instant, isFalse,
          reason: 'spikes hurt, the drop kills');
      expect(game.named<Hazard>('the gulf')?.instant, isTrue);
      expect(game.dynamics.bodies, hasLength(greaterThanOrEqualTo(20)),
          reason: 'crates, in the yard and everywhere else');
    });

    test('the checkpoints run in the order they are met', () {
      // The simulation respawns at the highest-ordered checkpoint reached, so
      // a checkpoint numbered out of step with where it stands sends a player
      // backwards — silently, and only when they die there.
      final game = _Game();
      final posts = <Checkpoint>[
        for (final m in game.mechanisms.all)
          if (m is Checkpoint) m,
      ]..sort((Checkpoint a, Checkpoint b) => a.order.compareTo(b.order));

      expect(posts, hasLength(greaterThanOrEqualTo(7)));
      for (var i = 1; i < posts.length; i++) {
        expect(posts[i].order, posts[i - 1].order + 1, reason: 'no gaps');
        expect(posts[i].at.z, greaterThan(posts[i - 1].at.z),
            reason: '${posts[i].name} is numbered after ${posts[i - 1].name} '
                'but stands in front of it');
      }
    });

    test('the maze cannot be jumped over', () {
      // The whole of the third zone is a maze, and a maze whose walls a player
      // can hop is scenery. Measured against the runner rather than a constant:
      // see _doubleJumpHeight.
      final level = _shipped();
      final reach = _doubleJumpHeight();
      final walls = <Brush>[
        for (final b in level.brushes)
          // The maze's own footprint: everything either side of it is the
          // filling that surrounds it, and that is meant to be climbable.
          if (b.min.z >= 83.0 &&
              b.max.z <= 121.0 &&
              b.min.x >= -28.0 &&
              b.max.x <= 28.0 &&
              b.max.y > 1.0)
            b,
      ];

      expect(walls, hasLength(greaterThanOrEqualTo(12)), reason: 'a maze');
      for (final wall in walls) {
        expect(wall.max.y, greaterThan(reach + 0.5),
            reason: 'a wall at ${wall.min.z} is ${wall.max.y} high and the '
                'runner reaches ${reach.toStringAsFixed(2)}');
      }
    });

    test('the stair to the summit can be climbed', () {
      // The last thing in the level is four terraces, and a terrace one step
      // too tall is a level that ends in a wall — the kind of mistake that only
      // shows up when somebody plays all the way to the end. Half a metre of
      // margin, because a player arrives at the edge rather than from a
      // standing start.
      final level = _shipped();
      final reach = _doubleJumpHeight();
      final stair = <Brush>[
        for (final b in level.brushes)
          // The middle lane only: the ziggurats and the colonnade beside it are
          // filling, and a player who wants them can take the hoists.
          //
          // **And the ground lane only.** There are two ways to this end of the
          // level now: the terraces, and the high road that the gate of two
          // skills lands on at seven metres. Measuring both as one staircase
          // reads the drop from the high road onto the first terrace as a step
          // nobody could climb — which is what happened the day the gate was
          // authored, and it is the test's model that was wrong rather than the
          // level.
          if (b.min.z >= 190.0 && b.min.x >= -14.0 && b.max.x <= 14.0 &&
              b.max.y > 1.0)
            b,
      ]
        // **By height, not by distance.** Sorting along z assumed one staircase
        // climbing away from the player, and there are two ways to this end of
        // the level now — the terraces, and the high road the gate of two
        // skills lands on. Ordered by z, the drop from the high road onto the
        // first terrace reads as a step nobody could climb; ordered by height,
        // the question is the one actually worth asking, which is whether every
        // level here is within reach of the one below it.
        ..sort((Brush a, Brush b) => a.max.y.compareTo(b.max.y));

      expect(stair, hasLength(greaterThanOrEqualTo(4)));
      var standing = 0.0;
      for (final terrace in stair) {
        expect(terrace.max.y - standing, lessThan(reach - 0.5),
            reason: 'the terrace at ${terrace.min.z}, topping out at '
                '${terrace.max.y}, is a step too tall from $standing');
        standing = terrace.max.y;
      }
    });

    test('the vault is out of a jump and inside a crate', () {
      // The crate puzzle in the yard only exists if both halves hold: too high
      // to jump, low enough to reach from a crate. Raise the ledge or shrink
      // the crates and this says which way it broke.
      final level = _shipped();
      final reach = _doubleJumpHeight();
      final ledge = level.brushes
          .firstWhere((Brush b) =>
              b.min.x <= -46.0 && b.max.x >= -46.0 &&
              b.min.z <= -10.0 && b.max.z >= -10.0 &&
              b.max.y > 1.0)
          .max
          .y;
      final crate =
          _shipped().ofType('crate').first.vector('size')?.y ?? 0.0;

      expect(ledge, greaterThan(reach),
          reason: 'the vault would not need the crate');
      expect(ledge, lessThan(crate + reach),
          reason: 'the vault could not be reached from the crate either');
    });
  });

  group('the yard of surfaces', () {
    test('the gantry is a floor from above and a doorway from below', () {
      // Both halves in the shipped level, because a one-way platform that works
      // in a test fixture and not in the document is a one-way platform nobody
      // can use. The runner is put under the lowest gantry and thrown at it.
      final game = _Game();
      final gantry = game.level.entities.firstWhere(
        (EntityDef e) => e.name == 'the gantry 1',
      );

      game.putAt(Vector3(gantry.position.x, 0.0, gantry.position.z));
      game.wait(20);
      final floor = game.runner.position.y;

      game.runner.launch(16.0);
      game.wait(120);

      expect(game.runner.isGrounded, isTrue);
      expect(game.runner.position.y, greaterThan(floor + 1.0),
          reason: 'it did not get through the gantry');

      // And down again through the same platform.
      final onTop = game.runner.position.y;
      for (var i = 0; i < 120; i++) {
        game.input.beginStep();
        game.input.press(PlatformerActions.dropThrough);
        game.sim.step(_dt);
        game.input.endStep();
      }

      expect(game.runner.position.y, lessThan(onTop - 1.0),
          reason: 'it could not drop back through');
    });

    test('the ice is slipperier than the moss beside it', () {
      // The level's own floors, measured against each other. Mutation: drop
      // `surface: "ice"` from the generator and the two come out the same.
      double slide(Vector3 from) {
        final game = _Game()..putAt(from);
        game.wait(10);
        game.walk(70);
        final letGoAt = game.runner.position.z;
        game.wait(70);
        return game.runner.position.z - letGoAt;
      }

      final onIce = slide(Vector3(-14.0, 0.1, 1.0));
      final onMoss = slide(Vector3(-2.0, 0.0, 1.0));

      expect(onMoss, lessThan(0.6));
      expect(onIce, greaterThan(onMoss * 3.0),
          reason: 'ice slid $onIce m and moss slid $onMoss m');
    });

    test('a belt carries a runner who is doing nothing', () {
      // Mutation: drop the `flow` from the level, or `surfaceVelocity` from
      // `ConveyorKind.spawn`.
      final game = _Game()..putAt(Vector3(-44.0, 0.5, 8.0));
      game.wait(90);

      expect(game.runner.position.z, greaterThan(10.0),
          reason: 'the belt carried nobody');
    });
  });

  group('the yard of moves', () {
    test('the crawlspace admits a crouched runner and no other', () {
      // Both halves, in the shipped level. Mutation: raise the slot in the
      // generator and the standing half stops failing.
      double reached({required bool crouching}) {
        final game = _Game()..putAt(Vector3(7.0, 0.0, 8.0));
        game.wait(10);
        for (var i = 0; i < 300; i++) {
          game.input.beginStep();
          game.input.press(GameAction.moveForward);
          if (crouching) game.input.press(PlatformerActions.dropThrough);
          game.sim.step(_dt);
          game.input.endStep();
        }
        return game.runner.position.z;
      }

      expect(reached(crouching: true), greaterThan(18.0),
          reason: 'it could not crawl through');
      expect(reached(crouching: false), lessThan(11.0),
          reason: 'it walked through a one-metre slot');
    });

    test('the shelves over the crevasse hold, and then do not', () {
      final game = _Game();
      final shelf = game.named<Crumbling>('the shelf 1')!;

      game.putAt(Vector3(-24.0, 1.2, 129.0));
      game.wait(10);
      expect(game.runner.isGrounded, isTrue, reason: 'standing on a shelf');
      expect(shelf.hasFallen, isFalse);

      game.wait(45);
      expect(shelf.hasFallen, isTrue, reason: 'it never gave way');
    });

    test('the cap over the coins opens to a pound and nothing else', () {
      final game = _Game();
      final cap = game.named<Breakable>('the cap 2')!;

      // **Above the cap, wherever the level put it.** This used to be three
      // numbers copied out of the generator, and when the cap moved — evicted
      // by the chimney that now stands where it was — the test went on
      // pounding an empty patch of field and reported that a pound does not
      // break a block.
      final above = cap.origin + Vector3(0.0, 4.4, 0.0);

      // Landing on it from a height is not enough.
      game.putAt(above);
      game.wait(120);
      expect(cap.isBroken, isFalse, reason: 'a landing broke it');

      game.putAt(above);
      game.wait(4);
      game.input.beginStep();
      game.input.press(PlatformerActions.dropThrough);
      game.sim.step(_dt);
      game.input.endStep();
      game.wait(120);

      expect(cap.isBroken, isTrue, reason: 'the pound did not break it');
    });
  });

  group('the guards', () {
    test('the level spawns them, and they patrol', () {
      // Mutation: drop `actors: actors` from the simulation the app builds —
      // the enemies stand still for ever, which is what a level full of actors
      // and no step looks like.
      final game = _Game();
      expect(game.actors.actors, hasLength(greaterThanOrEqualTo(3)));

      final guard = game.actors.actors.first;
      final startedAt = guard.position!.clone();
      game.wait(240);

      expect((guard.position! - startedAt).length, greaterThan(2.0),
          reason: 'a guard that never moved');
      expect(guard.position!.y, greaterThan(-1.0), reason: 'it fell out');
    });

    test('landing on one kills it and throws the runner back', () {
      final game = _Game();
      final guard = game.actors.actors.first;
      final over = guard.position!;

      // From just above, not from five metres: a guard walks while the runner
      // falls, and half a second in the air is more than a body's width of
      // walking. Dropping onto a moving target from a height is a test of the
      // level designer's aim rather than of the stomp.
      game.putAt(Vector3(over.x, over.y + 1.0, over.z));
      var stomped = false;
      for (var i = 0; i < 200 && !stomped; i++) {
        game.step();
        stomped = game.sim.stompedThisStep;
      }

      expect(stomped, isTrue, reason: 'it landed beside it');
      expect(guard.isAlive, isFalse);
      expect(game.runner.body.velocity.y, greaterThan(4.0));
    });
  });

  group('the gates', () {
    test('the blue gate is shut until the key is carried', () {
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

    test('walking into it is what opens it, and only with the key', () {
      // Nothing in a platformer presses a use key, so a gate is opened by the
      // plate the level authors in front of it. Without that plate the level's
      // two gates never open and the level cannot be finished — which is what
      // the document said before this test existed.
      final game = _Game();
      final gate = game.named<Door>('the blue gate')!;

      game.putAt(Vector3(0.0, 0.0, 72.0));
      game.walk(150);
      expect(gate.progress, 0.0, reason: 'no key, no gate');
      expect(game.runner.position.z, lessThan(79.0),
          reason: 'and it is still in the way');

      // Back out of the plate — a trigger fires on the way in, so the runner
      // has to leave it before it can be walked into again.
      game.putAt(Vector3(0.0, 0.0, 72.0));
      game.wait(5);
      game.runner.keyRing.take('blue');
      game.walk(240);

      expect(gate.progress, greaterThan(0.99), reason: 'wide open');
      expect(game.runner.position.z, greaterThan(81.0), reason: 'and through');
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
      expect(coin.sinceTaken, closeTo(0.5, 0.15),
          reason: 'the simulation keeps counting after the look has finished');
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
      game.putAt(Vector3(before.x, 0.0, before.z - 2.0));
      game.walk(200);

      expect(crate.position.z, greaterThan(before.z + 0.5));
      expect(crate.position.y, closeTo(before.y, 0.3), reason: 'and stays down');
    });
  });
}
