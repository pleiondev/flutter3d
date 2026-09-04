/// Monsters that arrive, and the room that is clear when they are dead.
///
///     flutter test test/spawner_test.dart
///
/// What a level could not say before: "three of these when the door opens, and
/// two more four seconds later". Every monster was placed by the document and
/// stood where it was placed, so a room held whatever it held.
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_game_shooter/sample.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

({Spawner spawner, ActorSystem actors, MechanismWorld mechanisms}) _room(
  List<Wave> waves,
) {
  final world = CollisionWorld()
    ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(80.0, 1.0, 80.0))
    ..update();
  final random = GameRandom(1);
  final actors = ActorSystem(world: world, random: random);
  final mechanisms = MechanismWorld(world);
  final spawner = Spawner(
    name: 'ambush',
    at: Vector3.zero(),
    waves: waves,
    bestiary: Bestiary(
      actors: actors,
      shot: WeaponShot(
        world: world,
        hitscan: Hitscan(world: world, random: random),
        projectiles: ProjectileSystem(world: world),
      ),
      catalog: Monsters.byName,
    ),
  );
  mechanisms.add(spawner);
  return (spawner: spawner, actors: actors, mechanisms: mechanisms);
}

void main() {
  test('nothing arrives until it is asked', () {
    final it = _room(<Wave>[const Wave(monster: Monsters.runner, count: 2)]);

    for (var i = 0; i < 120; i++) {
      it.mechanisms.step(_dt);
    }

    expect(it.spawner.spawned, isEmpty);
    expect(it.actors.actors, isEmpty);
  });

  test('and a wave due immediately arrives on the step it is asked', () {
    // A door that opens onto an ambush opens onto it, rather than onto an
    // empty room that fills a frame later.
    final it = _room(<Wave>[const Wave(monster: Monsters.runner, count: 3)]);

    it.spawner.activate(const Activation());

    expect(it.spawner.spawned, hasLength(3));
  });

  test('a later wave waits for its own clock', () {
    final it = _room(<Wave>[
      const Wave(monster: Monsters.runner),
      const Wave(monster: Monsters.runner, count: 2, after: 2.0),
    ]);

    it.spawner.activate(const Activation());
    expect(it.spawner.spawned, hasLength(1));
    expect(it.spawner.isDone, isFalse);

    for (var i = 0; i < 60; i++) {
      it.mechanisms.step(_dt);
    }
    expect(it.spawner.spawned, hasLength(1), reason: 'a second early');

    for (var i = 0; i < 90; i++) {
      it.mechanisms.step(_dt);
    }

    expect(it.spawner.spawned, hasLength(3));
    expect(it.spawner.isDone, isTrue);
  });

  test('asking twice spawns nothing the second time', () {
    // A spawner that can be triggered twice is a room a player can farm.
    final it = _room(<Wave>[const Wave(monster: Monsters.runner, count: 2)]);

    expect(it.spawner.activate(const Activation()), isA<Activated>());
    expect(it.spawner.activate(const Activation()), isA<NothingToDo>());
    expect(it.spawner.spawned, hasLength(2));
  });

  test('a wave of several is placed apart rather than in one heap', () {
    // Several bodies at one point are several bodies the solver has to push
    // out of each other, and what a player sees is a knot shoving itself
    // across the room before anything walks.
    final it = _room(<Wave>[const Wave(monster: Monsters.runner, count: 4)])
      ..spawner.activate(const Activation());

    final places = it.spawner.spawned
        .map((Actor a) => a.position!)
        .toList(growable: false);
    for (var i = 1; i < places.length; i++) {
      expect(places[i].distanceTo(places[0]), greaterThan(0.5));
    }
  });

  test('a saved crypt does not re-arm what it already spent', () {
    final it = _room(<Wave>[const Wave(monster: Monsters.runner, count: 2)])
      ..spawner.activate(const Activation());
    final saved = it.spawner.save();

    final other = _room(<Wave>[const Wave(monster: Monsters.runner, count: 2)])
      ..spawner.restore(saved);

    expect(other.spawner.isSpent, isTrue);
    expect(
      other.spawner.spawned,
      isEmpty,
      reason: 'restoring the list would double every monster the world holds',
    );

    for (var i = 0; i < 120; i++) {
      other.mechanisms.step(_dt);
    }
    expect(other.spawner.spawned, isEmpty);
  });
}
