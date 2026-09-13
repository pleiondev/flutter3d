import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_game_shooter/sample.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

/// What an agent starts a run holding — the same loadout
/// `apps/flutter3d_demo_dungeon`'s own `startingInventory()` gives a person,
/// kept in step with it by hand rather than by import: see this file's own
/// doc for why that is the honest cost here rather than a shortcut taken.
Inventory startingInventory() => Inventory(
  arsenal: Arsenal(
    slots: Weapons.all,
    owned: <WeaponDef>[...Weapons.all],
    ammo: <AmmoType, int>{
      AmmoType.bullets: 90,
      AmmoType.shells: 30,
      AmmoType.rockets: 12,
    },
    startingSlot: 1,
  ),
);

/// A level, spawned, with somebody standing in it ready to be stepped.
final class Staged {
  const Staged({required this.actors, required this.player, required this.sim});

  final ActorSystem actors;
  final Player player;
  final GameSimulation sim;
}

/// Turns a level document into a run, given a world it has already been
/// added to.
///
/// **A fourth copy of `apps/flutter3d_demo_dungeon/lib/src/staging.dart`'s
/// `stage()`, and a real cost rather than an oversight.** That file's own
/// doc comment already tells the story of the first two copies drifting
/// apart in four places before they were unified into one — the reason a
/// third copy was still tolerated in `apps/flutter3d_demo_dungeon/test/rewind_test.dart`
/// and its siblings is that a *test* can import the app it is testing;
/// `tool/structure.dart`'s `no package depends on an application` rule
/// means this package genuinely cannot, and copying the composition here
/// is the whole of what is left. **A follow-up worth doing**: everything
/// this function touches is already package-level
/// (`flutter3d_game_shooter` and `flutter3d_sim`, nothing from the app) —
/// promoting it into `flutter3d_game_shooter` itself would let this file,
/// the app, and every test currently duplicating a slice of it share one
/// definition. Not done here: it touches an already-shipped package's
/// public surface and every one of its callers, which is a change this
/// task did not ask for and should not make as a side effect of asking for
/// something else.
///
/// Deliberately smaller than the original: no mechanisms, no breaches, no
/// automap, no `onActorSpawned`/`onFixture` hooks — none of which `ai-00`'s
/// own tools read back, and each one is a further place this copy could
/// drift from the shipped game if it carried something nothing here uses.
Staged stage(Level level, CollisionWorld world, {required InputState input}) {
  final entities = EcsWorld();
  final dice = GameRandom(1);
  final projectiles = ProjectileSystem(world: world, entities: entities);
  final actors = ActorSystem(world: world, entities: entities, random: dice);

  final navIssues = <LevelIssue>[];
  final navigation = Navigation.bake(level, cellSize: 0.25, issues: navIssues);
  actors.navigation = navigation;

  final hitscan = Hitscan(world: world, random: dice);
  final shot = WeaponShot(world: world, hitscan: hitscan, projectiles: projectiles);
  final mechanisms = MechanismWorld(world);

  final registry = sampleRegistry();
  (registry[ShooterEntities.monster] as MonsterKind?)?.bestiary = Bestiary(
    actors: actors,
    shot: shot,
    catalog: Monsters.byName,
  );

  level.spawnInto(
    SpawnContext(world: world, actors: actors, mechanisms: mechanisms),
    registry: registry,
  );

  final spawn = level.playerStart;
  final start = spawn?.position ?? Vector3.zero();
  final player = Player(
    body: CharacterController(
      world: world,
      position: start + Vector3(0.0, 0.9, 0.0),
    ),
    inventory: startingInventory(),
  )..yaw = spawn?.yaw ?? 0.0;

  return Staged(
    actors: actors,
    player: player,
    sim: GameSimulation(
      random: dice,
      player: player,
      collision: world,
      input: input,
      actors: actors,
      mechanisms: mechanisms,
      projectiles: projectiles,
      shot: shot,
      levelNext: level.next,
    ),
  );
}
