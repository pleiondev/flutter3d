/// The level you play first, played to its exit.
///
///     flutter test test/first_steps_test.dart
///
/// The big level's own test deliberately does **not** finish it: a hundred and
/// twenty metres by two hundred and sixty, with two locked gates and a maze in
/// it, is a route script rewritten every time a brush moves. A teaching level
/// is the opposite case. It is short, it is a corridor, and the whole claim it
/// makes — that each room can be got through with the verb it teaches — is
/// exactly what a playthrough checks.
///
/// The autopilot is a *repertoire*, not a route: it walks, and when it has
/// stopped making progress it tries the next trick it knows. That is as close
/// to how a player meets a teaching level as a test can get, and it keeps the
/// script from encoding coordinates that a level edit would invalidate.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_platformer/flutter3d_platformer.dart';
import 'package:flutter3d_ui/flutter3d_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platformer/src/save_file.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

Level _level() => Level.fromJson(
      jsonDecode(File('assets/levels/first_steps.json').readAsStringSync())
          as Map<String, Object?>,
    );

final class _Game {
  /// [startAt] is the runner's feet. Defaults to the level's own spawn.
  _Game({Vector3? startAt}) {
    final kinds = platformerRegistry();
    LevelValidator(registry: kinds, rules: platformerRules()).assertValid(level);

    level.addTo(world);
    mechanisms = MechanismWorld(world);
    actors = ActorSystem(world: world);
    (kinds[PlatformerEntities.crate] as CrateKind?)?.dynamics = dynamics;
    level.spawnInto(
      SpawnContext(world: world, actors: actors, mechanisms: mechanisms),
      registry: kinds,
    );

    final start = startAt ?? level.playerStart?.position ?? Vector3.zero();
    runner = Runner(
      body: CharacterController(
        world: world,
        position: start + Vector3(0.0, 0.9, 0.0),
      ),
      surfaces: Surfaces.common(),
    );
    sim = PlatformerSimulation(
      runner: runner,
      collision: world,
      input: input,
      startAt: start,
      mechanisms: mechanisms,
      dynamics: dynamics,
      actors: actors,
      levelNext: level.next,
    );
  }

  final Level level = _level();
  final CollisionWorld world = CollisionWorld();
  late final Dynamics dynamics = Dynamics(world: world);
  final InputState input = InputState();
  late final MechanismWorld mechanisms;
  late final ActorSystem actors;
  late final Runner runner;
  late final PlatformerSimulation sim;

  final Set<GameAction> _held = <GameAction>{};

