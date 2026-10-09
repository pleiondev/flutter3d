import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

import '../actors/actor_hurt.dart';
import '../cinema/sequence_player.dart';
import '../ecs/ecs_world.dart';
import '../level/entity_kind.dart';
import '../level/entity_kinds.dart';
import '../save/snapshot.dart';
import 'headless_run.dart';
import 'published_worlds.dart';

/// A genre installed into an engine: its step as one named system, its
/// events on the bus, its entity kinds in the level format, and the run it
/// steps — [S], set by the game as levels come and go.
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
/// **One shape for every genre**, so a game and a tool hold them alike:
///
/// * [kinds] go into the engine's `EntityKinds` when it has one. A kind
///   another genre already added is shared when it is the same kind (the
///   format's `const DoorKind()`), refused when it is a different one — unless
///   [replaceKinds] is set, when this genre's stands over the other's while it
///   is installed. Two genres in one engine install side by side either way
///   as long as they do not mean different things by one word.
/// * [systemName] is the genre's step, one system in [stepPhase] (the
///   `physics` phase unless a genre says otherwise), named `<genre>.step`
///   and also a genre's `static const stepSystem`. A game orders its own
///   systems against it by that name. **One system, not
///   several**: the order inside a genre's step — its movers, its sweeps, its
///   rules — is what a recorded tape replays, and nothing may run between its
///   parts. The genre's own moments inside it are `StepSystems` phases on
///   the simulation, where a genre has them.
/// * [simulation] is the run being stepped, or null to step nothing. Setting
///   it points the new run's events at the bus ([publishEvents]) and the old
///   run's away from it.
/// * The genre's events are declared with their codecs ([declareEvents]),
///   and the ones every genre shares with them ([declareSimulationEvents]),
///   so a run's event digest folds in what each event carries and the view
///   reads them encoded.
/// * **The run is part of the loop's snapshots.** Installed, a genre adds a
///   `SnapshotPart` under its plugin id that captures [simulation] through
///   [captureSimulation] and puts it back through [restoreSimulation] — the
///   genre's own `save` and `restore`. So `EngineLoop.rewindTo`, a rollback,
///   the double-step check, a rewind buffer and a replay's checkpoints cover
///   the run with nothing more said; before this they covered the loop's
///   world, which held none of it, and restored nothing.
/// * **The run's world is published.** The world the run's actors and
///   rockets live in ([publishedWorldOf]) is added to the loop's
///   `PublishedWorlds` while the run is this genre's, so the view reads
///   where they are from `PublishedState` — the actor components are
///   registered published — rather than from the run.
/// * [headless] is the genre as a tool that plays it blind sees it, handed
///   in through the constructor like [kinds], and null when the host gave
///   none (see there for why it may be).
/// * [uninstall] points the run's events away from the bus; the host cancels
///   the registrations.
///
/// **Nothing global.** The run is this object's; two engines with a genre
/// each have two of these.
abstract base class GenrePlugin<S extends Object> extends Flutter3dPlugin {
  /// A genre adding [kinds] on install, over another genre's when
  /// [replaceKinds] is set, played blind through [headless].
  GenrePlugin({
    Iterable<EntityKind> kinds = const <EntityKind>[],
    this.replaceKinds = false,
    this.headless,
  }) : kinds = List<EntityKind>.unmodifiable(kinds);

  /// The entity kinds installed with the genre.
  final List<EntityKind> kinds;

  /// Whether [kinds] stand over kinds of the same type another genre or the
  /// application already added, rather than being refused for them. What they
  /// replaced is back when this genre is uninstalled.
  final bool replaceKinds;

  /// The genre played blind, or null when the host gave none: what a tool,
  /// a telemetry server or a replay checker steps a run of this genre
  /// through.
  ///
  /// **One shape for every genre: a constructor input, nullable.** Each
  /// genre takes it as `headless:` and none narrows the type, so code
  /// holding any [GenrePlugin] asks the same question of all of them
  /// ([headlessGamesOf] does it for a list). A genre whose own package can
  /// play itself (the platformer, the strategy game) defaults it to that
  /// game; one whose blind game needs what only its host has (a racing
  /// circuit's measured track, a shooter's roster and physics core) is
  /// handed it by the host, and is null when it was not, so a server
  /// refuses that genre's runs with a reason rather than a guess.
  final HeadlessGame? headless;

  /// The name of the genre's step system, `<genre>.step`: the genre's
  /// `static const stepSystem`, here for code that holds any genre.
  String get systemName;

  /// The phase the step runs in.
  LoopPhase get stepPhase => LoopPhase.physics;

  S? _simulation;
  EventRegistry? _bus;
  Registration? _forward;
  PublishedWorlds? _publishedWorlds;
  Registration? _publishing;

  /// The run this genre steps, or null to step nothing — between levels,
  /// before the first. Set again for every level; the old run's events stop
  /// reaching the bus and the new one's start.
  S? get simulation => _simulation;
  set simulation(S? value) {
    if (identical(value, _simulation)) return;
    _simulation = value;
    _reforward();
  }

  /// Steps [simulation] by the loop's step. Called once a step, in
  /// [stepPhase], while there is a simulation.
  void stepSimulation(S simulation, LoopContext context);

  /// Has [simulation] publish its events onto [bus] until the returned
  /// registration is cancelled — the run's own `publishTo`. Null for a genre
  /// that publishes from [stepSimulation] itself, through its
  /// `LoopContext`.
  Registration? publishEvents(S simulation, EventRegistry bus) => null;

  /// Declares the genre's own events, under names prefixed with the genre,
  /// each with its codec and a description a tool shows.
  void declareEvents(EventRegistry events) {}

  /// The world [simulation]'s entities live in — its actors, its rockets —
  /// whose published components the view reads, or null for a run that keeps
  /// none. Null by default.
  EcsWorld? publishedWorldOf(S simulation) => null;

  /// [simulation]'s whole state, as its own `save` writes it: what the
  /// genre's snapshot part holds.
  Snapshot captureSimulation(S simulation);

  /// Puts [state], one [captureSimulation] wrote, back into [simulation]:
  /// the run's own `restore`.
  void restoreSimulation(S simulation, Snapshot state);

  /// A number that differs when [simulation]'s state does, or null to digest
  /// what [captureSimulation] writes, which is always right and sometimes
  /// slow.
  int? digestSimulation(S simulation) => null;

  /// The shape [captureSimulation] writes now: grows when it changes
  /// meaning, as a codec's version does.
  int get snapshotVersion => 1;

  /// [runState] — a run's own snapshot, as [captureSimulation] writes it: a
  /// recorded tape's start, a save file — as a snapshot of the loop holding
  /// this genre's part alone, for `EngineLoop.rewindTo(step, state: …)`.
  ///
  /// **How a run's own file goes through the one path.** A `.f3drun`'s start
  /// and its checkpoints are the run's own snapshot, which is what keeps every
  /// tape recorded since 0.6 replaying; the loop restores it as its genre
  /// part, and the parts the file does not hold — the world, a plugin's —
  /// are left as the freshly staged level has them.
  Snapshot loopStateOf(Snapshot runState) => Snapshot(<String, Object?>{
    manifest.id: <String, Object?>{
      'version': snapshotVersion,
      'data': runState.data,
    },
  });

  /// This genre's part of [loopState], a loop's capture, as the run's own
  /// snapshot — what a checkpoint is digested from and a tape starts from;
  /// null when [loopState] holds none (absent).
  Snapshot? runStateOf(Snapshot loopState) =>
      switch (loopState.data[manifest.id]) {
        {'data': final Map<Object?, Object?> data} => Snapshot(
          data.cast<String, Object?>(),
        ),
        _ => null,
      };

  void _reforward() {
    _forward?.cancel();
    _forward = null;
    _publishing?.cancel();
    _publishing = null;
    final bus = _bus;
    final run = _simulation;
    if (bus == null || run == null) return;
    _forward = publishEvents(run, bus);
    final world = publishedWorldOf(run);
    if (world != null) _publishing = _publishedWorlds?.add(world);
  }

  @override
  void install(PluginHost host) {
    _bus = host.events;
    host.loop.addSystem(systemName, stepPhase, (LoopContext context) {
      final run = _simulation;
      if (run != null) stepSimulation(run, context);
    });
    host.maybeRegistry<SnapshotRegistry>()?.add(_GenrePart<S>(this));
    _publishedWorlds = host.maybeRegistry<PublishedWorlds>();
    declareSimulationEvents(host.events);
    declareEvents(host.events);
    final entityKinds = host.maybeRegistry<EntityKinds>();
    if (entityKinds != null && kinds.isNotEmpty) {
      if (replaceKinds) {
        entityKinds.replaceAll(kinds);
      } else {
        entityKinds.addAll(kinds);
      }
    }
    _reforward();
  }

  @override
  void uninstall(PluginHost host) {
    _forward?.cancel();
    _forward = null;
    _publishing?.cancel();
    _publishing = null;
    _publishedWorlds = null;
    _bus = null;
  }
}

