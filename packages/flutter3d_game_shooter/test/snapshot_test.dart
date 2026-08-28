/// The state of a running game, written down and put back.
///
/// The test that matters here is `_theStrongOne`: take a snapshot, play on for
/// two hundred steps and snapshot again; then restore the first, replay the
/// *same* two hundred steps, and demand the second snapshot back byte for byte.
///
/// Anything a snapshot forgets fails it. A cooldown left out, a monster's
/// state, the jump buffer, where the dice were — each of them changes something
/// within a few steps of the restore, and none of them is visible in a
/// round-trip test that only checks the fields it remembered to check.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_game_shooter/sample.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

/// A room with everything that has state in it: a moving platform, a pickup,
/// a monster that chases and hits back, and a player with a rocket launcher.
final class _World {
  _World({int seed = 7}) : random = GameRandom(seed) {
    world.addBox(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0));
    // Walled, so the script keeps the player in the room. Without them the
    // player walks off the edge in the first two seconds and spends the rest of
    // the test falling at terminal velocity, where nothing that happens to
    // anybody can make any difference to anything.
    for (final wall in <Vector3>[
      Vector3(0.0, 2.0, -20.0),
      Vector3(0.0, 2.0, 20.0),
    ]) {
      world.addBox(wall, Vector3(40.0, 4.0, 1.0));
    }
    for (final wall in <Vector3>[
      Vector3(-20.0, 2.0, 0.0),
      Vector3(20.0, 2.0, 0.0),
    ]) {
      world.addBox(wall, Vector3(1.0, 4.0, 40.0));
    }

    actors = ActorSystem(world: world, entities: entities, random: random);
    bestiary = Bestiary(
      actors: actors,
      shot: WeaponShot(
        world: world,
        hitscan: Hitscan(world: world, random: random),
        projectiles: projectiles,
      ),
      catalog: Monsters.byName,
    );
    mechanisms = MechanismWorld(world);

    mechanisms.add(
      MovingPlatform(
        name: 'ledge',
        collider: world.add(
          Collider(
            shape: CollisionBox(Vector3(1.5, 0.25, 1.5)),
            position: Vector3(-6.0, 0.25, 0.0),
            kind: ColliderKind.kinematic,
          ),
        ),
        travel: Vector3(0.0, 2.0, 0.0),
        wait: 0.5,
      ),
    );
    mechanisms.add(
      Pickup(
        name: 'medkit',
        gift: const HealthGift(),
        amount: 25.0,
        collider: world.add(
          Collider(
            shape: CollisionBox(Vector3(0.4, 0.4, 0.4)),
            position: Vector3(0.0, 0.4, -3.0),
            kind: ColliderKind.trigger,
            layer: CollisionLayers.pickup,
            mask: CollisionLayers.player,
          ),
        ),
      ),
    );

    player = Player(
      body: CharacterController(world: world, position: Vector3(0.0, 0.9, 4.0)),
      inventory: Inventory(
        // Four hundred, so the fight is still going at the last save point.
        // At a hundred the player is dead by step two hundred and forty, and
        // `MonsterSystem.step` is skipped for a dead player — so every monster
        // freezes and every cooldown in the level stops being a number worth
        // saving.
        health: Health(400.0),
        arsenal: Arsenal(
          slots: Weapons.all,
          owned: <WeaponDef>[Weapons.fists, Weapons.rocketLauncher],
          ammo: <AmmoType, int>{AmmoType.rockets: 8},
          startingSlot: 3,
        ),
      ),
    );

    sim = GameSimulation(
      player: player,
      collision: world,
      input: input,
      mechanisms: mechanisms,
      actors: actors,
      projectiles: projectiles,
      shot: WeaponShot(
        world: world,
        hitscan: Hitscan(world: world, random: random),
        projectiles: projectiles,
      ),
      levelNext: 'next.json',
      random: random,
    );

