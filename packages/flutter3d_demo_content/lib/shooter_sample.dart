/// The roster this repository's own shooter ships with.
///
/// **Not part of the engine's surface, and not published.** It was
/// `package:flutter3d_demo_content/shooter_sample.dart` until 1.0, public and so
/// under the genre's semver promise: one game's monsters held to the same
/// contract as the genre a second game builds its own on. It lives in this
/// unpublished package now, beside the dungeon that ships it and reachable
/// from the genre's tests, which are written against these numbers — a roster
/// is exactly what a test of an arsenal, a monster system or a level validator
/// needs to have lying about.
///
/// Nothing in the genre's `lib/` reads any of it. A game of your own copies
/// what it wants from here.
library;

import 'dart:math' as math;

import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

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
      loudness: 4.0,
      behavior: MeleeBehavior(),
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
      behavior: ProjectileBehavior(),
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
      loudness: 12.0,
      behavior: MeleeBehavior(arc: 100.0 * math.pi / 180.0),
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
    // Bare hands. Heard across a room and not through a wall.
    loudness: 5.0,
    name: 'Fists',
    behavior: MeleeBehavior(),
    ammo: AmmoType.none,
    damage: 20.0,
    shotsPerSecond: 2.0,
    range: 2.2,
    automatic: true,
  );

  static const WeaponDef pistol = WeaponDef(
    loudness: 16.0,
    name: 'Pistol',
    behavior: HitscanBehavior(),
    ammo: AmmoType.bullets,
    damage: 14.0,
    shotsPerSecond: 4.0,
    range: 120.0,
    falloffStart: 25.0,
    falloffEnd: 70.0,
    minimumDamageFraction: 0.4,
    // Half a degree a shot, back down in a fifth of a second. Four a second is
    // a rate a player can hold, so the sight flinches rather than climbing.
    recoil: 0.009,
  );

  /// Eight pellets, and all of the reason to close the distance.
  static const WeaponDef shotgun = WeaponDef(
    // The loudest thing a player carries, and the reason a corridor answers.
    loudness: 28.0,
    name: 'Shotgun',
    behavior: HitscanBehavior(),
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
    // A shove rather than a flinch, and slow to come back: the pause between
    // shells is what the weapon is, and it should be spent waiting for the
    // sight as much as for the pump.
    recoil: 0.05,
    recoilRecovery: 4.5,
  );

  static const WeaponDef rocketLauncher = WeaponDef(
    loudness: 26.0,
    name: 'Rocket Launcher',
    behavior: ProjectileBehavior(),
    ammo: AmmoType.rockets,
    damage: 90.0,
    shotsPerSecond: 0.9,
    range: 200.0,
    knockback: 9.0,
    projectileSpeed: 34.0,
    splashRadius: 4.5,
    splashMinimumFraction: 0.15,
    recoil: 0.045,
    recoilRecovery: 4.0,
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
  const ArmorGift(),
  const AmmoGift('bullets', AmmoType.bullets, defaultAmount: 20.0),
  const AmmoGift('shells', AmmoType.shells, defaultAmount: 8.0),
  const AmmoGift('rockets', AmmoType.rockets, defaultAmount: 4.0),
  const KeyGift(),
  const PowerUpGift('invulnerability', defaultAmount: 20.0),
  const PowerUpGift('berserk', defaultAmount: 30.0),
  // Shows what walks behind the walls, as silhouettes, for as long as it
  // lasts. A gift rather than a setting so that seeing through a wall is a
  // thing the level hands out and takes back — see `Inventory.hasSensor`.
  const PowerUpGift('sensor', defaultAmount: 30.0),
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
    defaultBehavior: const FlameFlicker(),
    defaultSize: Vector3(0.22, 0.5, 0.22),
  ),
  LightFixtureKind(
    SampleEntities.lamp,
    defaultBehavior: const SteadyLight(),
    defaultSize: Vector3(0.34, 0.34, 0.34),
  ),
  LightFixtureKind(
    SampleEntities.window,
    defaultBehavior: const SteadyLight(),
    defaultSize: Vector3(1.4, 2.2, 0.12),
  ),
];

