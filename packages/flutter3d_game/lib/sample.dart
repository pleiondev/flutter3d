/// The roster this repository's own game ships with.
///
/// **Not part of the engine's surface.** `flutter3d_game.dart` does not export
/// this library, so a game depending on the package gets none of it unless it
/// asks — `import 'package:flutter3d_game/sample.dart';` — and a second game
/// that wants its own monsters simply does not.
///
/// It stays inside the package rather than moving to `apps/dungeon` for one
/// reason: the tests. Two hundred of them are written against these numbers,
/// and a roster is exactly what a test of an arsenal, a monster system or a
/// level validator needs to have lying about. Moving the data would have
/// churned seventy-odd references for no behavioural change and left the tests
/// inventing a fresh roster each time.
///
/// What matters is that nothing in `lib/src/` reads any of it. The seam is the
/// deliverable; where the sample content sits is bookkeeping.
library;

import 'package:vector_math/vector_math.dart';

import 'src/actors/monster.dart';
import 'src/combat/weapon.dart';
import 'src/combat/weapon_behaviour.dart';
import 'src/level/entity_kind.dart';
import 'src/world/gift.dart';
import 'src/world/light_fixture.dart';

/// The roster.
abstract final class Monsters {
  /// Fast, fragile, and always in your face. The state machine's simplest case
  /// and the one that sets the game's tempo.
  static const MonsterDef runner = MonsterDef(
    name: 'runner',
    health: 45.0,
    speed: 5.4,
    radius: 0.35,
    height: 1.7,
    sightRange: 24.0,
    attack: WeaponDef(
      name: 'claws',
      behaviour: MeleeBehaviour(),
      ammo: AmmoType.none,
      damage: 9.0,
      shotsPerSecond: 1.6,
      range: 1.9,
      automatic: true,
    ),
  );

  /// Keeps its distance and throws something slow enough to dodge, which is
  /// what makes the room's geometry matter.
  static const MonsterDef shooter = MonsterDef(
    name: 'shooter',
    health: 60.0,
    speed: 3.0,
    radius: 0.38,
    height: 1.8,
    sightRange: 30.0,
    attack: WeaponDef(
      name: 'fireball',
      behaviour: ProjectileBehaviour(),
      ammo: AmmoType.none,
      damage: 22.0,
      shotsPerSecond: 0.55,
      range: 30.0,
      projectileSpeed: 13.0,
      splashRadius: 2.2,
      splashMinimumFraction: 0.2,
    ),
  );

  /// Slow, heavy, and largely indifferent to being shot.
  static const MonsterDef tank = MonsterDef(
    name: 'tank',
    health: 320.0,
    speed: 2.2,
    radius: 0.62,
    height: 2.4,
    sightRange: 22.0,
    painChance: 0.15,
    painCooldown: 1.4,
    hurtDuration: 0.18,
    attack: WeaponDef(
      name: 'slam',
      behaviour: MeleeBehaviour(arcDegrees: 100.0),
      ammo: AmmoType.none,
      damage: 34.0,
      shotsPerSecond: 0.7,
      range: 2.6,
      automatic: true,
    ),
  );

  static const Map<String, MonsterDef> byName = <String, MonsterDef>{
    'runner': runner,
    'shooter': shooter,
    'tank': tank,
  };
}

/// The weapons this game ships with.
///
/// Ordered as they appear on the keyboard, so slot and index are the same
/// thing and nothing has to map between them.
abstract final class Weapons {
  /// Free, short, and the reason running out of ammo is a setback rather than
  /// a dead end.
  static const WeaponDef fists = WeaponDef(
    name: 'Fists',
    behaviour: MeleeBehaviour(),
    ammo: AmmoType.none,
    damage: 20.0,
    shotsPerSecond: 2.0,
    range: 2.2,
    automatic: true,
  );