  void step(Set<GameAction> holding) {
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

  double get z => runner.position.z;
}

/// Walks the level, trying harder when it stops getting anywhere.
///
/// Four tricks, in the order a player would reach for them: walk, walk and
/// jump, add a dash, crouch. Each is held for a while before the next is tried,
/// and progress resets the ladder — so a run that gets through a room on the
/// jump rhythm does not carry a dash into the next one.
bool _playThrough(_Game game, {int steps = 7200}) {
  var trick = 0;
  // Progress is *either* axis. Measuring only the way forward was the first
  // attempt, and it abandoned the climb halfway up the chimney every time:
  // going up a shaft is progress that does not move you along the level at all.
  var bestZ = game.z;
  var bestY = game.runner.position.y;
  var stuckFor = 0;

  for (var i = 0; i < steps; i++) {
    if (game.sim.state == RunState.finished) return true;

    final holding = <GameAction>{GameAction.moveForward};
    // Jump on a rhythm rather than every step: a held button is one jump, and a
    // release on every step cuts every jump short.
    final beat = i % 30;
    if (trick >= 1 && beat < 22) holding.add(GameAction.jump);
    if (trick == 2 && beat == 5) holding.add(PlatformerActions.dash);
    if (trick == 3) holding.add(PlatformerActions.dropThrough);
    // Climbing: lean into whichever wall the runner is actually on and jump on
    // a fast rhythm. Blindly holding one direction was the first attempt and it
    // sat at the bottom of the chimney — which wall is nearer is a fact the
    // runner already reports, and a player uses their eyes for exactly this.
    if (trick >= 4) {
      holding.remove(GameAction.jump);
      final away = game.runner.wallAway;
      // Lean into the wall it is on — and when it is on none, lean *somewhere*
      // so that it finds one. Only leaning once a wall was already detected was
      // the first attempt, and it stood in the middle of the chimney for ever:
      // the probe reaches fourteen centimetres and the slot is two metres.
      holding.add(away.x <= 0.0 ? GameAction.moveLeft : GameAction.moveRight);
      if (i % 14 < 3) holding.add(GameAction.jump);
    }

    game.step(holding);

    final y = game.runner.position.y;
    if (game.z > bestZ + 0.25) {
      // Forward is the level being played: start again from walking, so a dash
      // learned in one room is not carried into the next.
      bestZ = game.z;
      if (y > bestY) bestY = y;
      stuckFor = 0;
      trick = 0;
    } else if (y > bestY + 0.25) {
      // Upward is a climb in progress. Keep doing whatever is working.
      bestY = y;
      stuckFor = 0;
    } else if (++stuckFor > (trick == 4 ? 420 : 90)) {
      // The climb gets a much longer leash than the rest. A wall jump gains
      // about a metre and a half and the slide between them gives some of it
      // back, so a climb makes no net progress for stretches longer than the
      // patience the other tricks need — and the engine's own wall-jump test
      // takes four hundred steps to go four metres.
      stuckFor = 0;
      trick = (trick + 1) % 5;
    }
  }
  return game.sim.state == RunState.finished;
}

void main() {
  test('the level a player starts on has no errors in it', () {
    final issues = LevelValidator(
      registry: platformerRegistry(),
      rules: platformerRules(),
    ).validate(_level());

    expect(
      issues.where((LevelIssue i) => i.isError).map((LevelIssue i) => i.message),
      isEmpty,
    );
    // Overlapping brushes z-fight, and a teaching level is the last place to
    // ship a flicker. This one is built to butt rather than overlap.
    expect(
      issues.map((LevelIssue i) => i.message).where((String m) =>
          m.contains('overlaps')),
      isEmpty,
    );
  });

  test('it can be finished, and it says where to go next', () {
    // **The acceptance for the whole stage.** A teaching level that cannot be
    // finished by trying the things it teaches is a teaching level that teaches
    // the wrong things.
    final game = _Game();

    expect(_playThrough(game), isTrue,
        reason: 'the autopilot stopped at '
            '(${game.runner.position.x.toStringAsFixed(1)}, '
            '${game.runner.position.y.toStringAsFixed(1)}, '
            '${game.z.toStringAsFixed(1)})');
    expect(game.sim.nextLevel, 'assets/levels/ascent.json');
  });

  group('the double-jump room can be got out of without a double jump', () {
    // **The defect the level shipped with**, and the one the player hit: the
    // room went straight to a 2.6 m shelf across the whole width — over a
    // single jump's 1.8, under a double's 3.13 — with nothing before it. A
    // player who had not discovered the second jump walked into it and stopped.
    // Measured before the fix: walking and jumping reach z = 23.5 and stall
    // there for the rest of the run.
    //
    // **This is a local claim on purpose.** The first version of this test said
    // "a walking, jumping player reaches z > 44" and passed with the step
    // deleted — because a bot that wanders left and right while jumping ends up
    // leaning on the level's own boundary wall and *wall jumps up it*: twenty-
    // nine of them, to a height of 5.1 m, at |x| = 10.6. A claim about how far
    // somebody gets is a claim about the whole level's geometry, and it was
    // being satisfied by an escape route nobody designed. So this asks the
    // question that was actually asked: can you get on top of the shelf with
    // one jump at a time?

    /// The top of every brush whose footprint covers [x], [z].
    List<double> topsAt(double x, double z) => <double>[
          for (final brush in _level().brushes)
            if ((brush.centre.x - x).abs() <= brush.size.x / 2.0 &&
                (brush.centre.z - z).abs() <= brush.size.z / 2.0)
              brush.centre.y + brush.size.y / 2.0,
        ];

    test('a step in front of it turns one climb into two', () {
      // **A claim about the level, not about a bot**, and that is not laziness.
      // Two behavioural versions of this test came before it and neither could
      // fail. The first said "a walking, jumping player reaches z > 44" and
      // passed with the step deleted, because a bot that wanders while jumping
      // ends up leaning on the level's own boundary wall and wall jumps up it:
      // twenty-nine of them, to 5.1 m, at |x| = 10.6. The second put the bot in
      // front of the step and it passed with the step deleted too — the shelf's
      // *face* is a wall, and this runner wall jumps walls, so whether a few of
      // those get you over depends on the approach.
      //
      // That inconsistency is worth knowing and is written down rather than
      // asserted: it means the room's real difficulty is "a double jump, or
      // luck". What the step contributes is a way up that is not luck, and what
      // can be checked is that it is one — reachable from the floor in a single
      // jump, and within a single jump of the shelf.
      //
      // Mutation: delete the step. There is nothing at x = 9 between the floor
      // and the shelf, and this says so.
      const jump = 1.8;

      final floor = topsAt(9.0, 23.0).reduce(math.min);
      final step = topsAt(9.0, 23.0).where((double y) => y > floor + 0.3);
      expect(step, isNotEmpty, reason: 'nothing to climb at x = 9');

      final onto = step.reduce(math.min);
      expect(onto - floor, lessThan(jump),
          reason: 'the step is ${(onto - floor).toStringAsFixed(2)} m up, and a '
              'single jump is $jump');

      final shelf = topsAt(0.0, 26.0).reduce(math.max);
      expect(shelf - onto, lessThan(jump),
          reason: 'from the step at $onto the shelf at $shelf is '
              '${(shelf - onto).toStringAsFixed(2)} m, more than a jump');
    });

    test('and the shelf it leads onto is still worth a double jump', () {
      // The other half, without which the test above is satisfied by lowering
      // the shelf until anyone can hop it: the lesson has to still be a lesson.
      //
      // A claim about the *level*, not about a bot, and deliberately so. Run
      // head-on at the shelf and the answer is not stable — the face is a wall,
      // jumping at a wall is a wall jump, and whether a few of those get you
      // over depends on the approach. That is its own complaint about the room
      // and not one a threshold in a test can express, so what is pinned here
      // is the geometry the design argument rests on.
      final shelf = <Brush>[
        for (final brush in _level().brushes)
          if (brush.centre.z > 24.0 &&
              brush.centre.z < 28.0 &&
              brush.centre.x.abs() < 1.0)
            brush,
      ];

      expect(shelf, isNotEmpty, reason: 'the shelf is gone');
      final top = shelf.first.centre.y + shelf.first.size.y / 2.0;
      expect(top, greaterThan(1.8),
          reason: 'the shelf is ${top}m, which a single jump clears, so the '
              'room teaches nothing');
      expect(top, lessThan(3.13),
          reason: 'the shelf is ${top}m, which a double jump cannot clear '
              'either, so the room teaches nothing');
    });
  });

  test('nothing a player must reach is inside a wall — in both shipped levels',
      () {
    // **The new rule, applied to the thing it was written for.** A test that
    // builds its own fixture proves the code path; this loads the documents the
    // game actually ships and asks about them. Fourteen coins and a crate were
    // inside brushes when it was first run — eight here, six in Ascent, several
    // of them placed by hand in the session that added the crawlspace.
    //
    // Mutation: put any of them back. `python3 tool/make_first_steps.py` now
    // refuses outright, and if a document is edited past the generator this
    // catches it.
    for (final path in <String>[
      'assets/levels/first_steps.json',
      'assets/levels/ascent.json',
    ]) {
      final level = Level.fromJson(
        jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>,
      );
      final buried = LevelValidator(
        registry: platformerRegistry(),
        rules: platformerRules(),
      ).validate(level).where(
            (LevelIssue i) => i.message.contains('inside solid geometry'),
          );

      expect(buried, isEmpty,
          reason: '$path: ${buried.map((LevelIssue i) => i.toString()).join('; ')}');
    }
  });

  test('the low passage can actually be crawled through', () {
    // It could not. The floor's top was at y = 6 and the slab's underside at
    // 6.5 — half a metre against a crouched body 0.9 m tall — so the room that
    // teaches crouching was impassable crouched. The autopilot finished the
    // level anyway by climbing the 5.5 m face of the slab, which is why no test
    // ever said so.
    //
    // Mutation: lower the slab back to a centre of 9.0. The gap drops to 0.5
    // and this fails; a bot cannot tell you that, because a bot finds the way
    // round.
    const crouched = 0.45 * 2.0;
    final level = _level();
    final tops = <double>[];
    final bottoms = <double>[];
    for (final brush in level.brushes) {
      if ((brush.centre.z - 94.0).abs() > 4.0) continue;
      if (brush.centre.x.abs() > 1.0) continue;
      final top = brush.centre.y + brush.size.y / 2.0;
      final bottom = brush.centre.y - brush.size.y / 2.0;
      if (top < 7.0) tops.add(top);
      if (bottom > 6.0) bottoms.add(bottom);
    }

    expect(tops, isNotEmpty, reason: 'no floor under the passage');
    expect(bottoms, isNotEmpty, reason: 'no roof over the passage');

    final gap = bottoms.reduce(math.min) - tops.reduce(math.max);
    expect(gap, greaterThan(crouched),
        reason: 'the passage is ${gap}m and a crouched runner is ${crouched}m');
    expect(gap, lessThan(1.8),
        reason: 'the passage is ${gap}m, which a standing runner walks through, '
            'so it teaches nothing');
  });

  test('there is enough in it to be worth playing', () {
    // Not a mechanism, a *quantity*, and it is here because the level failed on
    // exactly that: forty-four coins and seven crates now, against eleven and
    // none. The complaint was "few coins, no crates to push, dull", and a level
    // that teaches six verbs across a hundred and eighteen metres with nothing
    // to pick up is a corridor with lessons in it.
    final level = _level();
    expect(level.ofType(PlatformerEntities.collectible).length,
        greaterThanOrEqualTo(40));
    expect(level.ofType(PlatformerEntities.crate).length,
        greaterThanOrEqualTo(6));
  });

  test('every room is behind the one before it', () {
    // The checkpoints are the level's own account of its order, and a post
    // numbered out of step sends a player backwards when they die at it.
    final game = _Game();
    final posts = <Checkpoint>[
      for (final m in game.mechanisms.all)
        if (m is Checkpoint) m,
    ]..sort((Checkpoint a, Checkpoint b) => a.order.compareTo(b.order));

    expect(posts, hasLength(5));
    for (var i = 1; i < posts.length; i++) {
      expect(posts[i].at.z, greaterThan(posts[i - 1].at.z));
    }
  });

  test('quitting halfway and coming back is the same run, through the file',
      () {
    // **The end of E5, joined up.** The package proves that `save`/`restore`
    // carries the state; this proves that the game's own path carries it —
    // a real level, a real run, a real file on disk, and a second world built
    // from scratch the way a relaunch builds one.
    //
    // Mutation: write `sim.save()` but restore into a world whose entities were
    // never spawned, or drop the level name from the file. The purse survives
    // and the world does not, which is exactly the class of bug the whole stage
    // is about.
    final temporary = Directory.systemTemp.createTempSync('platformer_resume');
    addTearDown(() => temporary.deleteSync(recursive: true));
    final saves = SaveFile(
      storage: FileStorage(appName: 'platformer', directory: temporary),
    );

    final first = _Game();
    _playThrough(first, steps: 1800);
    expect(first.runner.purse['coin'], greaterThan(0),
        reason: 'nothing had happened yet, so nothing is under test');

    saves.write('assets/levels/first_steps.json', first.sim.save());

    final read = saves.read();
    expect(read, isNotNull);
    expect(read!.level, 'assets/levels/first_steps.json');

    final second = _Game()..sim.restore(read.run);

    expect(second.runner.purse['coin'], first.runner.purse['coin']);
    expect(second.sim.deaths, first.sim.deaths);
    expect(second.sim.elapsed, closeTo(first.sim.elapsed, 1e-6));
    expect(second.runner.position.z, closeTo(first.runner.position.z, 0.01));
    expect(second.sim.respawnPoint.z, closeTo(first.sim.respawnPoint.z, 0.01));

    // And the world came back with it: a coin already taken is still gone, so
    // walking the level again does not pay twice.
    final taken = <Collectible>[
      for (final m in second.mechanisms.all)
        if (m is Collectible && m.isTaken) m,
    ];
    expect(taken, hasLength(first.runner.purse['coin']));
  });

  test('nothing in it can kill you', () {
    // The claim the file's own header makes: every pit has a floor and a stair,
    // and the only thing that hurts is the guard at the end. A teaching level
    // that kills is a teaching level that teaches frustration.
    final level = _level();
    expect(level.ofType(PlatformerEntities.hazard), isEmpty);
  });
}
