import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import 'run_elements.dart';

/// The dynamics the run's backend gives [world] — see `usePhysics`: on the
/// core, the crates and the characters, the runner's platforms solid from
/// above as a rule the core keeps, and the rays; on the Dart reference the
/// same crates, and other bits.
RigidDynamics platformerDynamics(CollisionWorld world) =>
    usePhysics().dynamics(world);

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
    this.elements,
  });

  /// The one registry that validated the document and then spawned it.
  final EntityRegistry registry;

  final RigidDynamics dynamics;
  final ActorSystem actors;
  final MechanismWorld mechanisms;
  final Runner runner;
  final PlatformerSimulation sim;

  /// The authored spawn point — where the feet go, not where the body's middle
  /// is. Kept because the camera and the respawn both want it.
  final Vector3 start;

  /// The level's water and fires, in the run — see `run_elements.dart`. Null
  /// for a level dressed in none, and on the Dart reference, which has no
  /// core to hold them: a run recorded there says so in `Demo.physics`, and
  /// is played back there.
  final RunElements? elements;

  /// One whole step of the run: the simulation's, then the elements'.
  ///
  /// **What every path that steps a run outside the engine's loop calls** —
  /// a test, the ghost, the timeline's replays — so each steps the same two
  /// things in the same order the loop does, where the genre's step is
  /// `platformer.step` in the `physics` phase and the elements' is
  /// [stepElements] in the `elements` phase after it.
  void step(double dt) {
    sim.step(dt);
    stepElements(sim, elements, dt);
  }
}

/// Turns a level document into a run, given a world it has already been added
/// to.
///
/// **The genre's assembly, [stagePlatformer], plus this game's elements.**
/// There were five copies of this once, and the drift between them is the
/// reason there is one: a harness that is not the game is a harness that
/// agrees with any bug the game has. The genre's half now lives in its
/// package, where a tool that plays the genre blind reaches it too, and what
/// is here is only what this game hangs on the run — the level's water and
/// fires, built from the pits the spawn put in the world, stepped beside the
/// simulation ([Staged.step]) and saved in its snapshot under
/// [elementsPart].
///
/// [world] must already have the level's brushes in it: the application gets
/// them from `LevelLoader`, which builds collision and scene together, and a
/// test calls `level.addTo(world)`.
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

  /// What steps the crates: [platformerDynamics] unless a caller hands over
  /// another, as the test that compares the two does.
  RigidDynamics Function(CollisionWorld world)? dynamicsFor,
}) {
  final genre = stagePlatformer(
    level,
    world,
    input: input,
    registry: registry,
    onFixture: onFixture,
    startAt: startAt,
    coins: coins,
    lives: lives,
    deaths: deaths,
    elapsed: elapsed,
    random: random,
    dynamicsFor: dynamicsFor ?? platformerDynamics,
  );
  final elements = genre.dynamics is NativeDynamics
      ? RunElements.build(level, genre.mechanisms, genre.runner)
      : null;
  if (elements != null) {
    genre.sim.parts[elementsPart] = (
      save: elements.save,
      restore: elements.restore,
    );
  }
  return Staged(
    elements: elements,
    registry: genre.registry,
    dynamics: genre.dynamics,
    actors: genre.actors,
    mechanisms: genre.mechanisms,
    runner: genre.runner,
    start: genre.start,
    sim: genre.sim,
  );
}

/// [stage] as the genre's blind player has it: a [PlatformerHeadlessGame]
/// whose runs carry this game's water and fires, built, saved and stepped as
/// [stage] does them, so a run the game recorded replays there as it was
/// played.
PlatformerHeadlessGame headlessPlatformer() => PlatformerHeadlessGame(
  dress: (Level level, PlatformerStaged genre) {
    if (genre.dynamics is! NativeDynamics) return null;
    final elements = RunElements.build(level, genre.mechanisms, genre.runner);
    if (elements == null) return null;
    genre.sim.parts[elementsPart] = (
      save: elements.save,
      restore: elements.restore,
    );
    return (double dt) => stepElements(genre.sim, elements, dt);
  },
);
