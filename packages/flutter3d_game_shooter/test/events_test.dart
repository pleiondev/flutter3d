/// What a step says happened, and in what order.
///
///     flutter test test/events_test.dart
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
///    objects, and nothing said which came first. They now go into one buffer,
///    written where each happens.
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_game_shooter/sample.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

/// A monster a stride in front of a player holding [weapon], and one step.
///
/// The same shape `berserk_test.dart` uses, and placed by its centre for the
/// same reason: `MonsterKind` lifts an authored position by half the height,
/// and a capsule with its middle in the floor is shot over the top of.
({GameSimulation sim, Actor monster}) _oneShot(
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
  input.press(ShooterActions.fire);
  sim.step(_dt);
  return (sim: sim, monster: monster);
}

void main() {
  group('one step, many events', () {
    test('a shotgun reports every pellet that landed', () {
      // The measurement the old shape could not make. `firedThisStep` is one
      // weapon whatever the spread does, so a game drawing an impact mark per
      // pellet had to reach into `sim.hits` — a second collection, cleared on
      // a different line, that only this package published.
      final it = _oneShot(Weapons.shotgun, target: Monsters.tank);
      final events = it.sim.events.drain();

      final fired = events.whereType<ShotFired>().toList();
      final landed = events.whereType<ShotLanded>().toList();

      expect(fired, hasLength(1), reason: 'one trigger pull is one shot');
      expect(
        landed.length,
        greaterThan(1),
        reason: 'a shotgun that reports one hit is reporting a pellet',
      );
    });

    test('draining twice gives nothing the second time', () {
      final it = _oneShot(Weapons.pistol);

      expect(it.sim.events.drain(), isNotEmpty);
      expect(it.sim.events.drain(), isEmpty);
    });
  });

  group('order across subsystems', () {
    test('a shot is reported before the death it caused', () {
      // The whole reason the buffer is handed down to `ActorSystem` instead of
      // its `died` list being read afterwards. Both orderings look identical
      // to a reader of two collections; only one of them is true.
      final it = _oneShot(Weapons.shotgun, target: Monsters.runner);
      final events = it.sim.events.drain();

      final shot = events.indexWhere((GameEvent e) => e is ShotFired);
      final died = events.indexWhere((GameEvent e) => e is ActorDied);

      expect(shot, isNonNegative, reason: 'nothing was fired');
      expect(died, isNonNegative, reason: 'the runner survived a shotgun');
      expect(shot, lessThan(died));
    });

    test('and the death names who caused it', () {
      final it = _oneShot(Weapons.shotgun, target: Monsters.runner);
      final died = it.sim.events.drain().whereType<ActorDied>().single;

      expect(identical(died.actor, it.monster), isTrue);
      expect(died.from, isNotNull, reason: 'killed by nobody');
    });
  });

  group('a game with an event of its own', () {
    // The point of the base type being open. Nothing in either package knows
    // `_TorchLit` exists; it travels in the same buffer, in order, beside
    // events from two packages that have never heard of it.
    test('puts it in the same buffer, in order', () {
      final it = _oneShot(Weapons.pistol);
      it.sim.events.add(const _TorchLit('north sconce'));
      final events = it.sim.events.drain();

      expect(events.last, isA<_TorchLit>());
      expect(events.whereType<ShotFired>(), hasLength(1));
    });
  });

  group('a buffer nobody drains', () {
    // The normal case for every headless test in this repository, and the
    // reason the buffer is capped: a simulation that grows a list for the
    // whole of a long game runs out of memory, and it would do it in a
    // program that never asked for events at all.
    test('keeps the newest and counts what it dropped', () {
      final events = GameEvents(limit: 4);
      for (var i = 0; i < 10; i++) {
        events.add(_TorchLit('$i'));
      }

      final kept = events.drain().cast<_TorchLit>().map((e) => e.where);
      expect(kept, <String>['6', '7', '8', '9']);
      expect(events.dropped, 6);
    });

    test('and a buffer that is drained drops nothing', () {
      final events = GameEvents(limit: 4);
      for (var i = 0; i < 10; i++) {
        events
          ..add(_TorchLit('$i'))
          ..drain();
      }

      expect(events.dropped, 0);
    });
  });
}

/// An event this repository does not have, written as a game would write it.
final class _TorchLit extends GameEvent {
  const _TorchLit(this.where);

  final String where;

  @override
  String get name => 'torch lit ($where)';
}