    // One close enough to be swinging within a second, so attack cooldowns
    // and pain timers are live numbers rather than zeros at every save point.
    bestiary.spawn(Monsters.runner, Vector3(0.0, 0.9, 1.0));
    bestiary.spawn(Monsters.runner, Vector3(-2.0, 0.9, -6.0));
    bestiary.spawn(Monsters.tank, Vector3(4.0, 1.2, -9.0));
    world.update();
  }

  final CollisionWorld world = CollisionWorld();

  /// One entity world, handed to both systems. Two would mean a save that
  /// covered half the game, which `GameSimulation.entities` refuses out loud.
  final EcsWorld entities = EcsWorld();
  late final ProjectileSystem projectiles = ProjectileSystem(
    world: world,
    entities: entities,
  );
  final GameRandom random;
  late final ActorSystem actors;
  late final Bestiary bestiary;
  late final MechanismWorld mechanisms;
  late final Player player;
  late final GameSimulation sim;
  final InputState input = InputState();

  /// The same script every time: walk in, look about, and fire rockets at the
  /// far end of the room.
  void play(int steps, {int from = 0}) {
    for (var i = from; i < from + steps; i++) {
      input
        ..setStickAxis(math.sin(i * 0.03), 1.0)
        ..addLook(math.sin(i * 0.11) * 6.0, math.cos(i * 0.07) * 3.0);
      if (i % 40 == 0) input.press(ShooterActions.fire);
      // Twice, four steps apart: the first is taken on the ground and consumed
      // at once, the second lands while the player is in the air and sits in
      // the jump buffer — which is the only way that field is ever non-zero
      // when somebody looks at it.
      if (i % 97 == 0 || i % 97 == 4) input.press(GameAction.jump);
      sim.step(_dt);
      input.endStep();
    }
  }
}

String _canonical(Snapshot snapshot) => jsonEncode(snapshot.toJson());

