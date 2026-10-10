import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import 'actions.dart';
import 'crate.dart';
import 'entity_kinds.dart';
import 'purse.dart';
import 'runner.dart';
import 'simulation.dart';
import 'simulation_version.dart';
import 'surfaces.dart';

/// A platformer level, spawned, with a runner standing in it ready to be
/// stepped.
final class PlatformerStaged {
  const PlatformerStaged({
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

  final RigidDynamics dynamics;
  final ActorSystem actors;
  final MechanismWorld mechanisms;
  final Runner runner;
  final PlatformerSimulation sim;

  /// The authored spawn point — where the feet go, not where the body's
  /// middle is. Kept because the camera and the respawn both want it.
  final Vector3 start;
}

/// Turns a level document into a platformer run, given a world it has
/// already been added to.
///
/// **The genre's assembly, and the one the game builds on.** The shipped
/// game's own `stage` is this plus what only it has — the level's water and
/// fires — so a run staged here and a run the game stages agree about every
/// body the genre owns, and a tool that plays the genre blind
/// ([PlatformerHeadlessGame]) plays the game's run rather than a copy of it.
/// What is not here is everything that needs a graphics device.
///
/// [world] must already have the level's brushes in it: the game gets them
/// from its level loader, which builds collision and scene together, and a
/// test calls `level.addTo(world)`.
///
/// [dynamicsFor] makes the world's rigid bodies, the crates; the run's
/// world's physics backend ([CollisionWorld.backend]) unless a caller hands over
/// another.
///
/// [entities] is where the enemies live: a world of the run's own when none
/// is given, which [PlatformerPlugin] puts in the loop's snapshots, with the
/// run, and in its published worlds, so the view reads the enemies from
/// published state ([PublishedActor]). A game that wants them in the loop's
/// own world passes `loop.world`.
PlatformerStaged stagePlatformer(
  Level level,
  CollisionWorld world, {
  required InputState input,
  EntityRegistry? registry,
  void Function(Fixture fixture)? onFixture,

  /// Somewhere other than the level's own spawn to stand, for a test that
  /// wants to start beside the thing it is about.
  Vector3? startAt,
  int coins = 0,
  int lives = -1,
  int deaths = 0,

  /// Seconds already on the run's clock.
  double elapsed = 0.0,
  GameRandom? random,
  RigidDynamics Function(CollisionWorld world)? dynamicsFor,
  EcsWorld? entities,
}) {
  // One registry validates the document and then spawns it. Two could
  // disagree about what a document may contain — so the crate kind is told
  // where bodies go *after* there is a world.
  final kinds = registry ?? platformerRegistry();

  // **One world for the whole run** (decision 1 of
  // `tasks/1.0-physics-audit.md`): the platformer's, with the level's laid
  // over it, set before anything is made in it — the dynamics read it, the
  // crates fall by it as the runner does, the chasers' jump arcs are baked
  // in it. The crates used to keep the dynamics' own 22 m/s² under a runner
  // falling at 24, so a crate kicked off a ledge beside the runner landed
  // after him. A level filled with a plugin's medium is refused here,
  // naming the plugin, before anything falls through it.
  world.properties = level.worldOver(
    platformerWorld,
    materials: world.materials,
  );
  final dynamics = (dynamicsFor ?? (w) => w.backend.dynamics(w))(world);
  (kinds[PlatformerEntities.crate] as CrateKind?)?.dynamics = dynamics;

  // **One generator for the whole world, and it is the same object the
  // simulation snapshots.** Two generators are two sequences of which a save
  // records one — so a restored run would agree about the runner and
  // disagree about everything an enemy rolled for.
  final dice = random ?? GameRandom(1);

  final actors = ActorSystem(world: world, random: dice, entities: entities)
    // Baked with the enemies' own reach — they move by the default tuning —
    // so a hunter is handed the gaps it clears and a level of platforms is a
    // level it can cross. A patrol never asks the grid and is unaffected.
    ..navigation = Navigation.bake(
      level,
      jumps: JumpReach.of(const MovementSettings(), world: world.properties),
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
    // Seeded so the purse is the run's total rather than this level's.
    // Through the purse rather than beside it, so `sim.save()` carries it
    // and a resumed run is not a run that lost its coins.
    purse: Purse()..add('coin', coins),
  );

  return PlatformerStaged(
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

/// The platformer as a [HeadlessGame]: [platformerRegistry] and
/// [stagePlatformer] — what a tool plays when it plays this genre.
///
/// **The genre's run, not the shipped game's whole one.** A game that hangs
/// state of its own beside the simulation — the demo's water and fires —
/// hands it in through [dress], which is given each run's level and staging before its
/// first step and may add a [PlatformerSimulation.parts] entry and return
/// what steps it; a run that game recorded replays here only with the same
/// dressing hung on it. Without one, a level is played as the genre has it.
///
/// It says which simulation it is ([simulation]), so a tool refuses
/// a run recorded on other rules before playing it.
final class PlatformerHeadlessGame extends HeadlessGame {
  const PlatformerHeadlessGame({this.extra = const <EntityKind>[], this.dress});

  /// Kinds a level may name beyond the genre's own, for a host whose levels
  /// carry words this package does not know.
  final List<EntityKind> extra;

  /// What the host's game hangs on each run of a level, and what steps it
  /// after each of the simulation's steps — or null for nothing.
  final void Function(double dt)? Function(
    Level level,
    PlatformerStaged staged,
  )?
  dress;

  @override
  SimulationVersion get simulation => platformerSimulationVersion;

  @override
  String get name => 'platformer';

  @override
  Map<String, GameAction> get buttons => const <String, GameAction>{
    'dash': PlatformerActions.dash,
    'dropThrough': PlatformerActions.dropThrough,
  };

  @override
  EntityRegistry registry() {
    final base = platformerRegistry();
    return EntityRegistry(<EntityKind>[
      for (final type in base.types) base[type]!,
      ...extra,
    ]);
  }

  @override
  HeadlessRun start(Level level, CollisionWorld world, InputState input) {
    final staged = stagePlatformer(
      level,
      world,
      input: input,
      registry: registry(),
    );
    return _PlatformerRun(staged, dress?.call(level, staged));
  }
}

/// A staged platformer run, answering what a blind tool asks of one.
final class _PlatformerRun extends RestorableRun {
  _PlatformerRun(this.staged, this._beside);

  final PlatformerStaged staged;
  final void Function(double dt)? _beside;

  PlatformerSimulation get _sim => staged.sim;

  @override
  void step(double dt) {
    _sim.step(dt);
    _beside?.call(dt);
  }

  @override
  Snapshot save() => _sim.save();

  @override
  void restore(Snapshot snapshot) => _sim.restore(snapshot);

  @override
  RunOutcome get outcome => _sim.state.outcome;

  /// The body's float32 position read against the world's origin, which the
  /// loop moves with its own (`EngineLoop.shiftsPhysics`).
  @override
  WorldPosition get position => staged.runner.body.position.toWorldPosition(
    origin: staged.actors.world.origin,
  );

  /// The runner's head: the top of the body, where a person's eyes are.
  @override
  WorldPosition get eye {
    final body = staged.runner.body;
    return position.translated(0.0, body.halfExtents.y, 0.0);
  }

  /// Level, along the way the runner faces.
  @override
  void aim(Vector3 out) {
    final turn = Portable.sinCos(staged.runner.yaw);
    out.setValues(turn.sin, 0.0, turn.cos);
  }

  @override
  String get summary {
    final at = position;
    final health = staged.runner.health;
    return 'runner at (${at.x.toStringAsFixed(1)}, ${at.y.toStringAsFixed(1)}, '
        '${at.z.toStringAsFixed(1)}), health '
        '${health.current.toStringAsFixed(0)}/'
        '${health.maximum.toStringAsFixed(0)}, ${_sim.state.name}, '
        '${_sim.deaths} deaths, ${_sim.elapsed.toStringAsFixed(1)} s.';
  }

  @override
  Map<String, Object?> get reading {
    final at = position;
    final health = staged.runner.health;
    return <String, Object?>{
      'runner': <String, Object?>{
        'position': <double>[at.x, at.y, at.z],
        'yaw': staged.runner.yaw,
        'health': health.current,
        'maxHealth': health.maximum,
      },
      'state': _sim.state.name,
      'deaths': _sim.deaths,
      'lives': _sim.lives,
      'elapsed': _sim.elapsed,
      'next': _sim.nextLevel,
    };
  }
}
