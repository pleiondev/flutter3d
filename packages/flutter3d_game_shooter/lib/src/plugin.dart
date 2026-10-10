import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'entity_kinds.dart';
import 'events.dart';
import 'simulation.dart';
import 'step_phases.dart';

/// The shooter as a plugin: what a game installs into an `EngineLoop` to have
/// a [GameSimulation] stepped by the engine rather than by hand.
///
/// ## What it registers
///
/// * **One system, `shooter.step`, in the engine's `physics` phase**, which
///   steps [simulation] by the loop's `dt`. The shooter's own moments —
///   [ShooterPhases] and the two every genre has, run through
///   [GameSimulation.systems] — are **sub-phases of this one system**: the
///   order inside a shooter's step is the genre's, documented on
///   [ShooterPhases], and a tape recorded under it replays only while that
///   order holds. The engine's phases order what comes before and after the
///   step; a game hangs its own pre-step work in `input` and its reading of
///   the step in `publish`, or orders a system against `shooter.step` by
///   name.
/// * **The genre's own events, declared** under names prefixed `shooter.`,
///   each with its codec, so a tool can list them beside another genre's and
///   a run's event digest folds in what each carries. An event's `name` is
///   the name it is declared under. The events every genre shares —
///   `ActorDied`, `ActorHurt`, `SequenceSignal` — are the engine's, declared
///   by `GenrePlugin` itself (`declareSimulationEvents`).
/// * **Its entity kinds**, into the engine's `EntityKinds` when the engine
///   has one: [shooterKinds] — a secret and a note, the words only a shooter's
///   levels use — unless the game hands others. A pickup names its gifts and
///   a monster its catalogue, and both are the game's roster, which nothing
///   under `lib/src/` reads, so those come from the game: the shipped one
///   hands over `sampleRegistry`'s kinds.
///
/// Nothing is kept anywhere but on this object and the engine it is installed
/// in; two engines with a plugin each do not meet.
///
/// ## The simulation
///
/// Set [simulation] when a level is staged and again for the next; null
/// steps nothing. Its events are published onto the engine's bus, and only
/// there ([GameSimulation.publishTo]), from inside the step that raised them;
/// a game subscribes with `onStep`, `onFrame`, or reads a whole step's at
/// `EngineLoop.onStepEnd`.
///
/// ## Playing it blind
///
/// [headless] is the [HeadlessGame] a tool plays this genre through, when
/// the host gave one. The shipped one is `ShooterHeadlessGame` in
/// `package:flutter3d_demo_content/shooter_staging.dart`, which reads the roster and
/// the physics core and so cannot be named from here; a host pairs the two
/// by passing it in: `ShooterPlugin(headless: const ShooterHeadlessGame())`.
final class ShooterPlugin extends GenrePlugin<GameSimulation> {
  ShooterPlugin({
    Iterable<EntityKind>? kinds,
    super.replaceKinds,
    super.headless,
  }) : super(kinds: kinds ?? shooterKinds());

  /// The plugin's id, which is the package's name.
  static const String id = 'flutter3d_game_shooter';

  /// The name of the system that steps the simulation, for a game's own
  /// system to order itself against.
  static const String stepSystem = 'shooter.step';

  @override
  String get systemName => stepSystem;

  @override
  PluginManifest get manifest => const PluginManifest(
    id: id,
    apiVersion: PluginApiVersion.current,
    touches: PluginTouches.simulation,
    permissions: <PluginPermission>{},
    description: 'A first-person shooter stepped in the physics phase.',
  );

  @override
  void stepSimulation(GameSimulation simulation, LoopContext context) =>
      simulation.step(context.dt);

  @override
  Registration publishEvents(GameSimulation simulation, EventRegistry bus) =>
      simulation.publishTo(bus);

  /// The run in the loop's snapshots: [GameSimulation.save].
  @override
  Snapshot captureSimulation(GameSimulation simulation) => simulation.save();

  /// [GameSimulation.restore].
  @override
  void restoreSimulation(GameSimulation simulation, Snapshot state) =>
      simulation.restore(state);

  /// The monsters' and the rockets' world, published: the view reads where
  /// the monsters are from `PublishedState` ([PublishedActor.read]).
  @override
  EcsWorld? publishedWorldOf(GameSimulation simulation) => simulation.entities;

  @override
  void declareEvents(EventRegistry events) {
    events
      ..declare<ShotFired>(
        ShotFired.eventName,
        description: 'The player fired a weapon.',
        codec: ShotFired.codec,
      )
      ..declare<ShotLanded>(
        ShotLanded.eventName,
        description: 'A shot reached something.',
        codec: ShotLanded.codec,
      )
      ..declare<PlayerHurt>(
        PlayerHurt.eventName,
        description: 'The player took damage this step.',
        codec: PlayerHurt.codec,
      )
      ..declare<PlayerDied>(
        PlayerDied.eventName,
        description: "The player's health reached zero.",
        codec: PlayerDied.codec,
      )
      ..declare<SecretFound>(
        SecretFound.eventName,
        description: 'The player walked into a secret.',
        codec: SecretFound.codec,
      )
      ..declare<MechanismUsed>(
        MechanismUsed.eventName,
        description: 'The player pressed something, and what came of it.',
        codec: MechanismUsed.codec,
      );
  }
}
