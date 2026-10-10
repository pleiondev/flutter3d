import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'events.dart';
import 'headless.dart';
import 'level_reader.dart';
import 'match.dart';
import 'step_phases.dart';

/// The strategy as a plugin: what installs a match's step into an
/// `EngineLoop`.
///
/// ## What it registers
///
/// * **[stepSystem] in `LoopPhase.physics`**, stepping [simulation] by the
///   loop's `dt`: the bots decide, then the simulation steps, as
///   [Match.step] always has. The step's own order — orders, jobs, walk,
///   fight, shove, production, fog, then `StrategySimulation.afterStep` —
///   is the genre's and stays inside the one system, because a recorded
///   match is that order and nothing may run between its parts. A game's
///   rule hangs at the genre's own moments, [StrategyPhases], on
///   `StrategySimulation.systems`, as it does in every genre.
///   `afterStep` stays where it is for the same reason: a map's world hangs
///   on it, and a replay that steps the simulation without a loop finds it
///   there.
/// * **[UnitFired] and [MatchDecided]**, declared, and published by the
///   match onto the bus from inside its step ([Match.publishTo]), as every
///   genre's run publishes its own.
/// * **The run in the loop's snapshots**, under [id]: [Match.save].
/// * **The level's entity kinds**, when an `EntityKinds` registry is among
///   the engine's: [kinds] — [strategyLevelKinds] unless the application
///   hands its own, as the shipped game does, since the document a match is
///   read from belongs to the application.
///
/// ## What it holds
///
/// The match being played, [simulation], set by the application when one is
/// staged and swapped when the next one is; null steps nothing. Per plugin
/// and so per engine: two engines with a strategy plugin each step their own
/// match. It was `match` before 1.0; it is named as every genre's run is now,
/// [GenrePlugin.simulation].
///
/// ## Playing it blind
///
/// [headless] is the [HeadlessGame] a tool plays this genre through —
/// [StrategyHeadlessGame] by default, which opens a map with
/// [openStrategyLevel] and takes side nought's orders as an [OrderedGame]:
/// a strategy has no body the stick walks, so its selection is sent by
/// orders written into the input, and a run played that way replays as any
/// other does.
final class StrategyPlugin extends GenrePlugin<Match> {
  /// A plugin adding [kinds] to the engine's entity kinds when installed.
  StrategyPlugin({
    Iterable<EntityKind>? kinds,
    super.replaceKinds,
    super.headless = const StrategyHeadlessGame(),
  }) : super(kinds: kinds ?? strategyLevelKinds);

  /// The plugin's id: the package's name.
  static const String id = 'flutter3d_game_strategy';

  /// The system that steps the match.
  static const String stepSystem = 'strategy.step';

  @override
  String get systemName => stepSystem;

  @override
  PluginManifest get manifest => const PluginManifest(
    id: id,
    apiVersion: PluginApiVersion.current,
    touches: PluginTouches.simulation,
    permissions: <PluginPermission>{},
    description: 'A crowd on a map: orders, an economy, fog and a fight.',
  );

  @override
  void declareEvents(EventRegistry events) {
    events
      ..declare<UnitFired>(
        UnitFired.eventName,
        description: 'A unit fired at another.',
        codec: UnitFired.codec,
      )
      ..declare<MatchDecided>(
        MatchDecided.eventName,
        description: 'The match was won or drawn.',
        codec: MatchDecided.codec,
      );
  }

  /// The bots decide and the simulation steps, as [Match.step] always has;
  /// the match publishes what the step left onto the bus it was pointed at
  /// ([publishEvents]).
  @override
  void stepSimulation(Match playing, LoopContext context) =>
      playing.step(context.dt);

  /// The match's events go onto the bus while it is this genre's run: see
  /// [Match.publishTo].
  @override
  Registration publishEvents(Match simulation, EventRegistry bus) =>
      simulation.publishTo(bus);

  /// The run in the loop's snapshots: [Match.save].
  @override
  Snapshot captureSimulation(Match simulation) => simulation.save();

  /// [Match.restore].
  @override
  void restoreSimulation(Match simulation, Snapshot state) =>
      simulation.restore(state);

  /// The crowd's world, published.
  @override
  EcsWorld? publishedWorldOf(Match simulation) =>
      simulation.simulation.entities;
}
