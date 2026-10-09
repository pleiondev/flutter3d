/// What a step says happened, and in what order.
///
///     flutter test test/shooter/events_test.dart
///
/// The seam that replaces a per-step field for each kind of moment. Two things
/// the fields could not do are the subject here, and both are measured through
/// the simulation rather than asserted about the buffer:
///
///  * **More than one of a thing.** A shotgun landing eight pellets was one
///    `firedThisStep` and a list of hits that only the shooter kept; a step
///    that killed three monsters was a number in a tally.
///  * **Order across subsystems.** A shot fired by this package and a death
///    recorded by `flutter3d_sim` went into two collections owned by two
///    objects, and nothing said which came first. They are now published onto
///    one bus, where each happens.
library;

import 'package:flutter3d_demo_content/shooter_sample.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'heard_events.dart';

const double _dt = 1.0 / 60.0;

/// A monster a stride in front of a player holding [weapon], and one step.
///
/// The same shape `berserk_test.dart` uses, and placed by its centre for the
/// same reason: `MonsterKind` lifts an authored position by half the height,
/// and a capsule with its middle in the floor is shot over the top of.
({GameSimulation sim, Actor monster, HeardEvents heard}) _oneShot(
  WeaponDef weapon, {
  MonsterDef target = Monsters.runner,
}) {
  final world = CollisionWorld()
    ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(60.0, 1.0, 60.0));
  final random = GameRandom(7);
  final actors = ActorSystem(world: world, random: random);
  final shot = WeaponShot(
    world: world,
    hitscan: Hitscan(world: world, random: random),
    projectiles: ProjectileSystem(world: world),
  );
  final monster = Bestiary(
    actors: actors,
    shot: shot,
    catalog: Monsters.byName,
  ).spawn(target, Vector3(0.0, target.height / 2.0, -1.6));

  final input = InputState();
  final player = Player(
    body: CharacterController(world: world, position: Vector3(0.0, 0.9, 0.0)),
    inventory: Inventory(
      arsenal: Arsenal(
        slots: <WeaponDef>[weapon],
        ammo: <AmmoType, int>{AmmoType.bullets: 99, AmmoType.shells: 99},
      ),
    ),
  );
  world.update();

  final sim = GameSimulation(
    random: random,
    player: player,
    collision: world,
    input: input,
    actors: actors,
    shot: shot,
    zones: const HitZones.even(),
  );
  final heard = HeardEvents(sim);
  input.press(ShooterActions.fire);
  sim.step(_dt);
  return (sim: sim, monster: monster, heard: heard);
}