void main() {
  group('the format', () {
    test('a snapshot from a newer build is refused, not misread', () {
      // The same rule the level format follows, and for the same reason: a
      // save whose fields have changed meaning restores a game that is subtly
      // wrong, and subtly wrong is worse than refused.
      expect(
        () => Snapshot.fromJson(<String, Object?>{
          'version': Snapshot.formatVersion + 1,
        }),
        throwsA(isA<SnapshotFormatException>()),
      );
    });

    test('something that is not a snapshot is refused too', () {
      expect(
        () =>
            Snapshot.fromJson(<String, Object?>{'player': <String, Object?>{}}),
        throwsA(isA<SnapshotFormatException>()),
      );
    });

    test('a snapshot from an older build is read', () {
      // Read rather than refused: only a *newer* document is a refusal, since
      // an older one's fields still mean what they meant.
      //
      // **This used to assert `data['version'] == 1`**, which was a claim
      // about the envelope made from inside the payload — `fromJson` handed
      // back the document it was given, header and all, so a system reading
      // its own fields also got a key belonging to the format. It takes the
      // header off now, and what is worth asserting is what a game actually
      // gets: its own fields, and nothing thrown.
      final older = Snapshot.fromJson(<String, Object?>{
        'version': 1,
        'player': <String, Object?>{'health': 42},
      });

      expect(older.data.containsKey(Snapshot.versionKey), isFalse);
      expect(older.data['player'], <String, Object?>{'health': 42});
    });

    test('it survives being written to text and read back', () {
      final world = _World()..play(90);
      final written = jsonEncode(world.sim.save().toJson());
      final read = Snapshot.fromJson(
        jsonDecode(written) as Map<String, Object?>,
      );
      expect(jsonEncode(read.toJson()), written);
    });
  });

  group('a round trip', () {
    test('puts the player back where and how they were', () {
      final world = _World()..play(120);
      final taken = world.sim.save();
      final wasAt = world.player.body.position.clone();
      final wasFacing = world.player.yaw;
      final hadRockets = world.player.inventory.arsenal.ammoOf(
        AmmoType.rockets,
      );

      world.play(120, from: 120);
      // That the world moved on at all, rather than that the player did: with
      // a monster in their face the player can be pinned in one spot for two
      // seconds, and an assertion about their position would then be measuring
      // the fight rather than the restore.
      expect(
        _canonical(world.sim.save()),
        isNot(_canonical(taken)),
        reason: 'nothing happened, so putting it back proves nothing',
      );

      world.sim.restore(taken);
      expect(world.player.body.position.x, closeTo(wasAt.x, 1e-6));
      expect(world.player.body.position.z, closeTo(wasAt.z, 1e-6));
      expect(world.player.yaw, closeTo(wasFacing, 1e-9));
      expect(
        world.player.inventory.arsenal.ammoOf(AmmoType.rockets),
        hadRockets,
      );
    });

    test('puts the mechanisms back', () {
      final world = _World()..play(150);
      final ledge = world.mechanisms['ledge']! as MovingPlatform;
      final taken = world.sim.save();
      final wasAt = ledge.progress;

      world.play(150, from: 150);
      world.sim.restore(taken);

      expect(ledge.progress, closeTo(wasAt, 1e-6));
      expect(
        ledge.collider.position.y,
        closeTo(0.25 + wasAt * 2.0, 1e-5),
        reason:
            'the body has to move with the number, or the platform is '
            'drawn where it is not',
      );
    });

    test(
      'a monster killed before the save is still dead, and still not a wall',
      () {
        // Mutation: drop the collider-kind line in `Monster.restore`. Every
        // corpse you walked over becomes solid again on load, and this fails.
        final world = _World();
        final victim = world.actors.actors.first;
        world.actors.hurt(victim, 10000.0);
        final taken = world.sim.save();

        victim.body!.collider.kind = ColliderKind.kinematic;
        world.sim.restore(taken);

        expect(victim.isAlive, isFalse);
        expect(victim.body!.collider.kind, ColliderKind.trigger);
      },
    );

    test('a pickup taken before the save is not standing there again', () {
      final world = _World();
      final medkit = world.mechanisms['medkit']! as Pickup;
      // A medkit refused at full health is not a medkit taken.
      world.player.applyDamage(40.0);
      medkit.activate(Activation(by: world.player.body.collider));
      expect(medkit.isTaken, isTrue);

      final taken = world.sim.save();
      world.sim.restore(taken);
      expect(medkit.isTaken, isTrue);
    });
  });

  group('determinism', () {
    test('the same seed and the same script give the same world', () {
      final a = _World(seed: 11)..play(400);
      final b = _World(seed: 11)..play(400);
      expect(_canonical(a.sim.save()), _canonical(b.sim.save()));
    });

    test('a different seed gives a different one', () {
      // Otherwise the test above proves only that nothing random happens.
      final a = _World(seed: 11)..play(400);
      final b = _World(seed: 12)..play(400);
      expect(_canonical(a.sim.save()), isNot(_canonical(b.sim.save())));
    });

    test('one extra press is enough to tell two runs apart', () {
      // The half that stops the test above from passing for the wrong reason.
      // A jump rather than a shot, because the script already fires on the
      // first step and the launcher's cooldown swallows anything sooner than a
      // second — an "extra" press that changes nothing would have proved
      // nothing, which is what the first version of this did.
      final a = _World(seed: 11)..play(200);

      // At step sixty, on the ground: the script itself jumps on step zero, so
      // a press five steps later would land in the jump buffer, expire, and
      // change nothing — which is what the first version of this did, and it
      // passed for that reason rather than for a good one.
      final b = _World(seed: 11)..play(60);
      b.input.press(GameAction.jump);
      b.play(140, from: 60);

      expect(_canonical(a.sim.save()), isNot(_canonical(b.sim.save())));
    });
  });

  group('a restored world plays out exactly as the one it was taken from', () {
    // **The one that finds what the others cannot.** Everything a snapshot
    // leaves out shows up here within a few steps of the restore: a cooldown, a
    // state timer, the jump buffer, a rocket in flight, where the dice were.
    //
    // **Several save points, and that is not thoroughness for its own sake.**
    // The first version of this took one snapshot at step 240 and claimed to
    // catch anything missing. It caught almost nothing: at that particular step
    // no monster was mid-swing, no jump was buffered, and every rocket fired so
    // far had already hit a wall — so four fields could be deleted from the
    // format and the test still passed. A field is only under test at a moment
    // when it is not zero.
    //
    // The points below are chosen against the script: just after each shot,
    // when a rocket is still in the air; just after a detonation, when
    // something is staggered; just after a jump; and in the middle of the
    // platform's wait.
    //
    // **Three fields are still saved without being pinned here, and pretending
    // otherwise would be worse than saying so.** Deleting `jumpBuffer`,
    // `stateTime` or `noticed` from the format leaves every test in this file
    // green. Each is genuinely wrong to omit — a press swallowed a frame before
    // landing, a stagger that ends at the wrong moment, a monster that forgets
    // it was shot from behind — and each is observable only in a window a few
    // steps wide that none of these save points happens to land in. Chasing
    // them with more save points is tuning a test until it passes for reasons
    // nobody can state; the gap is named instead.
    for (final at in <int>[65, 82, 90, 102, 163, 175, 199, 245]) {
      test('taken at step $at', () {
        final world = _World(seed: 3)..play(at);
        final taken = world.sim.save();

        world.play(200, from: at);
        final playedOn = _canonical(world.sim.save());

        world.sim.restore(taken);
        world.play(200, from: at);

        expect(_canonical(world.sim.save()), playedOn);
      });
    }
  });
}
