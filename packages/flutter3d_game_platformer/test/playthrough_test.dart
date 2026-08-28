/// The whole of SPEC stage 5's acceptance, as a test: a game that is not a
/// shooter, played to its exit, with nothing rendered and nothing mocked.
///
/// The level is built in code rather than loaded from an asset because what is
/// under test is the machinery, not a document — and a level a test can adjust
/// by one number is a level that can be made to prove one thing at a time.
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

/// A run along +Z: ground, a gap to clear, a ledge only two jumps reach, and
/// the exit on top of it.
Level _level() => Level(
  name: 'first steps',
  materials: <String, LevelMaterial>{'rock': LevelMaterial()},
  brushes: <Brush>[
    // The starting ground, z from -1 to 6.
    Brush(
      centre: Vector3(0.0, -0.5, 2.5),
      size: Vector3(6.0, 1.0, 7.0),
      material: 'rock',
    ),
    // The far side, z from 9 to 17.
    Brush(
      centre: Vector3(0.0, -0.5, 13.0),
      size: Vector3(6.0, 1.0, 8.0),
      material: 'rock',
    ),
    // The ledge, z from 17 to 21, its top at y = 2.4 — above one jump's
    // 1.88 m and under two. See the assertions in 'jumping'.
    Brush(
      centre: Vector3(0.0, 1.2, 19.0),
      size: Vector3(6.0, 2.4, 4.0),
      material: 'rock',
    ),
  ],
  lights: <LevelLight>[
    LevelLight(position: Vector3(0.0, 6.0, 8.0), intensity: 20.0, range: 40.0),
  ],
  entities: <EntityDef>[
    EntityDef(type: EntityTypes.playerSpawn, position: Vector3(0.0, 0.0, 0.0)),
    EntityDef(
      type: PlatformerEntities.collectible,
      name: 'first coin',
      position: Vector3(0.0, 1.0, 4.0),
      properties: <String, Object?>{'what': 'coin'},
    ),
    EntityDef(
      type: PlatformerEntities.checkpoint,
      name: 'before the gap',
      position: Vector3(0.0, 1.0, 5.0),
      properties: <String, Object?>{
        'order': 1,
        'respawn': <double>[0.0, 1.0, 4.5],
      },
    ),
    // In the gap, wide and deep: falling in is the failure this level is
    // about, so it kills rather than nibbling.
    EntityDef(
      type: PlatformerEntities.hazard,
      name: 'the pit',
      position: Vector3(0.0, -2.0, 7.5),
      properties: <String, Object?>{
        'size': <double>[6.0, 4.0, 3.0],
        'instant': true,
      },
    ),
    EntityDef(
      type: EntityTypes.exit,
      name: 'the way on',
      position: Vector3(0.0, 3.4, 19.0),
      properties: <String, Object?>{'next': 'second steps'},
    ),
  ],
);

/// Everything the application would assemble, minus anything that draws.
final class _Run {
  _Run() {
    LevelValidator(
      registry: platformerRegistry(),
      rules: platformerRules(),
    ).assertValid(level);

    level.addTo(world);
    mechanisms = MechanismWorld(world);
    level.spawnInto(
      SpawnContext(world: world, actors: actors, mechanisms: mechanisms),
      registry: platformerRegistry(),
    );

    final start = level.playerStart?.position ?? Vector3.zero();
    runner = Runner(
      body: CharacterController(
        world: world,
        // The authored point is where the feet go; the body is a box centred
        // on its middle. The dungeon's application does the same sum.
        position: start + Vector3(0.0, 0.9, 0.0),
        tuning: const MovementTuning(),
      ),
    );
    sim = PlatformerSimulation(
      runner: runner,
      collision: world,
      input: input,
      startAt: start,
      mechanisms: mechanisms,
      random: GameRandom(1),
    );
  }

  final Level level = _level();
  final CollisionWorld world = CollisionWorld();
  final InputState input = InputState();
  late final ActorSystem actors = ActorSystem(
    world: world,
    random: GameRandom(1),
  );
  late final MechanismWorld mechanisms;
  late final Runner runner;
  late final PlatformerSimulation sim;

  late final double _floorY = runner.position.y;
  bool _forwardHeld = false;
  bool _jumpHeld = false;

