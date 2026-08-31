/// Monsters that hurt each other stop being on the same side.
///
///     flutter test test/infighting_test.dart
///
/// **Monsters could not hurt each other at all.** A monster's shot collected
/// what it hit and then counted the damage only if the thing hit was the focus,
/// so a fireball crossing a room passed through anything standing in the way.
/// The classic thing a crowded room does — one shot going wide, two of them
/// falling out, the player walking round the argument — was not slow or rare
/// here; it was impossible.
///
/// Two halves make it work, and they are in different packages on purpose. The
/// engine learned who dealt damage: `Damageable.applyDamage(amount, from:)`, an
/// `Object?` because an engine has no business knowing what a monster is. The
/// genre decided what to do about it, which is this file's subject.
library;


import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_game_shooter/sample.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

/// A floor and nothing else, so that seeing is never the question.
({ActorSystem system, Bestiary bestiary, Vector3 eye}) _room({int seed = 1}) {
  final world = CollisionWorld()
    ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(80.0, 1.0, 80.0))
    ..update();
  final random = GameRandom(seed);
  final system = ActorSystem(world: world, random: random);
  return (
    system: system,
    bestiary: Bestiary(
      actors: system,
      shot: WeaponShot(
        world: world,
        hitscan: Hitscan(world: world, random: random),
        projectiles: ProjectileSystem(world: world),
      ),
      catalog: Monsters.byName,
    ),
    // The player, far enough away to be nobody's business here.
    eye: Vector3(0.0, 0.7, 60.0),
  );
}

ChaseBrain _brainOf(Actor actor) => actor.brain! as ChaseBrain;

/// Steps the actors, having first told the world where everything is.
///
/// **The reindex is not a detail of this file.** In the game it is
/// `WorldStep.index`, which every genre calls before anything sweeps; a test
/// that drives `ActorSystem` directly has to do it itself, and without it a
/// body spawned this step is invisible to the broadphase — so a swing that
/// should land finds an empty room and the whole file passes for the wrong
/// reason.
void _step(ActorSystem system, Vector3 focus, {int times = 1}) {
  for (var i = 0; i < times; i++) {
    system.world.reindex();
    system.beginStep();
    system.step(_dt, focus: focus);
    system.world.update();
  }
}

void main() {
  test('a monster hurt by another one turns on it', () {
    final it = _room();
    final hurt = it.bestiary.spawn(Monsters.runner, Vector3(0.0, 0.0, 0.0));
    final culprit = it.bestiary.spawn(Monsters.runner, Vector3(4.0, 0.0, 0.0));

    // The engine's own call, which is what a stray shot arrives as.
    hurt.applyDamage(10.0, from: culprit);

    expect(_brainOf(hurt).quarrel, same(culprit),
        reason: 'it took the shot and went on chasing the player');
  });

  test('and a monster hurt by the player does not', () {
    // The half that matters more: a monster that turned on whoever hit it
    // would turn on the player's neighbour every time they landed a shot, and
    // then walk away from the person shooting it.
    final it = _room();
    final monster = it.bestiary.spawn(Monsters.runner, Vector3.zero());

    // What the simulation passes for a hitscan: the player, which is not an
    // actor.
    monster.applyDamage(10.0, from: Object());

    expect(_brainOf(monster).quarrel, isNull);
  });

  test('and damage from nobody leaves it alone', () {
    // A pit, a crushing lift, a fall. `from` is null and there is nothing to
    // turn on — which is why a brain has to handle that rather than assume a
    // culprit.
    final it = _room();
    final monster = it.bestiary.spawn(Monsters.runner, Vector3.zero());

    monster.applyDamage(5.0);

    expect(_brainOf(monster).quarrel, isNull);
  });

  test('and it walks towards the one it is fighting, not towards the player',
      () {
    final it = _room();
    final hurt = it.bestiary.spawn(Monsters.runner, Vector3(0.0, 0.0, 0.0));
    final culprit = it.bestiary.spawn(Monsters.runner, Vector3(-12.0, 0.0, 0.0));
    hurt.applyDamage(10.0, from: culprit);

    final startedAt = hurt.position!.clone();
    _step(it.system, it.eye, times: 120);

    // The player is sixty metres along +z and the quarrel twelve along -x. A
    // monster still chasing the focus would have gone the other way entirely.
    final moved = hurt.position! - startedAt;
    expect(moved.x, lessThan(-0.5), reason: 'it did not go for the other one');
    expect(moved.z, lessThan(1.0), reason: 'it went for the player instead');
  });

  test('and the argument ends when one of them dies', () {
    final it = _room();
    final hurt = it.bestiary.spawn(Monsters.runner, Vector3(0.0, 0.0, 0.0));
    final culprit = it.bestiary.spawn(Monsters.runner, Vector3(-12.0, 0.0, 0.0));
    hurt.applyDamage(10.0, from: culprit);
    expect(_brainOf(hurt).quarrel, same(culprit));

    // Killed by something else entirely, which is the usual way an infight
    // ends: the player finishes one of them off.
    it.system.hurt(culprit, 10000.0);
    _step(it.system, it.eye);

    expect(_brainOf(hurt).quarrel, isNull,
        reason: 'it is still fighting a corpse');
  });

  test('and a monster shot by another one is hurt by it', () {
    // The whole chain rather than the engine call: one monster fires, the
    // other loses health and knows who did it. Before this, a monster's shot
    // touched nothing but the player.
    final it = _room();
    // Within a claw's reach of each other at the start: what is being tested
    // is that the swing lands on another monster at all, not how well one
    // walks up to another.
    final shooter = it.bestiary.spawn(Monsters.runner, Vector3(0.0, 0.0, 0.0));
    final victim = it.bestiary.spawn(Monsters.runner, Vector3(0.0, 0.0, -1.5));
    final before = victim.health!.current;

    // Point the shooter at the victim and let it swing: a grunt's attack is a
    // claw with a metre or two of reach.
    _brainOf(shooter).quarrel = victim;
    for (var i = 0; i < 240 && victim.health!.current >= before; i++) {
      _step(it.system, it.eye);
    }

    expect(victim.health!.current, lessThan(before),
        reason: 'the shot went through it');
    expect(_brainOf(victim).quarrel, same(shooter),
        reason: 'it was hit and did not notice by whom');
  });
}
