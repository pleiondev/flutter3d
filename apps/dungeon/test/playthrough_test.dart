/// The first test this application has ever had.
///
/// It loads `crypt.json`, builds the whole simulation, and plays the level to
/// its exit — the key, the locked door, the corridor beyond — **with no
/// widgets, no GPU and no renderer of any kind**. That it can be written at all
/// is the point of everything under `packages/`: the game is a simulation that
/// something happens to draw, so the parts that decide whether a level is
/// finishable are reachable from a plain unit test.
///
/// Every ordering bug in `GameSimulation` would have been caught by this the
/// day it was written, and none of them were, because until now there was
/// nothing here to catch them.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_shooter/sample.dart';
import 'package:flutter3d_shooter/flutter3d_shooter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

Level _crypt() => Level.fromJson(
      jsonDecode(File('assets/levels/crypt.json').readAsStringSync())
          as Map<String, dynamic>,
    );

/// Everything `main.dart` builds, minus everything that draws.
final class _Game {
  _Game(this.level, {required EntityRegistry registry}) {
    level.addTo(world);
    actors = ActorSystem(world: world, entities: entities)
      ..navigation = Navigation.bake(level, cellSize: 0.25);
    (registry[ShooterEntities.monster] as MonsterKind?)?.bestiary = Bestiary(
      actors: actors,
      shot: WeaponShot(
        world: world,
        hitscan: Hitscan(world: world),
        projectiles: projectiles,
      ),
      catalog: Monsters.byName,
    );
    mechanisms = MechanismWorld(world);
    level.spawnInto(
      SpawnContext(world: world, actors: actors, mechanisms: mechanisms),
      registry: registry,
    );

    final start = level.playerStart!;
    player = Player(
      body: CharacterController(
        world: world,
        // A spawn is authored where the feet go, which is the only place an
        // author can see.
        position: start.position + Vector3(0.0, 0.9, 0.0),
      ),
      inventory: Inventory(arsenal: sampleArsenal()),
    )..yaw = start.yaw;

    sim = GameSimulation(
      player: player,
      collision: world,
      input: input,
      mechanisms: mechanisms,
      actors: actors,
      projectiles: projectiles,
      shot: WeaponShot(
        world: world,
        hitscan: Hitscan(world: world),
        projectiles: projectiles,
      ),
      levelNext: level.next,
    );
    world.update();
  }

  final Level level;
  final CollisionWorld world = CollisionWorld();

  /// One entity world for both systems; two would be a save covering half the
  /// game.
  final EcsWorld entities = EcsWorld();
  late final ProjectileSystem projectiles =
      ProjectileSystem(world: world, entities: entities);
  late final ActorSystem actors;
  late final MechanismWorld mechanisms;
  late final Player player;
  late final GameSimulation sim;
  final InputState input = InputState();

  /// This test's own routing, kept apart from `monsters.navigation` on purpose.
  ///
  /// A `Navigation` re-targets **every** field it holds when its goal moves,
  /// and the monster system moves its goal to the player once a step. Sharing
  /// one would mean these fields quietly flowed towards the player instead of
  /// wherever this was walking — which is exactly what happened first time, and
  /// looked like the player being wedged in a corner.
  late final Navigation route = Navigation.bake(level, cellSize: 0.25);

  Vector3 get at => player.body.position;

  /// Walks towards [goal], routing round corners with the level's own
  /// navigation grid, and stops when it is within [within] metres of it.
  ///
  /// The route comes from `Navigation` rather than from a hand-written list of
  /// waypoints, which makes this a test of the grid as well: a path the field
  /// reports has to be one the character controller can actually walk.
  ///
  /// Returns false if it did not arrive inside [steps]. When [until] is given
  /// it is the success condition instead of the distance — walking *to* a key
  /// and *picking it up* are different events, and only the second one matters.
  bool walkTo(
    Vector3 goal, {
    double within = 1.5,
    int steps = 1800,
    bool Function()? until,
  }) {
    // Two fields, wide and narrow, and the reason is worth stating because it
    // is a real property of grid navigation rather than a trick.
    //
    // The wide one asks for the player's own size, so the route it reports is
    // one this body can walk with room to spare. But a grid is conservative:
    // a cell touching a wall has a clearance of one whatever the wall's actual
    // distance, so the wide field abandons whole corners of the level, and a
    // player standing in one gets no direction at all. The narrow field covers
    // those, at the price of routes that hug walls — which the character
    // controller slides along.
    final wide = route.fieldFor(radius: 0.35, height: 1.8)..rebuild(goal);
    final narrow = route.fieldFor(radius: 0.0, height: 1.8)..rebuild(goal);
    final direction = Vector3.zero();

    var best = double.infinity;
    for (var i = 0; i < steps; i++) {
      if (until != null) {
        if (until()) return true;
      }
      final togo = Vector3(goal.x - at.x, 0.0, goal.z - at.z);
      if (togo.length < best) best = togo.length;
      if (until == null && togo.length < within) return true;

      // Straight at it when the field has nothing to say, which is what it
      // reports inside the goal's own cell and off the grid.
      if (!wide.descend(at, direction) && !narrow.descend(at, direction)) {
        direction
          ..setFrom(togo)
          ..normalize();
      }
      // Face where we are going and walk forwards, through the same input the
      // keyboard writes to.
      player.yaw = _yawTowards(direction);
      input.setStickAxis(0.0, 1.0);
      sim.step(_dt);
      input.endStep();
    }
    // ignore: avoid_print
    print('walkTo $goal gave up at $at, closest ${best.toStringAsFixed(2)}');
    return false;
  }