/// Everything above, assembled the way this game's levels expect.
///
/// **An example of composing a vocabulary, not a default.** The package offers
/// kinds; which of them a game speaks is the game's own answer.
///
/// `monsters: false` is not a convenience — it is the shortest statement of
/// what the content seam is worth. A game without them gets a registry with no
/// `monster` in it, and the word stops being part of the language its levels
/// are written in.
///
/// [extra] is where an application adds a kind this package cannot know
/// about without depending on it — `wg-02`'s `WidgetSurfaceKind`
/// (`flutter3d_app`) is the reason this exists: a genre package must not
/// gain a dependency on the application layer just so its sample registry
/// can speak a word that layer, not the genre, defines.
EntityRegistry sampleRegistry({
  bool monsters = true,
  Iterable<EntityKind> extra = const <EntityKind>[],
}) => EntityRegistry(<EntityKind>[
  const PlayerSpawnKind(),
  if (monsters) MonsterKind(Monsters.byName),
  PickupKind(sampleGifts),
  const ShooterKeyKind(),
  const DoorKind(),
  const LiftKind(),
  const PlatformKind(),
  const ButtonKind(),
  const TriggerKind(),
  const NoteKind(),
  const SecretKind(),
  const ExitKind(),
  ...sampleLightKinds(),
  // The format's own word, spoken here because this game's rooms are lit
  // by torches and nothing else: a probe per room is what lets a key or
  // a barrel reflect the room it is in rather than a sky it cannot see.
  const ReflectionProbeKind(),
  const DecalKind(),
  const ReflectorKind(),
  const CameraScreenKind(),
  // Read for the dungeon's sixty steps a second.
  const CutsceneKind(stepsPerSecond: 60),
  ...extra,
]);

/// What this game asks of a level as a whole.
///
/// Two rules, and both are about *this* game rather than about the format: one
/// place to start, and a way to finish. A game that ends by script rather than
/// by walking into a door passes an empty list.
List<LevelRule> sampleRules() => <LevelRule>[
  const ExactlyOne(
    EntityTypes.playerSpawn,
    because:
        'the player would start at the origin, which is usually '
        'inside the floor',
  ),
  const AtLeastOne(EntityTypes.exit, because: 'the level cannot be finished'),
  // A monster's tree reads against the leaves this game's monsters have —
  // the standard ones — and a monster names a tree the level has.
  BehaviorsRead(BehaviorKinds()),
];

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

/// What the game sets on [actors] for walking to a point and round each
/// other, for [level]: a navigation mesh per width in the roster, on the
/// grid's quarter-metre lattice for the grid's reason — a one-metre corridor
/// is a corridor — and avoidance.
///
/// **In four-metre tiles**, so that a wall a rocket breaks is baked again
/// where it broke and nowhere else — see [followBreaches].
///
/// One function, called by both stagings and by the test that holds the
/// game to it, so that what is tested is what ships.
void stageRoutes(ActorSystem actors, Level level) {
  actors
    ..navMeshes = NavMesh.bakeLevelFor(level, <(double, double)>[
      for (final def in Monsters.byName.values) (def.radius, def.height),
    ], config: routeConfig)
    ..avoidance = const Avoidance();
}

/// The lattice and tiles the game's navigation meshes are baked on.
const NavMeshSettings routeConfig = NavMeshSettings(
  cellSize: 0.25,
  tileSize: 16,
  maxEdgeError: 0.45,
);

/// Keeps [actors]' navigation meshes, and the flow field's grid a chase
/// walks, on the level as [breaches] leave it: each hole bakes again the
/// part of every mesh and of the grid it changed, and a restore bakes the
/// ones [actors] had as authored again for every saved hole in turn, which
/// is the level with all of them baked whole.
///
/// In the step, where the hole is blown, so a replay meets the same mesh at
/// the same step.
void followBreaches(ActorSystem actors, Level level, Breaches breaches) {
  final authored = actors.navMeshes;
  final navigation = actors.navigation;
  final authoredGrid = navigation?.grid;
  List<Brush> standing() => expandRecipes(
    Level(
      name: level.name,
      brushes: breaches.brushes,
      heightfield: level.heightfield,
      recipes: level.recipes,
    ),
  ).brushes;
  NavMesh bakedAgain(NavMesh mesh, Aabb3 hole, List<Brush> brushes) =>
      mesh.rebake(
        brushes,
        ground: level.heightfield,
        minX: hole.min.x,
        minZ: hole.min.z,
        maxX: hole.max.x,
        maxZ: hole.max.z,
      );
  NavGrid gridAgain(NavGrid grid, Aabb3 hole, List<Brush> brushes) =>
      grid.rebake(
        brushes,
        minX: hole.min.x,
        minZ: hole.min.z,
        maxX: hole.max.x,
        maxZ: hole.max.z,
      );
  breaches
    ..onHole = (Aabb3 hole) {
      final brushes = standing();
      actors.navMeshes = <NavMesh>[
        for (final mesh in actors.navMeshes) bakedAgain(mesh, hole, brushes),
      ];
      // The chase's way too, or a monster that has seen the player walks
      // into the wall the patrol next to it now walks through.
      if (navigation != null) {
        navigation.grid = gridAgain(navigation.grid, hole, brushes);
      }
    }
    ..onRestore = () {
      final brushes = standing();
      actors.navMeshes = <NavMesh>[
        for (final mesh in authored)
          breaches.holes.fold(
            mesh,
            (NavMesh baked, Aabb3 hole) => bakedAgain(baked, hole, brushes),
          ),
      ];
      if (navigation != null && authoredGrid != null) {
        navigation.grid = breaches.holes.fold(
          authoredGrid,
          (NavGrid baked, Aabb3 hole) => gridAgain(baked, hole, brushes),
        );
      }
    };
}