  /// One step, with whatever is being held this step.
  ///
  /// **Presses and releases only on the edges, the way a keyboard does.** The
  /// first version of this called `release` on every step the button was not
  /// wanted, which fires the release edge sixty times a second — and the
  /// release edge is what cuts a jump short. Every jump in this file was
  /// therefore a tapped jump, the double-jump test landed before it could take
  /// its second, and the level could not be finished. A harness that does not
  /// behave like a device is a harness that tests itself.
  void step({bool forward = false, bool jump = false, bool dash = false}) {
    input.beginStep();
    _hold(GameAction.moveForward, forward, _forwardHeld);
    _forwardHeld = forward;
    _hold(GameAction.jump, jump, _jumpHeld);
    _jumpHeld = jump;
    if (dash) input.press(PlatformerActions.dash);
    sim.step(_dt);
    input.endStep();
    if (dash) input.release(PlatformerActions.dash);
    final above = runner.position.y - _floorY;
    if (above > _rise) _rise = above;
  }

  void _hold(GameAction action, bool wanted, bool was) {
    if (wanted == was) return;
    if (wanted) {
      input.press(action);
    } else {
      input.release(action);
    }
  }

  /// Runs forward, jumping whenever [jumpAt] says to, for at most [steps].
  ///
  /// A predicate rather than a list of step numbers: a script keyed to frame
  /// counts passes until somebody changes a tuning value by five per cent, and
  /// then fails in a way that says nothing about what broke.
  void run(
    int steps, {
    bool Function(_Run run)? jumpAt,
    bool Function(_Run run)? until,
  }) {
    for (var i = 0; i < steps; i++) {
      if (until != null && until(this)) return;
      step(forward: true, jump: jumpAt != null && jumpAt(this));
    }
  }

  double get z => runner.position.z;
  double get y => runner.position.y;

  /// The highest the body has been above where it started, in metres.
  ///
  /// Tracked as it goes rather than sampled, because the apex falls between two
  /// steps and a loop that reads `y` afterwards misses it by however much the
  /// step happened to be worth.
  double get rise => _rise;
  double _rise = 0.0;
}