/// The blind games [genres] carry, by [HeadlessGame.name]: what a telemetry
/// or replay server is handed to step a run of any of them.
///
/// A genre with no [GenrePlugin.headless] is left out, and the server
/// answers a run of it with why it took none; a server never has to know
/// which genres those are.
Map<String, HeadlessGame> headlessGamesOf(Iterable<GenrePlugin> genres) =>
    <String, HeadlessGame>{
      for (final game in genres.map((genre) => genre.headless).nonNulls)
        game.name: game,
    };

/// Declares the events every genre shares, the engine's rather than any
/// one genre's — [ActorHurt], [ActorDied] and [SequenceSignal] — with their
/// codecs, each one not already declared on [events].
///
/// Called by every [GenrePlugin] as it is installed, so the first genre in
/// an engine declares them and a second finds them there. A game that steps
/// actors or a cutscene without a genre calls it itself.
void declareSimulationEvents(EventRegistry events) {
  bool declared(String name) => events.declared.any((d) => d.name == name);
  if (!declared(ActorHurt.eventName)) {
    events.declare<ActorHurt>(
      ActorHurt.eventName,
      description: 'An actor took damage and survived it.',
      codec: ActorHurt.codec,
    );
  }
  if (!declared(ActorDied.eventName)) {
    events.declare<ActorDied>(
      ActorDied.eventName,
      description: "An actor's health reached zero.",
      codec: ActorDied.codec,
    );
  }
  if (!declared(SequenceSignal.eventName)) {
    events.declare<SequenceSignal>(
      SequenceSignal.eventName,
      description: "A cutscene's signal fired.",
      codec: SequenceSignal.codec,
    );
  }
}

/// A genre's run as one part of the loop's snapshots, under the genre's
/// plugin id: what [GenrePlugin.install] adds.
///
/// The part holds `null` while the genre steps nothing, and restoring `null`
/// leaves whatever run is set alone; a run restored into another level's run
/// is the caller's mistake, as it is for the run's own `restore`.
final class _GenrePart<S extends Object> extends SnapshotPart {
  const _GenrePart(this.genre);

  final GenrePlugin<S> genre;

  @override
  String get id => genre.manifest.id;

  @override
  int get version => genre.snapshotVersion;

  @override
  Object? capture() {
    final run = genre.simulation;
    return run == null ? null : genre.captureSimulation(run).data;
  }

  @override
  void restore(Object? data, int version) {
    final run = genre.simulation;
    if (run == null || data is! Map) return;
    genre.restoreSimulation(run, Snapshot(data.cast<String, Object?>()));
  }

  @override
  int? digest() {
    final run = genre.simulation;
    return run == null ? 0 : genre.digestSimulation(run);
  }
}