  /// Presses the use key while facing [target].
  void useOn(Vector3 target) {
    final togo = Vector3(target.x - at.x, 0.0, target.z - at.z);
    player
      ..yaw = _yawTowards(togo)
      ..pitch = 0.0;
    input
      ..setStickAxis(0.0, 0.0)
      ..press(GameAction.use);
    sim.step(_dt);
    input.endStep();
  }

  void idle(int steps) {
    for (var i = 0; i < steps; i++) {
      input.setStickAxis(0.0, 0.0);
      sim.step(_dt);
      input.endStep();
    }
  }

  /// `forward` is −Z at yaw zero, so this is the inverse of `Player.forward`.
  static double _yawTowards(Vector3 direction) =>
      math.atan2(-direction.x, -direction.z);
}

void main() {
  test('the level a game ships with has no errors in it', () {
    // The validator runs against the same registry the game spawns from, so
    // the two cannot disagree about what a document may contain.
    final issues = LevelValidator(
      registry: sampleRegistry(),
      rules: sampleRules(),
    ).validate(_crypt());

    expect(
      issues.where((LevelIssue i) => i.isError),
      isEmpty,
      reason: issues.join('\n'),
    );
  });

  test('the whole game builds without a renderer', () {
    // Not a formality. `flutter3d_game` does not depend on `flutter3d`, and
    // this is what that sentence is worth: the simulation, the level, the
    // mechanisms and the navigation all come up with no graphics context in
    // existence.
    final game = _Game(_crypt(), registry: sampleRegistry());

    expect(game.sim.state, GameState.playing);
    expect(game.mechanisms['crypt_door'], isA<Door>());
    expect(game.mechanisms['way_down'], isA<Exit>());
    expect(game.actors.actors, hasLength(3));
    expect(game.player.isAlive, isTrue);
  });

  test('the crypt can be finished', () {
    // The level as authored: a locked door, a key on the far side of the hall,
    // and an exit past it. Monsters are left out — a fight is not what this
    // measures, and leaving `MonsterKind` out of the registry is also the
    // shortest demonstration that the package has no opinion about whether a
    // game has monsters at all.
    // `monsters: false` and nothing else: the registry has no `monster` in it,
    // so the word is not part of the language this level is read in and the
    // three in the document spawn nothing. The shortest statement of what the
    // content seam is worth.
    final game = _Game(_crypt(), registry: sampleRegistry(monsters: false));

    final key = game.level.entities
        .firstWhere((EntityDef e) => e.type == EntityTypes.key);
    final door = game.mechanisms['crypt_door']! as Door;
    final exit = game.mechanisms['way_down']! as Exit;

    expect(
      game.walkTo(key.position, until: () => game.player.keys.contains('iron')),
      isTrue,
      reason: 'never picked up the key at ${key.position}',
    );

    // Up to the door, then a hand on it. It is locked, and the key is what
    // makes the difference — the same activation with an empty key ring is
    // refused.
    expect(game.walkTo(door.collider.position, within: 2.0), isTrue,
        reason: 'never reached the door');
    game.useOn(door.collider.position);
    game.idle(120);
    expect(door.progress, greaterThan(0.0), reason: 'the door did not open');

    expect(
      game.walkTo(
        exit.collider.position,
        until: () => game.sim.state == GameState.complete,
      ),
      isTrue,
      reason: 'never reached the exit at ${exit.collider.position}',
    );
    expect(game.sim.state, GameState.complete);
    expect(game.sim.nextLevel, isNull, reason: 'the crypt says nothing next');
  });
}
