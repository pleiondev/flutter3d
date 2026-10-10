import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'crate.dart';
import 'entity_kinds.dart';
import 'events.dart';
import 'simulation.dart';
import 'staging.dart';

/// The platformer, installed into an engine: its step in the loop, its
/// events on the bus, its entity kinds in the level format.
///
/// ```dart
/// final platformer = PlatformerPlugin();
/// final loop = EngineLoop(
///   input: input,
///   registries: <PluginRegistry>[EntityKinds()],
///   plugins: <Flutter3dPlugin>[platformer],
/// );
/// platformer.simulation = staged.sim; // and again for every level
/// ```
///
/// **The genre's step is one system**, `platformer.step` in the `physics`
/// phase, because the order inside it — the movers, the broadphase catching
/// up, the runner's sweep, the overlaps, the rules read off them — is this
/// genre's and is what a recorded tape replays. A game hangs its own work
/// before it (`input`), beside it (`elements`) and after it (`publish`).
///
/// **Nothing global.** The run it steps is this object's, set by the game as
/// levels come and go; two engines with a platformer each have two of these.
///
/// The shape every genre has, [GenrePlugin]: [kinds] are [platformerKinds]
/// unless the game hands others, and [replaceKinds] puts them over another
/// genre's kinds of the same type rather than being refused for them.
final class PlatformerPlugin extends GenrePlugin<PlatformerSimulation> {
  PlatformerPlugin({
    Iterable<EntityKind>? kinds,
    super.replaceKinds,
    super.headless = const PlatformerHeadlessGame(),
  }) : super(kinds: kinds ?? platformerKinds());

  /// The plugin's id, which is its package's name.
  static const String id = 'flutter3d_game_platformer';

  /// The name of the genre's step system.
  static const String stepSystem = 'platformer.step';

  @override
  String get systemName => stepSystem;

  @override
  PluginManifest get manifest => const PluginManifest(
    id: id,
    apiVersion: PluginApiVersion.current,
    touches: PluginTouches.simulation,
    permissions: <PluginPermission>{},
    description:
        'A platformer: a runner, its jumps, checkpoints, collectibles and '
        'enemies, stepped in the physics phase.',
  );

  @override
  void stepSimulation(PlatformerSimulation simulation, LoopContext context) =>
      simulation.step(context.dt);

  /// The run in the loop's snapshots: [PlatformerSimulation.save].
  @override
  Snapshot captureSimulation(PlatformerSimulation simulation) =>
      simulation.save();

  /// [PlatformerSimulation.restore].
  @override
  void restoreSimulation(PlatformerSimulation simulation, Snapshot state) =>
      simulation.restore(state);

  /// The enemies' world, published: the view reads where they are from
  /// `PublishedState` ([PublishedActor.read]).
  @override
  EcsWorld? publishedWorldOf(PlatformerSimulation simulation) =>
      simulation.actors?.entities;

  /// The run's events go onto the bus while it is this genre's run: see
  /// [PlatformerSimulation.publishTo].
  @override
  Registration publishEvents(
    PlatformerSimulation simulation,
    EventRegistry bus,
  ) => simulation.publishTo(bus);

  /// Declares the genre's own events, each with its codec, so a run's event
  /// digest folds in what each carries. Named under the plugin, so two genres
  /// in one engine never claim one name; the shared ones of `flutter3d_sim`
  /// are declared by [GenrePlugin] itself (`declareSimulationEvents`).
  @override
  void declareEvents(EventRegistry events) {
    events
      ..declare<CollectibleTaken>(
        CollectibleTaken.eventName,
        description: 'A collectible was taken.',
        codec: CollectibleTaken.codec,
      )
      ..declare<LevelSaid>(
        LevelSaid.eventName,
        description: 'The level said a line.',
        codec: LevelSaid.codec,
      )
      ..declare<CheckpointReached>(
        CheckpointReached.eventName,
        description: 'The runner reached a checkpoint.',
        codec: CheckpointReached.codec,
      )
      ..declare<EnemyStomped>(
        EnemyStomped.eventName,
        description: 'An enemy was landed on.',
        codec: EnemyStomped.codec,
      )
      ..declare<RunnerDied>(
        RunnerDied.eventName,
        description: 'The runner died.',
        codec: RunnerDied.codec,
      )
      ..declare<Jumped>(
        Jumped.eventName,
        description: 'The runner jumped.',
        codec: Jumped.codec,
      )
      ..declare<WallJumped>(
        WallJumped.eventName,
        description: 'The runner jumped off a wall.',
        codec: WallJumped.codec,
      )
      ..declare<LongJumped>(
        LongJumped.eventName,
        description: 'The runner long-jumped.',
        codec: LongJumped.codec,
      )
      ..declare<Mantled>(
        Mantled.eventName,
        description: 'The runner climbed a ledge.',
        codec: Mantled.codec,
      )
      ..declare<Dashed>(
        Dashed.eventName,
        description: 'The runner dashed.',
        codec: Dashed.codec,
      )
      ..declare<Slid>(
        Slid.eventName,
        description: 'The runner slid.',
        codec: Slid.codec,
      )
      ..declare<Grabbed>(
        Grabbed.eventName,
        description: 'The runner grabbed a ledge.',
        codec: Grabbed.codec,
      )
      ..declare<Landed>(
        Landed.eventName,
        description: 'The runner landed.',
        codec: Landed.codec,
      )
      ..declare<Bounced>(
        Bounced.eventName,
        description: 'The runner bounced.',
        codec: Bounced.codec,
      )
      ..declare<SpringFired>(
        SpringFired.eventName,
        description: 'A spring fired.',
        codec: SpringFired.codec,
      )
      ..declare<BlockCrumbled>(
        BlockCrumbled.eventName,
        description: 'A crumbling block gave way.',
        codec: BlockCrumbled.codec,
      )
      ..declare<BlockBroke>(
        BlockBroke.eventName,
        description: 'A block was broken.',
        codec: BlockBroke.codec,
      )
      ..declare<PowerEnded>(
        PowerEnded.eventName,
        description: 'A power ran out.',
        codec: PowerEnded.codec,
      )
      ..declare<ChainEnded>(
        ChainEnded.eventName,
        description: 'A chain of collectibles ended.',
        codec: ChainEnded.codec,
      );
  }
}

/// The entity kinds that are the platformer's own — the words its levels
/// use that no other genre does — for an engine's [EntityKinds].
///
/// **Not the whole of [platformerRegistry].** The level format's own kinds
/// (a spawn point, doors, lifts, buttons, triggers, the exit, a key) and the
/// lamp are the engine's words, which every genre names; added by each
/// genre, two genres in one engine would claim them twice. A game adds those
/// itself, once. The crate is added without a world's dynamics: a level is
/// spawned through [stagePlatformer], which hands its own registry the
/// dynamics of the world it spawns into.
List<EntityKind> platformerKinds() => <EntityKind>[
  const CollectibleKind(),
  const HazardKind(),
  const CheckpointKind(),
  CrateKind(),
  const SpringKind(),
  const OneWayKind(),
  const ConveyorKind(),
  const CrumblingKind(),
  const BreakableKind(),
  const ClimbableKind(),
  const EnemyKind(),
];