  static const WeaponDef pistol = WeaponDef(
    name: 'Pistol',
    behaviour: HitscanBehaviour(),
    ammo: AmmoType.bullets,
    damage: 14.0,
    shotsPerSecond: 4.0,
    range: 120.0,
    falloffStart: 25.0,
    falloffEnd: 70.0,
    minimumDamageFraction: 0.4,
  );

  /// Eight pellets, and all of the reason to close the distance.
  static const WeaponDef shotgun = WeaponDef(
    name: 'Shotgun',
    behaviour: HitscanBehaviour(),
    ammo: AmmoType.shells,
    damage: 11.0,
    shotsPerSecond: 1.4,
    rayCount: 8,
    spread: 0.10,
    range: 60.0,
    falloffStart: 6.0,
    falloffEnd: 26.0,
    minimumDamageFraction: 0.2,
    knockback: 2.0,
  );

  static const WeaponDef rocketLauncher = WeaponDef(
    name: 'Rocket Launcher',
    behaviour: ProjectileBehaviour(),
    ammo: AmmoType.rockets,
    damage: 90.0,
    shotsPerSecond: 0.9,
    range: 200.0,
    knockback: 9.0,
    projectileSpeed: 34.0,
    splashRadius: 4.5,
    splashMinimumFraction: 0.15,
  );

  /// In keyboard order: slot n is `all[n]`.
  static const List<WeaponDef> all = <WeaponDef>[
    fists,
    pistol,
    shotgun,
    rocketLauncher,
  ];
}


/// What a pickup in this game's levels may give.
final GiftRegistry sampleGifts = GiftRegistry(<Gift>[
  const HealthGift(),
  const ArmourGift(),
  const AmmoGift('bullets', AmmoType.bullets, defaultAmount: 20.0),
  const AmmoGift('shells', AmmoType.shells, defaultAmount: 8.0),
  const AmmoGift('rockets', AmmoType.rockets, defaultAmount: 4.0),
  const KeyGift(),
  const PowerUpGift('invulnerability', defaultAmount: 20.0),
  const PowerUpGift('berserk', defaultAmount: 30.0),
]);

/// What this game's own entity types are called in a document.
///
/// The format's own vocabulary is [EntityTypes]; these three are furniture, and
/// they live beside the kinds that implement them.
abstract final class SampleEntities {
  static const String torch = 'torch';
  static const String lamp = 'lamp';
  static const String window = 'window';
}

/// The three lights this game's levels use.
///
/// Furniture, not vocabulary: a torch is a `LightFixtureKind` with a flicker
/// and a size, and both of those are data. They were three subclasses in the
/// engine until the day the engine stopped being one game's.
List<EntityKind> sampleLightKinds() => <EntityKind>[
      LightFixtureKind(
        SampleEntities.torch,
        defaultBehaviour: const FlameFlicker(),
        defaultSize: Vector3(0.22, 0.5, 0.22),
      ),
      LightFixtureKind(
        SampleEntities.lamp,
        defaultBehaviour: const SteadyLight(),
        defaultSize: Vector3(0.34, 0.34, 0.34),
      ),
      LightFixtureKind(
        SampleEntities.window,
        defaultBehaviour: const SteadyLight(),
        defaultSize: Vector3(1.4, 2.2, 0.12),
      ),
    ];

/// Everything above, assembled the way this game's levels expect.
EntityRegistry sampleRegistry() => EntityRegistry.forGame(
      monsters: Monsters.byName,
      gifts: sampleGifts,
      extra: sampleLightKinds(),
    );

/// The loadout this game's player starts with.
///
/// `Arsenal` used to default to exactly this, which meant a package that should
/// not know the game has fists shipped its opening inventory. The numbers are
/// unchanged; only where they live is.
Arsenal sampleArsenal({int startingSlot = 0}) => Arsenal(
      slots: Weapons.all,
      owned: <WeaponDef>[Weapons.fists, Weapons.pistol],
      ammo: <AmmoType, int>{AmmoType.bullets: 40},
      startingSlot: startingSlot,
    );
