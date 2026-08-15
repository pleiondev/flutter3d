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
import 'dart:io';

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_platformer/flutter3d_platformer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platformer/src/save_file.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

Level _level() => Level.fromJson(
      jsonDecode(File('assets/levels/first_steps.json').readAsStringSync())
          as Map<String, Object?>,
    );

final class _Game {
  _Game() {
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

    final start = level.playerStart?.position ?? Vector3.zero();
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
    final saves = SaveFile(directory: temporary);

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
