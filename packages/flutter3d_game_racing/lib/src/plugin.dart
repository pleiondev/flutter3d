import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'events.dart';
import 'headless.dart';
import 'simulation.dart';

/// The racing genre as a plugin: its step in an `EngineLoop`, its events on
/// the bus, and the game a blind tool plays.
///
/// ```dart
/// final racing = RacingPlugin();
/// final loop = EngineLoop(input: input, plugins: <Flutter3dPlugin>[racing]);
/// racing.simulation = staged.sim; // each circuit
/// ```
///
/// **What it registers.** One system, `racing.step`, in
/// [LoopPhase.physics]: the whole of [RacingSimulation.step], whose own order
/// — the lights, the movers, the cars, the push apart, progress, the
/// overlaps, the recoveries — is the one a tape and a ghost depend on, and
/// stays inside it. A game's driver and AI write the cars' inputs in
/// [LoopPhase.input] before it; what reads the step's outcome runs in
/// [LoopPhase.publish] after. And the genre's own events are declared under
/// `racing.` names, so a tool lists them and a second genre in the same
/// engine cannot claim one.
///
/// **No entity kinds of its own.** A circuit is a `TrackDocument`, its level
/// an ordinary one built from the engine's own kinds; [kinds] is empty unless
/// the game hands some in.
///
/// **Nothing global.** The race being stepped is this instance's
/// [simulation], set by whoever stages one; two engines hold two plugins and
/// their races do not meet. The shape every genre has is [GenrePlugin].
///
/// **Played blind on a circuit the host names.** [headless] is null unless
/// the host hands a [RacingHeadlessGame] for one circuit: it needs the
/// circuit's measured spline, which a `TrackDocument` carries beside its
/// level and a level alone does not.
final class RacingPlugin extends GenrePlugin<RacingSimulation> {
  RacingPlugin({super.kinds, super.replaceKinds, super.headless});

  /// The plugin's id, which is the package's.
  static const String id = 'flutter3d_game_racing';

  /// The name of the system that steps the race.
  static const String stepSystem = 'racing.step';

  /// The names the genre's events are declared under, in the order they are
  /// declared: every one starts `racing.`.
  static const List<String> eventNames = <String>[
    CountdownTicked.eventName,
    RaceStarted.eventName,
    LapCompleted.eventName,
    BestLapSet.eventName,
    CheckpointPassed.eventName,
    SectorCompleted.eventName,
    WentWrongWay.eventName,
    LeftTheRoad.eventName,
    Respawned.eventName,
    DriftScored.eventName,
    RacerFinished.eventName,
    RaceFinished.eventName,
  ];

  @override
  String get systemName => stepSystem;

  @override
  PluginManifest get manifest => const PluginManifest(
    id: id,
    apiVersion: PluginApiVersion.current,
    touches: PluginTouches.simulation,
    permissions: <PluginPermission>{},
    description: 'Driving: cars on a measured circuit, laps, sectors and AI.',
  );

  /// Steps the race. Set [simulation] when a circuit is staged and clear it
  /// when it is torn down; while installed, its events are published onto
  /// the bus from inside the step, which puts them on the step channel.
  @override
  void stepSimulation(RacingSimulation simulation, LoopContext context) =>
      simulation.step(context.dt);

  @override
  Registration publishEvents(RacingSimulation simulation, EventRegistry bus) =>
      simulation.publishTo(bus);

  /// The run in the loop's snapshots: [RacingSimulation.save].
  @override
  Snapshot captureSimulation(RacingSimulation simulation) => simulation.save();

  /// [RacingSimulation.restore].
  @override
  void restoreSimulation(RacingSimulation simulation, Snapshot state) =>
      simulation.restore(state);

  @override
  void declareEvents(EventRegistry events) {
    // In [eventNames]' order, which a test holds.
    events
      ..declare<CountdownTicked>(
        CountdownTicked.eventName,
        description: 'A second of the starting lights went out.',
        codec: CountdownTicked.codec,
      )
      ..declare<RaceStarted>(
        RaceStarted.eventName,
        description: 'The lights went out and the cars may drive.',
        codec: RaceStarted.codec,
      )
      ..declare<LapCompleted>(
        LapCompleted.eventName,
        description: 'A car crossed the line and finished a lap.',
        codec: LapCompleted.codec,
      )
      ..declare<BestLapSet>(
        BestLapSet.eventName,
        description: 'A lap was the fastest of the race so far.',
        codec: BestLapSet.codec,
      )
      ..declare<CheckpointPassed>(
        CheckpointPassed.eventName,
        description: 'A car passed a checkpoint in order.',
        codec: CheckpointPassed.codec,
      )
      ..declare<SectorCompleted>(
        SectorCompleted.eventName,
        description: 'A car finished a sector of the lap.',
        codec: SectorCompleted.codec,
      )
      ..declare<WentWrongWay>(
        WentWrongWay.eventName,
        description: 'A car turned round and drove the circuit backwards.',
        codec: WentWrongWay.codec,
      )
      ..declare<LeftTheRoad>(
        LeftTheRoad.eventName,
        description: 'A car left the road.',
        codec: LeftTheRoad.codec,
      )
      ..declare<Respawned>(
        Respawned.eventName,
        description: 'A car was put back on the road.',
        codec: Respawned.codec,
      )
      ..declare<DriftScored>(
        DriftScored.eventName,
        description: 'A drift ended and was scored.',
        codec: DriftScored.codec,
      )
      ..declare<RacerFinished>(
        RacerFinished.eventName,
        description: 'A car finished the race.',
        codec: RacerFinished.codec,
      )
      ..declare<RaceFinished>(
        RaceFinished.eventName,
        description: 'Every car finished, or the race was called.',
        codec: RaceFinished.codec,
      );
  }
}