void main() {
  group('one step, many events', () {
    test('a shotgun reports every pellet that landed', () {
      // The measurement the old shape could not make. `firedThisStep` is one
      // weapon whatever the spread does, so a game drawing an impact mark per
      // pellet had to reach into `sim.hits` — a second collection, cleared on
      // a different line, that only this package published.
      final it = _oneShot(Weapons.shotgun, target: Monsters.tank);
      final events = it.heard.take();

      final fired = events.whereType<ShotFired>().toList();
      final landed = events.whereType<ShotLanded>().toList();

      expect(fired, hasLength(1), reason: 'one trigger pull is one shot');
      expect(
        landed.length,
        greaterThan(1),
        reason: 'a shotgun that reports one hit is reporting a pellet',
      );
    });

    test('taking twice gives nothing the second time', () {
      final it = _oneShot(Weapons.pistol);

      expect(it.heard.take(), isNotEmpty);
      expect(it.heard.take(), isEmpty);
    });
  });

  group('order across subsystems', () {
    test('a shot is reported before the death it caused', () {
      // The whole reason the bus is handed down to `ActorSystem` instead of
      // its `died` list being read afterwards. Both orderings look identical
      // to a reader of two collections; only one of them is true.
      final it = _oneShot(Weapons.shotgun, target: Monsters.runner);
      final events = it.heard.take();

      final shot = events.indexWhere((GameEvent e) => e is ShotFired);
      final died = events.indexWhere((GameEvent e) => e is ActorDied);

      expect(shot, isNonNegative, reason: 'nothing was fired');
      expect(died, isNonNegative, reason: 'the runner survived a shotgun');
      expect(shot, lessThan(died));
    });

    test('and the death names who caused it', () {
      final it = _oneShot(Weapons.shotgun, target: Monsters.runner);
      final died = it.heard.take().whereType<ActorDied>().single;

      expect(identical(died.actor, it.monster), isTrue);
      expect(died.from, isNotNull, reason: 'killed by nobody');
    });
  });

  group('a game with an event of its own', () {
    // The point of the base type being open. Nothing in either package knows
    // `_TorchLit` exists; it travels on the same bus, in order, beside
    // events from two packages that have never heard of it.
    test('puts it on the same bus, in order', () {
      final it = _oneShot(Weapons.pistol);
      it.heard.bus.publish(const _TorchLit('north sconce'));
      final events = it.heard.take();

      expect(events.last, isA<_TorchLit>());
      expect(events.whereType<ShotFired>(), hasLength(1));
    });
  });

  group('a simulation nobody listens to', () {
    // The normal case for every headless test in this repository: with no
    // bus there is nothing kept, so a long game grows nothing for a program
    // that never asked for events at all.
    test('steps, and is heard from the moment a bus is named', () {
      final it = _oneShot(Weapons.pistol);
      final quiet = GameSimulation(
        random: GameRandom(1),
        player: it.sim.player,
        collision: it.sim.collision,
        input: InputState(),
      )..hurtPlayer(1.0);
      final heard = HeardEvents(quiet);
      quiet.hurtPlayer(1.0);

      // Mutation: events kept from before a bus was named.
      expect(heard.take().whereType<PlayerHurt>(), hasLength(1));
    });
  });

  group('for a rule hung on the step', () {
    test('the shot is read without draining what the game reads', () {
      final it = _oneShot(Weapons.shotgun, target: Monsters.tank);
      final seen = it.sim.shotEvents;
      // Mutation: the shot not kept in `_fire` — a system reading it finds
      // nothing on the step a trigger was pulled.
      expect(seen.first, isA<ShotFired>());
      expect(seen.whereType<ShotLanded>(), isNotEmpty);
      // The bus heard the same events in the same order.
      final heard = it.heard.take();
      expect(
        heard.where((e) => e is ShotFired || e is ShotLanded).toList(),
        seen,
      );
      // Mutation: not cleared at the top of `step` — a step with the
      // trigger let go still reports the last shot.
      it.sim.input.release(ShooterActions.fire);
      it.sim.step(_dt);
      expect(it.sim.shotEvents, isEmpty);
    });

    test('harm through the one door is scaled and heard', () {
      final world = CollisionWorld()
        ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(20.0, 1.0, 20.0));
      final player = Player(
        body: CharacterController(
          world: world,
          position: Vector3(0.0, 0.9, 0.0),
        ),
        inventory: Inventory(),
      );
      final sim = GameSimulation(
        random: GameRandom(1),
        player: player,
        collision: world,
        input: InputState(),
        difficulty: const Difficulty('hard', damageTaken: 2.0),
      );
      final heard = HeardEvents(sim);
      final full = player.inventory.health.current;
      sim.hurtPlayer(10.0);
      // Mutation: the difficulty's scale not applied — ten taken, not
      // twenty.
      expect(player.inventory.health.current, full - 20.0);
      // Mutation: the harm not reported — nothing on the bus.
      expect(heard.take().whereType<PlayerHurt>().single.amount, 20.0);
      sim.hurtPlayer(full);
      // Mutation: the death not reported on the step it happens.
      expect(heard.take().whereType<PlayerDied>(), hasLength(1));
    });
  });
}

/// An event this repository does not have, written as a game would write it.
final class _TorchLit extends GameEvent {
  const _TorchLit(this.where);

  final String where;

  @override
  String get name => 'game.torchLit';
}
