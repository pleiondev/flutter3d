import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
// The roster. Not a parameter beside [registry], because the two must agree
// about what a `monster` entity may name and two arguments that must agree are
// two chances to pass one of them from somewhere else. It becomes a parameter
// the day there is a second roster, and not before.
import 'package:flutter3d_game_shooter/sample.dart';
import 'package:vector_math/vector_math.dart';

/// What the player starts a game holding.
///
/// **Here rather than as a field of the widget**, which is where it was: the
/// one test this application has could not reach it, so it built its own — and
/// what it built was fists, a pistol and forty bullets against the game's four
/// weapons and 90/30/12. "The crypt can be finished" was proved with equipment
/// nobody is ever given.
///
/// A function rather than a constant because an `Inventory` is mutable and a
/// run spends it: two levels sharing one object would be two levels sharing
/// one health bar, which is right, and two *runs* sharing it would be a new
/// game that starts where the last one died, which is not.
Inventory startingInventory() => Inventory(
      arsenal: Arsenal(
        slots: Weapons.all,
        owned: <WeaponDef>[...Weapons.all],
        ammo: <AmmoType, int>{
          AmmoType.bullets: 90,
          AmmoType.shells: 30,
          AmmoType.rockets: 12,
        },
        // The pistol, not the fists: the game starts with both, and a shooter
        // that opens with your hands up is making a promise it does not keep.
        startingSlot: 1,
      ),
    );

/// A level, spawned, with somebody standing in it ready to be stepped.
final class Staged {
  const Staged({
    required this.entities,
    required this.projectiles,
    required this.actors,
    required this.mechanisms,
    required this.hitscan,
    required this.shot,
    required this.player,
    required this.sim,
    required this.start,
    required this.navIssues,
  });

  /// One entity world for everything that has moved onto components, so that
  /// one save covers the lot. Two would be a save covering half the game.
  final EcsWorld entities;

  final ProjectileSystem projectiles;
  final ActorSystem actors;
  final MechanismWorld mechanisms;

  /// One ray-caster shared by the player's shots and the monsters', because
  /// there is one world and a second would be a second answer about it.
  final Hitscan hitscan;

  /// Reused between shots rather than made fresh — see [WeaponShot].
  final WeaponShot shot;

  final Player player;
  final GameSimulation sim;

  /// The authored spawn point — where the feet go, not where the body's middle
  /// is. Kept because the camera and the yaw both want it.
  final Vector3 start;

  /// What baking the navigation grid had to say. Reported by the caller rather
  /// than printed here: a test wants to assert on them and an application wants
  /// to log them, and neither wants the other's choice made for it.
  final List<LevelIssue> navIssues;
}

/// Turns a level document into a run, given a world it has already been added
/// to.
///
/// **There were two copies of this, and only one of them shipped.** The
/// application assembled a level in `_loadLevel` and `playthrough_test.dart`
/// assembled its own, and they had already drifted in four places:
///
/// * the application shares **one** `Hitscan` between the player's weapon and
///   the monsters'; the test built two, so a test of what a shot hits was a
///   test of an arrangement the game does not have;
/// * the application starts the player with all four weapons and 90/30/12
///   rounds, the test with fists and a pistol and 40 bullets — so "the crypt
///   can be finished" was proved with a loadout the game never gives anybody;
/// * the application collects what `Navigation.bake` complains about and prints
///   it, the test discarded it;
/// * the application sets the player's yaw after the fact, in `setState`; the
///   test set it in its harness.
///
/// The platformer went through the same thing at six copies, and the note its
/// harness still carries is the argument: a harness that is not the game is a
/// harness that agrees with any bug the game has.
///
/// This is the shipped assembly, and now it is the only one. What is **not**
/// here is everything that needs a graphics device — reading the document,
/// building the scene, `FixtureVisuals`, `ActorVisuals` — because a test has no
/// device and that is the whole reason the copies existed.
///
/// [world] must already have the level's brushes in it: the application gets
/// them from `LevelLoader`, which builds collision and scene together, and a
/// test calls `level.addTo(world)`. That is the seam where the two differ, and
/// it is one line on each side rather than sixty.
Staged stage(
  Level level,
  CollisionWorld world, {
  required InputState input,
  required EntityRegistry registry,
  required Inventory inventory,
  void Function(Actor actor)? onActorSpawned,
  void Function(Fixture fixture)? onFixture,
  double eyeOffset = 0.7,
  double lookSensitivity = 0.0022,
}) {
  final entities = EcsWorld();
  final projectiles = ProjectileSystem(world: world, entities: entities);
  final actors = ActorSystem(world: world, entities: entities);

  // Baked from the level's brushes and deliberately not from the collision
  // world: that holds the doors and the lift, and whichever position they
  // happen to be in at load would be frozen into the grid — a closed door
  // becoming a wall nothing ever paths through again.
  //
  // Quarter-metre cells, not the default half. Measured on the crypt: at half a
  // metre a one-metre corridor is two cells, both of them touching a wall, so
  // every cell in it has a clearance of one — and a monster 0.7 wide, which
  // physically fits, is refused the whole passage. The grid then silently falls
  // back to walking straight at the player in exactly the places a route is
  // worth having. Four times the cells and twice the bake, both load-time and
  // both small.
  final navIssues = <LevelIssue>[];
  actors.navigation =
      Navigation.bake(level, cellSize: 0.25, issues: navIssues);

  // One ray-caster and one shot for the whole world. The application already
  // shared the ray-caster and built the shot twice; sharing both is the same
  // statement made once.
  final hitscan = Hitscan(world: world);
  final shot = WeaponShot(
    world: world,
    hitscan: hitscan,
    projectiles: projectiles,
  );

  // The bestiary is attached here rather than at construction because it needs
  // a world to put monsters in, and there is no world until the level has
  // loaded. A registry with no monster kind in it — which is how a test says
  // "leave the fight out" — simply is not told, and the three in the document
  // spawn nothing.
  (registry[ShooterEntities.monster] as MonsterKind?)?.bestiary = Bestiary(
    actors: actors,
    shot: shot,
    catalog: Monsters.byName,
  );

  final mechanisms = MechanismWorld(world);

  level.spawnInto(
    SpawnContext(
      world: world,
      actors: actors,
      mechanisms: mechanisms,
      onActorSpawned: onActorSpawned,
      onFixture: onFixture,
    ),
    registry: registry,
  );

  final spawn = level.playerStart;
  final start = spawn?.position ?? Vector3.zero();

  // Who the collider *is*, rather than what it happens to be carrying. A locked
  // door reads the keys off the player and a rocket asks the player to take
  // damage, without the physics knowing what either is.
  final player = Player(
    body: CharacterController(
      world: world,
      // Lifted by half the body height: a spawn is authored where the player's
      // feet go, which is the only place an author can see.
      position: start + Vector3(0.0, 0.9, 0.0),
    ),
    inventory: inventory,
    eyeOffset: eyeOffset,
    lookSensitivity: lookSensitivity,
  )..yaw = spawn?.yaw ?? 0.0;

  return Staged(
    entities: entities,
    projectiles: projectiles,
    actors: actors,
    mechanisms: mechanisms,
    hitscan: hitscan,
    shot: shot,
    player: player,
    start: start,
    navIssues: navIssues,
    sim: GameSimulation(
      player: player,
      collision: world,
      input: input,
      mechanisms: mechanisms,
      actors: actors,
      projectiles: projectiles,
      shot: shot,
      levelNext: level.next,
    ),
  );
}
