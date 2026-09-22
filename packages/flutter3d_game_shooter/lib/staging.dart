/// A shooter level assembled into a run — the one assembly the shipped game,
/// its tests and a tool that plays it blind all share.
///
/// **A library of its own beside `sample.dart`, not under `lib/src/`.** It
/// reads the roster — the four weapons, the monsters and the registry that
/// names them — and nothing in `lib/src/` may. It moved here from
/// `apps/flutter3d_demo_dungeon/lib/src/staging.dart`, where no package could
/// reach it: `flutter3d_sim_mcp` kept a fourth copy for exactly that reason,
/// and the copy had already left out the automap and the breaches the game
/// has.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import 'flutter3d_game_shooter.dart';
// The roster. Not a parameter beside [stage]'s registry, because the two must
// agree about what a `monster` entity may name and two arguments that must
// agree are two chances to pass one of them from somewhere else. It becomes a
// parameter the day there is a second roster, and not before.
import 'sample.dart';

/// What the player starts a game holding.
///
/// **Here rather than as a field of the widget**, which is where it was: the
/// one test the application had could not reach it, so it built its own — and
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
  GameRandom? random,
}) {
  final entities = EcsWorld();

  // **One generator, shared by everything in this world that rolls.** It was
  // three: `ActorSystem` and `Hitscan` each defaulted to an unseeded
  // `math.Random`, and `GameSimulation.random` was left null, so `save()` wrote
  // no dice at all. A crypt restored from a save agreed about where everything
  // stood and disagreed about the first monster that decided whether to flinch
  // — which is ARCHITECTURE.md §9.3 not being kept by anything, in the game the document's
  // performance budgets are written for.
  final dice = random ?? GameRandom(1);

  final projectiles = ProjectileSystem(world: world, entities: entities);
  final actors = ActorSystem(world: world, entities: entities, random: dice);

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
  final navigation = Navigation.bake(level, cellSize: 0.25, issues: navIssues);
  actors.navigation = navigation;

  // One ray-caster and one shot for the whole world. The application already
  // shared the ray-caster and built the shot twice; sharing both is the same
  // statement made once.
  final hitscan = Hitscan(world: world, random: dice);
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
    sim:
        GameSimulation(
            random: dice,
            player: player,
            collision: world,
            input: input,
            mechanisms: mechanisms,
            actors: actors,
            projectiles: projectiles,
            shot: shot,
            levelNext: level.next,
          )
          ..automap = Automap(navigation.grid)
          // Walls crumble; floors, ceilings and the stone of the crypt's
          // fixtures do not. A rocket through the floor is a player out of the
          // level, and a ceiling with a hole in it looks out on nothing.
          ..breaches = Breaches(
            level,
            world,
            breakable: (Brush brush) =>
                brush.solid && brush.ramp == null && brush.material == 'wall',
          ),
  );
}

/// The shipped game as a [HeadlessGame]: the sample roster, the starting
/// loadout and [stage] — what a tool plays when it plays this genre.
///
/// A host composes this with `flutter3d_sim_mcp`'s session and playtest; the
/// tool names no genre and this package names no tool.
final class ShooterHeadlessGame implements HeadlessGame {
  const ShooterHeadlessGame({this.extra = const <EntityKind>[]});

  /// A kind this package cannot know about without depending on whoever
  /// defines it — `sampleRegistry`'s own `extra` parameter, threaded through
  /// rather than duplicated. A host that plays a real shipped level headless
  /// (`flutter3d_sim_mcp`'s own crypt) passes `WidgetSurfaceKind()` here the
  /// same way `flutter3d_demo_dungeon`'s `main.dart` does for the real app,
  /// since a level naming a word this game's own vocabulary does not know
  /// refuses to load rather than silently dropping the entity.
  final List<EntityKind> extra;

  @override
  String get name => 'shooter';

  @override
  Map<String, GameAction> get buttons => const <String, GameAction>{
    'fire': ShooterActions.fire,
  };

  @override
  EntityRegistry registry() => sampleRegistry(extra: extra);

  @override
  HeadlessRun start(Level level, CollisionWorld world, InputState input) =>
      _ShooterRun(
        stage(
          level,
          world,
          input: input,
          registry: registry(),
          inventory: startingInventory(),
        ),
      );
}

/// A [Staged] shooter run, answering what a blind tool asks of one.
final class _ShooterRun implements HeadlessRun {
  _ShooterRun(this.staged);

  final Staged staged;

  @override
  void step(double dt) => staged.sim.step(dt);

  @override
  Snapshot save() => staged.sim.save();

  @override
  RunOutcome get outcome => staged.sim.state.outcome;

  @override
  Vector3 get position => staged.player.body.position;

  @override
  void eye(Vector3 out) => staged.player.eye(out);

  @override
  void aim(Vector3 out) => staged.player.aim(out);

  /// Alive, health, where — the player and every actor still worth mentioning.
  @override
  String get summary {
    final player = staged.player;
    final at = player.body.position;
    final health = player.inventory.health;
    final alive = staged.actors.actors.where((a) => a.isAlive).length;
    final total = staged.actors.actors.length;
    return 'player at (${at.x.toStringAsFixed(1)}, ${at.y.toStringAsFixed(1)}, '
        '${at.z.toStringAsFixed(1)}), health ${health.current.toStringAsFixed(0)}'
        '/${health.maximum.toStringAsFixed(0)}, $alive of $total actors still up.';
  }

  /// One row per actor, named by [Actor.name] when the level gave it one and
  /// by its index otherwise, so two monsters of one kind stay apart across
  /// calls.
  @override
  Map<String, Object?> get reading {
    final player = staged.player;
    final at = player.body.position;
    final health = player.inventory.health;
    return <String, Object?>{
      'player': <String, Object?>{
        'position': <double>[at.x, at.y, at.z],
        'yaw': player.yaw,
        'health': health.current,
        'maxHealth': health.maximum,
        'alive': player.isAlive,
      },
      'actors': <Map<String, Object?>>[
        for (final actor in staged.actors.actors)
          <String, Object?>{
            'name': actor.name ?? '#${actor.entity.index}',
            'position': actor.position == null
                ? null
                : <double>[
                    actor.position!.x,
                    actor.position!.y,
                    actor.position!.z,
                  ],
            'health': actor.health?.current,
            'alive': actor.isAlive,
          },
      ],
    };
  }
}
