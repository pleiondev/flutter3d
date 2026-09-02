import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:vector_math/vector_math.dart';

/// A level, spawned, with somebody standing in it ready to be stepped.
final class Staged {
  const Staged({
    required this.registry,
    required this.dynamics,
    required this.actors,
    required this.mechanisms,
    required this.runner,
    required this.sim,
    required this.start,
  });

  /// The one registry that validated the document and then spawned it.
  final EntityRegistry registry;

  final Dynamics dynamics;
  final ActorSystem actors;
  final MechanismWorld mechanisms;
  final Runner runner;
  final PlatformerSimulation sim;

  /// The authored spawn point — where the feet go, not where the body's middle
  /// is. Kept because the camera and the respawn both want it.
  final Vector3 start;
}

/// Turns a level document into a run, given a world it has already been added
/// to.
///
/// **There were five copies of this, and only one of them shipped.** The
/// application assembled a level in `_readLevel`, and four test files each
/// assembled their own — with drift that had already cost something once:
/// `playthrough_test.dart` still carries the note that its first version left
/// `surfaces` out, so the level's ice walked exactly like its moss, and "a
/// harness that is not the game is a harness that agrees with any bug the game
/// has". Other drift was still there when this was written: one harness ran
/// the validator and three did not, one seeded the purse and four did not, and
/// none of them passed `levelNext`, so no test ever saw a level that knew
/// where the next one was.
///
/// This is the shipped assembly, and now it is the only one. What is *not*
/// here is everything that needs a graphics device — reading the document,
/// building the scene, the fixtures' meshes — because a test has no device and
/// that is the whole reason the copies existed.
///
/// [world] must already have the level's brushes in it: the application gets
/// them from `LevelLoader`, which builds collision and scene together, and a
/// test calls `level.addTo(world)`. That is the seam where the two differ, and
/// it is one line on each side rather than forty.
Staged stage(
  Level level,
  CollisionWorld world, {
  required InputState input,
  EntityRegistry? registry,
  void Function(Fixture fixture)? onFixture,

  /// Somewhere other than the level's own spawn to stand, for a test that wants
  /// to start beside the thing it is about. The application never passes it.
  Vector3? startAt,
  int coins = 0,
  int lives = -1,
  int deaths = 0,
  double elapsed = 0.0,
  GameRandom? random,
}) {
  // One registry validates the document and then spawns it. Two could disagree
  // about what a document may contain, which is the failure this seam was built
  // to remove — so the crate kind is told where bodies go *after* there is a
  // world, exactly as the shooter tells its monster kind where the bestiary is.
  final kinds = registry ?? platformerRegistry();

  final dynamics = Dynamics(world: world);
  (kinds[PlatformerEntities.crate] as CrateKind?)?.dynamics = dynamics;

  // **One generator for the whole world, and it is the same object the
  // simulation snapshots.** `PlatformerSimulation` would make its own if this
  // did not hand one over, and two generators are two sequences of which a save
  // records one — so a restored run would agree about the runner and disagree
  // about everything an enemy rolled for.
  final dice = random ?? GameRandom(1);

  final actors = ActorSystem(world: world, random: dice)
    // Baked with the enemies' own reach — they move by the default tuning —
    // so a hunter is handed the gaps it clears and a level of platforms is a
    // level it can cross. A patrol never asks the grid and is unaffected.
    ..navigation = Navigation.bake(
      level,
      jumps: JumpReach.of(const MovementTuning()),
    );
  final mechanisms = MechanismWorld(world);

  level.spawnInto(
    SpawnContext(
      world: world,
      actors: actors,
      mechanisms: mechanisms,
      onFixture: onFixture,
    ),
    registry: kinds,
  );

  // The authored point is where the feet go; the body is a box about its
  // middle.
  final start = startAt ?? level.playerStart?.position ?? Vector3.zero();
  final runner = Runner(
    body: CharacterController(
      world: world,
      position: start + Vector3(0.0, 0.9, 0.0),
    ),
    // What this game's floors are made of. The names live in the level
    // document, on the brushes, beside the material that paints them.
    surfaces: Surfaces.common(),
    // Seeded so the purse is the run's total rather than this level's, which is
    // what the HUD has always claimed it was and what the ending totals.
    // Through the purse rather than beside it, so `sim.save()` carries it and a
    // resumed run is not a run that lost its coins.
    purse: Purse()..add('coin', coins),
  );

  return Staged(
    registry: kinds,
    dynamics: dynamics,
    actors: actors,
    mechanisms: mechanisms,
    runner: runner,
    start: start,
    sim: PlatformerSimulation(
      runner: runner,
      collision: world,
      input: input,
      actors: actors,
      startAt: start,
      mechanisms: mechanisms,
      dynamics: dynamics,
      levelNext: level.next,
      random: dice,
      lives: lives,
      deaths: deaths,
      elapsed: elapsed,
    ),
  );
}
