/// What `berserk` does, now that it does anything.
///
///     flutter test test/berserk_test.dart
///
/// **It was in the shipped gift registry, placed in no level, and
/// `Inventory.isBerserk` was read by nothing.** The power-up existed as far as
/// a document could name it and as far as the HUD could count it down, and the
/// crypt behaved identically whether it was running or not. This is the
/// effect, measured through the simulation rather than asserted about a
/// constant: a multiplier nobody puts a shot through is a multiplier that can
/// be applied in the wrong place.
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_game_shooter/sample.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

/// A monster standing a stride in front of a player holding [weapon], and the
/// step that shoots it.
///
/// Close enough for the fists as well as the pistol, so one harness measures
/// both arms of the delivery. Placed by its **centre** — `MonsterKind` lifts an
/// authored position by half the height and this has to do the same, or the
/// capsule stands with its middle in the floor and the first shot goes over
/// the top of it.
///
/// `HitZones.even()` so that the only thing separating the two runs below is
/// the power-up: the ray lands wherever the capsule happens to be, and a table
/// that pays for height would make the comparison a question about where the
/// crosshair sat.
double _damageOneShot(WeaponDef weapon, {required bool berserk}) {
  const target = Monsters.tank;
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

  final inventory = Inventory(
    arsenal: Arsenal(
      slots: <WeaponDef>[weapon],
      ammo: <AmmoType, int>{AmmoType.bullets: 99, AmmoType.shells: 99},
    ),
  );
  if (berserk) inventory.empower('berserk', 30.0);

  final input = InputState();
  final player = Player(
    body: CharacterController(world: world, position: Vector3(0.0, 0.9, 0.0)),
    inventory: inventory,
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

  final before = monster.health!.current;
  input.press(ShooterActions.fire);
  sim.step(_dt);
  return before - monster.health!.current;
}

void main() {
  test('doubles what a shot is worth, and nothing else does', () {
    // Mutation: drop the `* scale` from the `scale:` closure in
    // `GameSimulation._fire` — the two runs come back equal and this fails.
    // Changing `berserkDamage` alone also fails it, which is the point: the
    // number is a decision, and a decision that moves should be read.
    final plain = _damageOneShot(Weapons.pistol, berserk: false);
    final raging = _damageOneShot(Weapons.pistol, berserk: true);

    expect(
      plain,
      greaterThan(0.0),
      reason: 'the shot missed; nothing is being measured',
    );
    expect(raging, closeTo(plain * GameSimulation.berserkDamage, 1e-9));
  });

  test('and reaches the melee as well as the rays', () {
    // The point of scaling what is *delivered* rather than what a weapon says
    // it does: fists arrive through `MeleeBehaviour` and a pistol through
    // `HitscanBehaviour`, and a power-up honoured by one and not the other is
    // the bug report `Inventory.damage`'s own doc was written against.
    //
    // Mutation: as above. The fists are the arm of it that a change scoped to
    // `WeaponDef.damage` would have missed.
    final plain = _damageOneShot(Weapons.fists, berserk: false);
    final raging = _damageOneShot(Weapons.fists, berserk: true);

    expect(plain, greaterThan(0.0));
    expect(raging, closeTo(plain * GameSimulation.berserkDamage, 1e-9));
  });

  test('and the number crosses the swings the roster is built on', () {
    // The comment on `berserkDamage` argues from swings rather than from a
    // round figure, and this is that argument as arithmetic. It is what makes
    // the constant a decision instead of a default: at 1.5 the fists still
    // take three swings on a runner and the claim in that doc is false.
    //
    // Mutation: set `berserkDamage` to 1.5 and this fails on the first
    // expectation.
    int swings(double damage, double health) => (health / damage).ceil();
    final scaled = GameSimulation.berserkDamage;

    expect(swings(Weapons.fists.damage * scaled, Monsters.runner.health), 2);
    expect(swings(Weapons.fists.damage, Monsters.runner.health), 3);
    expect(swings(Weapons.pistol.damage * scaled, Monsters.runner.health), 2);
    expect(swings(Weapons.pistol.damage, Monsters.runner.health), 4);
  });
}
