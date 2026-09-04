/// What a level was worth: how many, out of how many.
///
///     flutter test test/tally_test.dart
///
/// **The shooter had nothing to show at the end of a level**, which is half of
/// what the genre is. The walk to the exit is the game; the numbers on the way
/// out are what say whether it was played or merely survived. There were no
/// secrets in the level format at all, and nothing counted a kill.
///
/// Three of five is a sentence and three is not, so both halves are here: what
/// happened, and what the level held.
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_game_shooter/sample.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

/// A room, a player in it, and whatever else a test asks for.
final class _Level {
  _Level({int monsters = 0, int secrets = 0, Vector3? secretAt}) {
    world
      ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(60.0, 1.0, 60.0))
      ..update();

    player = Player(
      body: CharacterController(world: world, position: Vector3(0.0, 0.9, 0.0)),
      // Slot one is the pistol; slot nought is fists, which reach a metre.
      inventory: Inventory(arsenal: sampleArsenal(startingSlot: 1)),
    );

    final random = GameRandom(5);
    final actors = ActorSystem(world: world, random: random);
    final bestiary = Bestiary(
      actors: actors,
      shot: WeaponShot(
        world: world,
        hitscan: Hitscan(world: world, random: random),
        projectiles: ProjectileSystem(world: world),
      ),
      catalog: Monsters.byName,
    );
    for (var i = 0; i < monsters; i++) {
      spawned.add(
        bestiary.spawn(Monsters.runner, Vector3(6.0 + i * 3.0, 0.0, -12.0)),
      );
    }

    for (var i = 0; i < secrets; i++) {
      final collider = world.add(
        Collider(
          shape: CollisionBox(Vector3(1.0, 1.25, 1.0)),
          position: secretAt ?? Vector3(3.0 + i * 6.0, 0.9, 0.0),
          kind: ColliderKind.trigger,
          layer: CollisionLayers.trigger,
          mask: CollisionLayers.player,
        ),
      );
      this.secrets.add(
        mechanisms.add(Secret(name: 'secret$i', collider: collider)),
      );
    }
    // **Not updated here on purpose.** An overlap dispatched before the first
    // step would set the secret's flag and the first step's `movers` would
    // clear it again before anything counted — which is a real edge (a secret
    // a player starts inside) and not what this file is about.

    sim = GameSimulation(
      random: random,
      player: player,
      collision: world,
      input: input,
      mechanisms: mechanisms,
      actors: actors,
      shot: WeaponShot(
        world: world,
        hitscan: Hitscan(world: world, random: random),
        projectiles: ProjectileSystem(world: world),
      ),
    );
  }

  final CollisionWorld world = CollisionWorld();
  final InputState input = InputState();
  late final MechanismWorld mechanisms = MechanismWorld(world);
  late final Player player;
  late final GameSimulation sim;
  final List<Actor> spawned = <Actor>[];
  final List<Secret> secrets = <Secret>[];

  void step({int times = 1}) {
    for (var i = 0; i < times; i++) {
      input.beginStep();
      sim.step(_dt);
      input.endStep();
    }
  }
}

void main() {
  test('a level says how much of it there is', () {
    // Read from what was actually spawned rather than from a field in the
    // document: a level claiming four monsters and spawning three would
    // otherwise report itself unfinishable for ever.
    final it = _Level(monsters: 3, secrets: 2)..step();

    expect(it.sim.monsterCount, 3);
    expect(it.sim.secretCount, 2);
  });

  test('and counts nothing before anything has happened', () {
    final it = _Level(monsters: 2, secrets: 1)..step();

    expect(it.sim.tally[GameSimulation.kills], 0);
    expect(it.sim.tally[GameSimulation.secrets], 0);
  });

  test('and a kill is counted once, on the step it happened', () {
    // **Killed by the player, inside a step, which is the case that was
    // broken.** The shot is fired before the actors think, and `ActorSystem`
    // used to clear its dead at the top of its own step — so a monster the
    // player killed was reported to nobody at all. Everything downstream of
    // that read an empty list: this count, the death sound, the sparks.
    final it = _Level(monsters: 1)..step();
    final monster = it.spawned.single;
    // Softened, so a pistol finishes it in a few shots rather than a hundred.
    monster.applyDamage(monster.health!.current - 1.0, from: it.player);

    // Straight down the barrel: the monster is put where the player is aiming.
    monster.body!.teleport(Vector3(0.0, 0.9, -4.0));
    it.world.update();

    for (var i = 0; i < 30 && monster.isAlive; i++) {
      it.input.beginStep();
      it.input.press(ShooterActions.fire);
      it.sim.step(_dt);
      it.input.release(ShooterActions.fire);
      it.input.endStep();
    }

    expect(monster.isAlive, isFalse, reason: 'the shot never landed');
    expect(it.sim.tally[GameSimulation.kills], 1);

    // And not again on the next step.
    it.step(times: 5);
    expect(it.sim.tally[GameSimulation.kills], 1);
  });

  test('and walking into a secret finds it, once', () {
    // Placed where the player is standing, so the trigger fires on the first
    // step rather than after a walk this test is not about.
    final it = _Level(secrets: 1, secretAt: Vector3(0.0, 0.9, 0.0))
      ..step(times: 3);

    expect(it.sim.tally[GameSimulation.secrets], 1);
    expect(it.secrets.single.isFound, isTrue);

    it.step(times: 10);
    expect(
      it.sim.tally[GameSimulation.secrets],
      1,
      reason: 'standing in it counted it again',
    );
  });

  test('and it says which one, on the step it was found', () {
    final it = _Level(secrets: 1, secretAt: Vector3(0.0, 0.9, 0.0));

    // Stepped one at a time: this is a step edge, and the whole claim is that
    // it is true on exactly one of them.
    var announced = 0;
    for (var i = 0; i < 6; i++) {
      it.step();
      announced += it.sim.events.drain().whereType<SecretFound>().length;
    }

    expect(
      announced,
      1,
      reason: 'a message and a sound, once, on the step it happened',
    );
  });

  test('and both counts survive being saved and loaded', () {
    // **Counted, tested, serialisable — and not in the save.** `Tally` has had
    // a working `save`/`restore` pair all along and `GameSimulation.save`
    // never called either, so a resumed run reported nought kills and nought
    // secrets while the monsters stayed dead and the secrets stayed found. The
    // end-of-level summary — half of what the genre is — was wrong for any run
    // a player had ever quit out of.
    //
    // The two totals go too: three of five is a sentence and three is not, and
    // they are counted once on the first step from what was actually spawned,
    // so a restore into a level whose monsters are already dead would recount
    // them as none.
    //
    // Mutation: drop the `tally` line from `save`. Both counts come back nought.
    final it = _Level(monsters: 3, secrets: 2);
    it.sim.step(_dt);
    it.sim.tally.add(GameSimulation.kills, 2);
    it.sim.tally.add(GameSimulation.secrets, 1);

    final loaded = _Level(monsters: 3, secrets: 2);
    loaded.sim.restore(Snapshot.fromJson(it.sim.save().toJson()));

    expect(loaded.sim.tally[GameSimulation.kills], 2);
    expect(loaded.sim.tally[GameSimulation.secrets], 1);
    expect(loaded.sim.monsterCount, 3, reason: 'the out-of goes too');
    expect(loaded.sim.secretCount, 2);
  });

  test('and a secret is not something the level draws', () {
    // A secret a player can see is not one. `SecretKind` deliberately reveals
    // nothing, which is the difference between it and every other entity.
    const kind = SecretKind();

    expect(kind.type, ShooterEntities.secret);
  });
}
