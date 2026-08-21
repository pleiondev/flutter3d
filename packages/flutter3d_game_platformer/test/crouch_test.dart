/// The verbs that need the body to be a different size or a different mode.
///
///     flutter test test/crouch_test.dart
///
/// Crouch, slide, long jump, ground pound, ladders and ropes. Four of them are
/// one key — the same one that drops through a platform — and which verb it
/// means is decided by where the runner is and how fast it is going, because a
/// platformer that spends four keys on four downward ideas has four keys spare
/// and nothing to bind to them.
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;
const GameAction _crouch = PlatformerActions.dropThrough;

final class _Run {
  _Run({List<EntityDef> extras = const <EntityDef>[], List<Brush> walls = const <Brush>[]}) {
    final level = Level(
      name: 'a room',
      materials: <String, LevelMaterial>{'rock': LevelMaterial()},
      brushes: <Brush>[
        Brush(
          centre: Vector3(0.0, -0.5, 0.0),
          size: Vector3(80.0, 1.0, 80.0),
          material: 'rock',
        ),
        ...walls,
      ],
      entities: <EntityDef>[
        EntityDef(type: EntityTypes.playerSpawn, position: Vector3.zero()),
        ...extras,
      ],
    );

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

  final CollisionWorld world = CollisionWorld();
  final InputState input = InputState();
  late final MechanismWorld mechanisms;
  late final Runner runner;
  late final PlatformerSimulation sim;

  final Set<GameAction> _held = <GameAction>{};

  void step({Set<GameAction> holding = const <GameAction>{}}) {
    input.beginStep();
    for (final action in holding.difference(_held)) {
      input.press(action);
    }
    for (final action in _held.difference(holding)) {
      input.release(action);
    }
    _held
      ..clear()
      ..addAll(holding);
    sim.step(_dt);
    input.endStep();
  }

  void run(int steps, {Set<GameAction> holding = const <GameAction>{}}) {
    for (var i = 0; i < steps; i++) {
      step(holding: holding);
    }
  }

  double get feet => runner.position.y - runner.body.halfExtents.y;
  double get z => runner.position.z;
}

/// A roof a standing runner does not fit under and a crouched one does.
Brush _lowRoof({double z = 6.0}) => Brush(
      centre: Vector3(0.0, 1.6, z),
      size: Vector3(8.0, 0.6, 6.0),
      material: 'rock',
    );

void main() {
  group('crouching', () {
    test('makes the body short, and standing up makes it tall again', () {
      // Mutation: ignore `tryResize`'s answer and assign the shape anyway. The
      // second half still passes and the roof test below stops failing.
      final run = _Run()..run(20);
      final tall = run.runner.body.halfExtents.y;

      run.run(10, holding: <GameAction>{_crouch});
      expect(run.runner.isCrouching, isTrue);
      expect(run.runner.body.halfExtents.y, lessThan(tall * 0.7));

      run.run(10);
      expect(run.runner.isCrouching, isFalse);
      expect(run.runner.body.halfExtents.y, closeTo(tall, 1e-6));
    });

    test('the feet stay where they were', () {
      // Mutation: resize about the centre. The runner sinks into the floor and
      // is depenetrated back out, which reads as a crouch that bounces.
      final run = _Run()..run(20);
      final onFloor = run.feet;

      run.run(10, holding: <GameAction>{_crouch});
      expect(run.feet, closeTo(onFloor, 0.02));
    });

    test('a crawlspace is crossable crouched and not standing', () {
      // Both halves, because the first without the second proves nothing about
      // the roof.
      final crawled = _Run(walls: <Brush>[_lowRoof()]);
      // Three hundred steps, because a crouch walks at 2.4 m/s and the roof is
      // six metres deep: at a hundred and sixty it was still under it.
      crawled.run(300, holding: <GameAction>{_crouch, GameAction.moveForward});
      expect(crawled.z, greaterThan(9.0), reason: 'it did not get through');

      final blocked = _Run(walls: <Brush>[_lowRoof()]);
      blocked.run(300, holding: <GameAction>{GameAction.moveForward});
      expect(blocked.z, lessThan(4.0), reason: 'it walked through a roof');
    });

    test('and standing up under the roof is refused until there is room', () {
      // Mutation: delete the overlap check in `tryResize`. The runner stands up
      // inside the ceiling and is fired sideways out of it.
      final run = _Run(walls: <Brush>[_lowRoof()]);
      run.run(120, holding: <GameAction>{_crouch, GameAction.moveForward});
      final underIt = run.z;
      expect(underIt, greaterThan(4.0), reason: 'it should be under the roof');

      // Let go of crouch while still under it.
      run.run(30);
      expect(run.runner.isCrouching, isTrue, reason: 'there is a roof overhead');

      run.run(120, holding: <GameAction>{GameAction.moveForward});
      expect(run.runner.isCrouching, isFalse, reason: 'it is clear now');
    });
  });

  group('sliding', () {
    test('a crouch at speed is a slide, and covers ground a crouch does not',
        () {
      // Mutation: drop the speed threshold — every crouch becomes a slide, and
      // the pair below stops differing.
      double travelled({required bool running}) {
        final run = _Run();
        if (running) run.run(60, holding: <GameAction>{GameAction.moveForward});
        final from = run.z;
        // Straight from running into the crouch: five steps of standing still
        // first is five steps of friction, which takes six metres a second down
        // to under the threshold and turns the slide back into a crouch.
        run.run(60, holding: <GameAction>{_crouch});
        return run.z - from;
      }

      final fromStanding = travelled(running: false);
      final fromRunning = travelled(running: true);

      expect(fromRunning, greaterThan(fromStanding + 2.0));
    });

    test('it says so on the step it starts', () {
      final run = _Run()..run(60, holding: <GameAction>{GameAction.moveForward});
      expect(run.runner.slidThisStep, isFalse);

      run.step(holding: <GameAction>{GameAction.moveForward, _crouch});
      expect(run.runner.slidThisStep, isTrue);
      expect(run.runner.isSliding, isTrue);

      run.run(60, holding: <GameAction>{_crouch});
      expect(run.runner.isSliding, isFalse, reason: 'it does not last for ever');
    });

    test('a jump out of a slide goes further than a jump does', () {
      // The reason the long jump is worth learning: it is not a better jump,
      // it is a flatter one that crosses more ground.
      //
      // Mutation: drop the `_sliding > 0.0` branch from `_tryJump`.
      double jumped({required bool sliding}) {
        final run = _Run()..run(60, holding: <GameAction>{GameAction.moveForward});
        final from = run.z;
        if (sliding) {
          run.step(holding: <GameAction>{GameAction.moveForward, _crouch});
          run.step(holding: <GameAction>{GameAction.moveForward, _crouch, GameAction.jump});
        } else {
          run.step(holding: <GameAction>{GameAction.moveForward, GameAction.jump});
        }
        run.run(90, holding: <GameAction>{GameAction.moveForward});
        return run.z - from;
      }

      final plain = jumped(sliding: false);
      final long = jumped(sliding: true);

      expect(long, greaterThan(plain + 1.5),
          reason: 'the long jump went $long m and a plain one went $plain m');
    });
  });

  group('the ground pound', () {
    test('drives the runner down faster than gravity does', () {
      // Mutation: make the pound set velocity to zero instead of downwards —
      // it becomes a hover, which is the opposite of the verb.
      double fellIn(int steps, {required bool pounding}) {
        final run = _Run();
        run.runner.body.teleport(Vector3(0.0, 20.0, 0.0));
        run.run(10);
        final from = run.runner.position.y;
        if (pounding) run.step(holding: <GameAction>{_crouch});
        run.run(steps);
        return from - run.runner.position.y;
      }

      expect(fellIn(15, pounding: true), greaterThan(fellIn(15, pounding: false) * 1.5));
    });

    test('and says so on the step it lands', () {
      final run = _Run();
      run.runner.body.teleport(Vector3(0.0, 12.0, 0.0));
      run.run(5);
      run.step(holding: <GameAction>{_crouch});
      expect(run.runner.isPounding, isTrue);

      var landed = false;
      for (var i = 0; i < 120 && !landed; i++) {
        run.step();
        landed = run.runner.poundedThisStep;
      }

      expect(landed, isTrue, reason: 'it never reported landing');
      expect(run.runner.isPounding, isFalse);
    });

    test('and a spring is not a jump to cut short', () {
      // **A promise about height.** `Launchable.launch` says a spring is "a
      // promise about height — the level author placed it to reach a particular
      // ledge", and jump is held almost constantly in a platformer. Running
      // onto a pad with it down and letting go in the air multiplied the throw
      // by `jumpCut` and fell short of the ledge the level was built around.
      final run = _Run();
      run.step(holding: <GameAction>{GameAction.jump});
      run.runner.launch(15.0);
      expect(run.runner.body.velocity.y, closeTo(15.0, 1e-6));

      // Let go, mid-flight, exactly as a player holding jump would.
      run.step();

      expect(run.runner.body.velocity.y, greaterThan(12.0),
          reason: 'the spring was cut to jump height');
    });

    test('and a jump still is', () {
      // The other half, or the fix is "never cut anything" and passes.
      final run = _Run();
      run.step(holding: <GameAction>{GameAction.jump});
      final rising = run.runner.body.velocity.y;
      expect(rising, greaterThan(0.0), reason: 'it never left the ground');

      run.step();

      expect(run.runner.body.velocity.y, lessThan(rising * 0.6),
          reason: 'releasing jump no longer shortens a jump');
    });

    test('and dying in one does not carry it into the next life', () {
      // **A pound ends when the runner is out of it, and dying is out of it.**
      // `_pounding` was cleared only by landing, and dying mid-pound is the
      // ordinary way a pound kills you — into a hazard, or past the kill plane.
      // So the flag survived the respawn, and the first *ordinary* landing
      // after it reported a pound: the slam particles, the camera shake, and
      // `PlatformerSimulation` shattering whatever `Breakable` happened to be
      // under the checkpoint.
      final run = _Run();
      run.runner.body.teleport(Vector3(0.0, 12.0, 0.0));
      run.run(5);
      run.step(holding: <GameAction>{_crouch});
      expect(run.runner.isPounding, isTrue, reason: 'it never started');

      run.runner.reviveAt(Vector3(0.0, 0.0, 0.0));
      expect(run.runner.isPounding, isFalse,
          reason: 'the pound came back to life with the runner');

      var landed = false;
      for (var i = 0; i < 120 && !landed; i++) {
        run.step();
        landed = run.runner.poundedThisStep;
      }
      expect(landed, isFalse,
          reason: 'an ordinary landing after a respawn reported a pound');
    });

    test('and dashing out of one ends it too', () {
      // The other exit. Dashing zeroed the vertical speed and left the flag up,
      // so the landing at the end of the dash was a pound the player did not
      // make.
      final run = _Run();
      run.runner.body.teleport(Vector3(0.0, 12.0, 0.0));
      run.run(5);
      run.step(holding: <GameAction>{_crouch});
      expect(run.runner.isPounding, isTrue);

      run.step(holding: <GameAction>{PlatformerActions.dash});

      expect(run.runner.isPounding, isFalse);
    });

    test('a landing reports how hard it was', () {
      // The number E3's dust and squash are fed from, and the reason it is read
      // before the step: landing is where the controller turns downward speed
      // into zero.
      //
      // Mutation: read the speed after `body.step` — every landing arrives at
      // nought.
      double landingFrom(double height) {
        final run = _Run();
        run.runner.body.teleport(Vector3(0.0, height, 0.0));
        for (var i = 0; i < 300; i++) {
          run.step();
          if (run.runner.landedThisStep) return run.runner.landingSpeed;
        }
        return -1.0;
      }

      final small = landingFrom(2.0);
      final big = landingFrom(20.0);

      expect(small, greaterThan(0.0));
      expect(big, greaterThan(small * 2.0));
    });

    test('breaks a block, and only a block that was under it', () {
      // Mutation: break whatever is nearest rather than what is underfoot — a
      // pound nobody can aim.
      final run = _Run(extras: <EntityDef>[
        EntityDef(
          type: PlatformerEntities.breakable,
          name: 'the block',
          position: Vector3(0.0, 1.0, 0.0),
          properties: <String, Object?>{
            'size': <double>[2.0, 2.0, 2.0],
          },
        ),
        EntityDef(
          type: PlatformerEntities.breakable,
          name: 'the other block',
          position: Vector3(3.0, 1.0, 0.0),
          properties: <String, Object?>{
            'size': <double>[2.0, 2.0, 2.0],
          },
        ),
      ]);
      final block = run.mechanisms['the block']! as Breakable;
      final other = run.mechanisms['the other block']! as Breakable;

      run.runner.body.teleport(Vector3(0.0, 8.0, 0.0));
      run.run(5);
      run.step(holding: <GameAction>{_crouch});
      run.run(120);

      expect(block.isBroken, isTrue, reason: 'the pound did not break it');
      expect(other.isBroken, isFalse, reason: 'it broke the one beside it too');
    });

    test('and an ordinary landing does not break it', () {
      final run = _Run(extras: <EntityDef>[
        EntityDef(
          type: PlatformerEntities.breakable,
          name: 'the block',
          position: Vector3(0.0, 1.0, 0.0),
          properties: <String, Object?>{
            'size': <double>[2.0, 2.0, 2.0],
          },
        ),
      ]);
      final block = run.mechanisms['the block']! as Breakable;

      run.runner.body.teleport(Vector3(0.0, 8.0, 0.0));
      run.run(180);

      expect(block.isBroken, isFalse);
    });

    test('and a checkpoint taken before the pound puts the block back', () {
      // **Restoring only ever took the collider away, never gave it back.**
      // Load a save written before the block broke, in a session where it
      // since had, and `isBroken` said "solid" while the world had no collider
      // in it — and nothing un-breaks a block, so there was no later step that
      // could put it right. A wall the player can see and walk through.
      final run = _Run(extras: <EntityDef>[
        EntityDef(
          type: PlatformerEntities.breakable,
          name: 'the block',
          position: Vector3(0.0, 1.0, 0.0),
          properties: <String, Object?>{
            'size': <double>[2.0, 2.0, 2.0],
          },
        ),
      ]);
      final block = run.mechanisms['the block']! as Breakable;
      final whole = block.save();

      run.runner.body.teleport(Vector3(0.0, 8.0, 0.0));
      run.run(5);
      run.step(holding: <GameAction>{_crouch});
      run.run(120);
      expect(block.isBroken, isTrue, reason: 'the pound did not break it');

      block.restore(whole);
      run.runner.body.teleport(Vector3(0.0, 4.0, 0.0));
      run.run(60);

      expect(block.isBroken, isFalse);
      // Height rather than `isGrounded`, because there is a floor under the
      // block and landing on *that* is grounded too — the first draft of this
      // test passed with the collider still missing. The block's top is at two
      // metres; the floor is at nothing.
      expect(run.runner.position.y, greaterThan(1.5),
          reason: 'the block is back, and the runner fell through it');
    });
  });

  group('a crumbling platform', () {
    EntityDef aShelf() => EntityDef(
          type: PlatformerEntities.crumbling,
          name: 'the shelf',
          position: Vector3(0.0, 3.0, 0.0),
          properties: <String, Object?>{
            'size': <double>[4.0, 0.4, 4.0],
            'delay': 0.4,
            'gone': 1.0,
          },
        );

    test('holds, then gives way under whoever is standing on it', () {
      // Mutation: count the timer from the level's start rather than from the
      // first footfall. Every shelf in the level falls at once, moments after
      // the player spawns, and none of them is ever there when they arrive.
      final run = _Run(extras: <EntityDef>[aShelf()]);
      final theShelf = run.mechanisms['the shelf']! as Crumbling;

      run.runner.body.teleport(Vector3(0.0, 4.2, 0.0));
      run.run(10);
      expect(run.runner.isGrounded, isTrue, reason: 'standing on the shelf');
      expect(theShelf.hasFallen, isFalse, reason: 'it went immediately');

      run.run(40);
      expect(theShelf.hasFallen, isTrue, reason: 'it never gave way');
      expect(run.runner.position.y, lessThan(3.0), reason: 'it is falling');
    });

    test('and comes back', () {
      final run = _Run(extras: <EntityDef>[aShelf()]);
      final theShelf = run.mechanisms['the shelf']! as Crumbling;

      run.runner.body.teleport(Vector3(0.0, 4.2, 0.0));
      run.run(60);
      expect(theShelf.hasFallen, isTrue);

      run.run(90);
      expect(theShelf.hasFallen, isFalse, reason: 'it never came back');
    });

    test('and a checkpoint taken before it fell puts it back', () {
      // The same hole as the block above, and the reason it is worth testing
      // twice: a shelf that comes back on its own hides it for a second and a
      // half, and then does not.
      final run = _Run(extras: <EntityDef>[aShelf()]);
      final theShelf = run.mechanisms['the shelf']! as Crumbling;
      final standing = theShelf.save();

      run.runner.body.teleport(Vector3(0.0, 4.2, 0.0));
      run.run(60);
      expect(theShelf.hasFallen, isTrue, reason: 'it never gave way');

      theShelf.restore(standing);
      run.runner.body.teleport(Vector3(0.0, 4.2, 0.0));
      run.run(10);

      expect(theShelf.hasFallen, isFalse);
      expect(run.runner.isGrounded, isTrue,
          reason: 'restored standing, and the runner fell through it');
    });

    test('a platform nobody stood on never falls', () {
      final run = _Run(extras: <EntityDef>[aShelf()]);
      final theShelf = run.mechanisms['the shelf']! as Crumbling;

      run.run(300);

      expect(theShelf.hasFallen, isFalse);
    });
  });

  group('a hazard', () {
    test('hurts for as long as you stand in it', () {
      // **The first test this mechanism has ever had.** It has been in the
      // engine since the platformer began, it kills the player in the shipped
      // level, and nothing asserted that it does anything at all.
      //
      // Mutation: make `damagePerSecond` a per-touch figure — the damage stops
      // depending on how long, and standing in lava becomes survivable.
      final run = _Run(extras: <EntityDef>[
        EntityDef(
          type: PlatformerEntities.hazard,
          name: 'the spikes',
          position: Vector3(0.0, 0.4, 0.0),
          properties: <String, Object?>{
            'size': <double>[6.0, 0.8, 6.0],
            'damage': 30.0,
          },
        ),
      ]);

      run.run(30);
      final afterHalfASecond = run.runner.health.current;
      run.run(60);
      final afterOneMore = run.runner.health.current;

      expect(afterHalfASecond, lessThan(100.0), reason: 'it did nothing');
      expect(afterOneMore, lessThan(afterHalfASecond - 20.0),
          reason: 'standing in it longer cost no more');
    });

    test('an instant one kills whatever its damage number says', () {
      final run = _Run(extras: <EntityDef>[
        EntityDef(
          type: PlatformerEntities.hazard,
          name: 'the pit',
          position: Vector3(0.0, 0.4, 0.0),
          properties: <String, Object?>{
            'size': <double>[6.0, 0.8, 6.0],
            'instant': true,
          },
        ),
      ]);

      run.run(5);
      expect(run.runner.health.isAlive, isFalse);
      expect(run.sim.deaths, greaterThan(0));
    });

    test('a saw rides the mover it names', () {
      // Mutation: drop `_ride()` from `Hazard.step`. The saw stays where the
      // document drew it and the arm swings out from under it — which looks
      // like the saw working right up until somebody walks under the arm.
      final run = _Run(extras: <EntityDef>[
        EntityDef(
          type: EntityTypes.platform,
          name: 'the arm',
          position: Vector3(0.0, 3.0, 10.0),
          properties: <String, Object?>{
            'size': <double>[2.0, 0.4, 2.0],
            'travel': <double>[10.0, 0.0, 0.0],
            'speed': 4.0,
            'wait': 0.0,
          },
        ),
        EntityDef(
          type: PlatformerEntities.hazard,
          name: 'the saw',
          position: Vector3(0.0, 4.0, 10.0),
          properties: <String, Object?>{
            'size': <double>[1.6, 1.6, 1.6],
            'damage': 60.0,
            'follows': 'the arm',
          },
        ),
      ]);
      final saw = run.mechanisms['the saw']! as Hazard;
      final arm = run.mechanisms['the arm']! as MovingPlatform;
      final startedAt = saw.origin.x;

      run.run(60);

      expect(arm.collider.position.x, greaterThan(1.0), reason: 'the arm moved');
      expect(saw.origin.x, greaterThan(startedAt + 1.0),
          reason: 'the saw stayed behind');
      // And it keeps the metre it was authored above the arm.
      expect(saw.origin.y - arm.collider.position.y, closeTo(1.0, 0.01));
    });
  });

  group('a ladder', () {
    EntityDef ladder({double swing = 0.0}) => EntityDef(
          type: PlatformerEntities.climbable,
          name: 'the ladder',
          position: Vector3(0.0, 4.0, 6.0),
          properties: <String, Object?>{
            'size': <double>[1.2, 8.0, 1.2],
            'swing': swing,
            'period': 2.0,
          },
        );

    test('is climbed by walking into it and holding forward', () {
      // Mutation: leave the climb out of `Runner.step` and let gravity have it.
      // The runner walks into a trigger volume and falls past it.
      final run = _Run(extras: <EntityDef>[ladder()]);
      run.runner.body.teleport(Vector3(0.0, 0.9, 5.0));
      run.run(120, holding: <GameAction>{GameAction.moveForward});

      expect(run.runner.climbing, isNotNull, reason: 'it never took hold');
      expect(run.runner.position.y, greaterThan(3.0), reason: 'it did not climb');
    });

    test('and it lets go at the top rather than climbing into the sky', () {
      final run = _Run(extras: <EntityDef>[ladder()]);
      run.runner.body.teleport(Vector3(0.0, 0.9, 5.0));
      run.run(400, holding: <GameAction>{GameAction.moveForward});

      expect(run.runner.position.y, lessThan(9.0));
    });

    test('a jump leaves it', () {
      final run = _Run(extras: <EntityDef>[ladder()]);
      run.runner.body.teleport(Vector3(0.0, 0.9, 5.0));
      run.run(60, holding: <GameAction>{GameAction.moveForward});
      expect(run.runner.climbing, isNotNull);

      run.step(holding: <GameAction>{GameAction.jump});
      expect(run.runner.climbing, isNull, reason: 'it is still holding on');
      expect(run.runner.body.velocity.y, greaterThan(0.0));
    });

    test('a rope carries whoever is on it', () {
      // The whole of rope physics a platformer needs: the volume swings and the
      // climber is written from it.
      //
      // Mutation: drop `collider.moveTo(_at)` from `Climbable.step`, or write
      // only the climber's height and leave its x alone.
      final run = _Run(extras: <EntityDef>[ladder(swing: 3.0)]);
      run.runner.body.teleport(Vector3(0.0, 0.9, 5.0));
      run.run(30, holding: <GameAction>{GameAction.moveForward});
      expect(run.runner.climbing, isNotNull);

      var leftmost = run.runner.position.x;
      var rightmost = run.runner.position.x;
      for (var i = 0; i < 120; i++) {
        run.step();
        leftmost = leftmost < run.runner.position.x ? leftmost : run.runner.position.x;
        rightmost = rightmost > run.runner.position.x ? rightmost : run.runner.position.x;
      }

      expect(rightmost - leftmost, greaterThan(3.0),
          reason: 'the rope swung and the climber did not');
    });
  });
}