void main() {
  group('the level', () {
    test('a platformer level validates against a platformer registry', () {
      // The format is the shooter's format, and it holds a level with no
      // monsters, no weapons and no pickups in it because none of those were
      // ever the format's. This is the cheapest half of stage 5's acceptance,
      // and it fails loudly if a genre's words leak back into `EntityTypes`.
      final issues = LevelValidator(
        registry: platformerRegistry(),
        rules: platformerRules(),
      ).validate(_level());

      expect(issues.where((LevelIssue i) => i.isError), isEmpty);
    });

    test('the whole game builds with no renderer', () {
      expect(_Run().sim.state, RunState.running);
    });
  });

  group('jumping', () {
    test('one jump does not reach the ledge and two do', () {
      // The level is built around these two numbers. Mutation: set
      // `airJumpSpeed` to zero and the second fails; raise `jumpSpeed` to 11
      // and the first does, taking the reason for the ledge with it.
      const double ledge = 2.4;

      final single = _Run();
      final ground = single.y;
      for (var i = 0; i < 100; i++) {
        single.step(jump: true);
      }
      expect(
        single.rise,
        lessThan(ledge),
        reason: 'one jump must not clear a ${ledge}m ledge',
      );
      expect(single.y, closeTo(ground, 0.05), reason: 'and it comes back down');

      final twice = _Run();
      for (var i = 0; i < 24; i++) {
        twice.step(jump: true);
      }
      // Released at the top, then pressed again — which is what a player does
      // and, more to the point, the only way to get a second press edge.
      twice.step();
      for (var i = 0; i < 100; i++) {
        twice.step(jump: true);
      }
      expect(twice.rise, greaterThan(ledge), reason: 'two must clear it');
    });

    test('a jump released early is shorter than one held', () {
      // Variable jump height, which is the control that makes a platformer a
      // platformer. Mutation: set `jumpCut` to 1.0 — the two runs then agree to
      // within a millimetre and this fails.
      double apexOf({required bool holdIt}) {
        final run = _Run()..step(jump: true);
        for (var i = 0; i < 80; i++) {
          run.step(jump: holdIt);
        }
        return run.rise;
      }

      final held = apexOf(holdIt: true);
      final tapped = apexOf(holdIt: false);

      expect(tapped, lessThan(held - 0.4));
    });

    test('the air jump is spent once and comes back on landing', () {
      final run = _Run();
      // Off the edge of the world's ground rather than off a jump, so the
      // first jump is the air one and the budget is unambiguous.
      run.step(jump: true);
      expect(run.runner.airJumpsLeft, 1, reason: 'the ground jump is free');

      for (var i = 0; i < 20; i++) {
        run.step();
      }
      run.step(jump: true);
      expect(run.runner.airJumpsLeft, 0);

      run.step(jump: true);
      expect(run.runner.airJumpsLeft, 0, reason: 'a third jump is not a jump');

      for (var i = 0; i < 120; i++) {
        run.step();
      }
      expect(run.runner.isGrounded, isTrue, reason: 'it should be back down');
      expect(run.runner.airJumpsLeft, 1, reason: 'landing refills it');
    });
  });

  group('the run', () {
    test('the coin is collected by walking over it', () {
      final run = _Run()
        ..run(180, until: (_Run r) => r.runner.purse['coin'] > 0);
      expect(run.runner.purse['coin'], 1);
    });

    test('and the step says so, for whoever has to make a noise about it', () {
      // The purse is not the whole answer. A game hears a pickup through
      // `takenThisStep`, which is filled from the mechanism world's published
      // events — and this step forgot to publish them, so for as long as the
      // platformer has existed the coin has been counted in silence. The purse
      // filling up is exactly why nobody noticed.
      //
      // Mutation: drop `mechanisms?.publish()` from `PlatformerSimulation.step`.
      final run = _Run()
        ..run(180, until: (_Run r) => r.sim.takenThisStep.isNotEmpty);

      expect(run.sim.takenThisStep, hasLength(1));
      expect(run.sim.takenThisStep.single.name, 'first coin');
      expect(run.sim.takenThisStep.single.what, 'coin');

      // And cleared again on the next step, so a sound plays once.
      run.step();
      expect(run.sim.takenThisStep, isEmpty);
    });

    test('a revived runner stands on the floor rather than inside it', () {
      // **The bug a player found in four seconds.** A level says where a
      // checkpoint is the way a person points at the floor; a body is a box
      // about its centre. Teleporting the centre to the authored point buries
      // the runner half a body deep, and what follows is a death loop with no
      // way out of it — it slides, falls, dies and comes back to the same spot.
      //
      // Mutation: drop the `halfExtents.y` in `Runner.reviveAt`.
      final run = _Run();
      final standing = run.y;

      run.runner.reviveAt(Vector3(0.0, 0.0, 2.0));
      expect(run.runner.position.y, closeTo(standing, 0.01));

      // And it stays there: a buried body is not grounded and does not rest.
      for (var i = 0; i < 30; i++) {
        run.step();
      }
      expect(run.runner.isGrounded, isTrue);
      expect(run.runner.position.y, closeTo(standing, 0.05));
    });

    test('dying once does not become dying forever', () {
      // The death loop as the player met it: fall in, come back, fall in again
      // without having moved. One fall must stay one fall.
      final run = _Run()..run(240, until: (_Run r) => r.sim.deaths > 0);
      expect(run.sim.deaths, 1);

      for (var i = 0; i < 120; i++) {
        run.step();
      }
      expect(
        run.sim.deaths,
        1,
        reason: 'standing still after a revive is safe',
      );
      expect(run.runner.isGrounded, isTrue);
    });

    test('falling in the pit puts the runner back at the checkpoint', () {
      final run = _Run()
        // Forward until past the checkpoint and into the gap. No jumping, so
        // the gap is a hole rather than an obstacle.
        ..run(240, until: (_Run r) => r.sim.deaths > 0);

      expect(run.sim.deaths, greaterThan(0));
      // One more step to carry out the revival the fall scheduled.
      run.step();
      expect(run.sim.state, RunState.running);
      expect(
        run.runner.position.z,
        closeTo(4.5, 0.6),
        reason: 'the checkpoint said 4.5, not the level start',
      );
      expect(run.runner.health.isAlive, isTrue);
    });

    test('the level can be finished', () {
      final run = _Run()
        ..run(
          900,
          // Three windows, and the gaps between them are as load-bearing as the
          // windows: releasing is what ends the first jump and what makes the
          // second press an edge at all.
          //
          //   5.2 - 8.5   clear the pit, one jump, held the whole way up
          //  13.4 - 15.6  the first half of the double jump, likewise held
          //  15.75- 18.0  the second, which is over 2.8 m by the ledge's face
          //
          // Each window is long enough to cover the whole ascent on purpose.
          // The first draft cut them short and the runner fell in the pit: the
          // release edge is what ends a jump, so letting go at the top of a
          // window means letting go halfway up.
          jumpAt: (_Run r) =>
              (r.z > 5.2 && r.z < 8.5) ||
              (r.z > 13.4 && r.z < 15.6) ||
              (r.z > 15.75 && r.z < 18.0),
          until: (_Run r) => r.sim.state == RunState.finished,
        );

      expect(run.sim.state, RunState.finished);
      expect(run.sim.nextLevel, 'second steps');
      expect(run.runner.purse['coin'], 1, reason: 'the coin is on the way');
    });
  });
}
