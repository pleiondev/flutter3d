import 'dart:async';

import 'package:flutter3d_game/flutter3d_game.dart'; // RunSession

import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'looks.dart';
import 'run_elements.dart';
import 'staging.dart';

/// A level, loaded and playable.
///
/// The live objects rather than copies of their numbers: a scene and a
/// simulation are read sixty times a second, and a state class holding their
/// contents would be a state class emitted sixty times a second.
final class LevelReady {
  const LevelReady({
    required this.loaded,
    required this.staged,
    required this.fixtures,
  });

  final LoadedLevel loaded;
  final Staged staged;
  final FixtureVisuals fixtures;

  Scene get scene => loaded.scene;
  Runner get runner => staged.runner;
  PlatformerSimulation get sim => staged.sim;
}

/// What a run has come to so far, carried from one level into the next.
///
/// **Three lives used to mean three lives per level**, and the clock on the
/// summit read as the time for the last climb: every level built a fresh
/// simulation from the constant, and the tally of the run before it went
/// nowhere. A run spans levels and a simulation does not.
typedef Carried = ({int lives, int deaths, double elapsed, int coins});

/// Reads a level document and builds the half of it that draws.
///
/// **A named function rather than four lines inside [PlatformerRun.loadLevel],
/// because `frame_test.dart` was the second copy of them.** Its copy happened
/// to be right; the crypt's equivalent copy had lost `bindLights()`, so every
/// torch in that harness lit nothing. A frame test is only worth having if the
/// frame is the game's, and that means calling what the game calls rather than
/// writing it out again beside it.
///
/// Deliberately *not* in `staging.dart`: everything here needs a
/// [GraphicsDevice], and that file exists to be callable without one.
///
/// [document] builds that level instead of reading [asset]: a level edited
/// in the editor, which exists as a document and not yet as an asset.
Future<({EntityRegistry kinds, LoadedLevel loaded, FixtureVisuals fixtures})>
openLevel(
  String asset, {
  required GraphicsDevice device,
  Level? document,

  /// What the simulation last published, which the guards are drawn from —
  /// see [PlatformerLooks.published]. Null asks the actors themselves.
  PublishedState Function()? published,
}) async {
  final kinds = platformerRegistry();
  final loaded = document == null
      ? await const LevelLoader().load(
          asset,
          device: device,
          registry: kinds,
          rules: platformerRules(),
          physics: usePhysics(),
        )
      : await const LevelLoader().build(
          document,
          device: device,
          registry: kinds,
          rules: platformerRules(),
          physics: usePhysics(),
        );
  final fixtures = FixtureVisuals(
    loaded.scene,
    loaded,
    appearance: PlatformerLooks(published: published),
    device: device,
    // Before spawning, so a light-bearing fixture can find the light it drives.
  )..bindLights();

  return (kinds: kinds, loaded: loaded, fixtures: fixtures);
}

/// This game's answers to the five questions a run asks.
///
/// Starting, restarting, moving on, saving, resuming and the guards around them
/// are `RunSession`'s, shared with the other two games. What is here is what
/// only a platformer can answer — including the two places it disagrees with
/// the crypt, which are both about having lives.
final class PlatformerRun extends RunSession<LevelReady> {
  PlatformerRun({
    required super.firstLevel,
    required super.saves,
    required this.input,
    required this.openDevice,
    required this.onLevelBuilt,
    this.onLevelEdited,
    this.startingLives = 3,
    this.pauseBetweenLevels = const Duration(milliseconds: 1400),
    this.published,
  });

  /// What the simulation last published — `() => loop.published` — which
  /// the level's guards are drawn from ([PlatformerLooks.published]).
  final PublishedState Function()? published;

  final InputState input;

  /// The device to upload through, waited for rather than given up on: the
  /// first level is asked for before the renderer has finished opening.
  final Future<GraphicsDevice> Function() openDevice;

  /// Everything the widget has to do with a level once it exists — the runner's
  /// node, the camera, the interpolators, and (`rp-01`/`rp-04`) starting the
  /// demo recording. Handed in because it touches the widget's own fields,
  /// which a run has no business holding. Carries [asset] too — [loadLevel]'s own
  /// argument — because the widget needs the source path a demo names itself
  /// by, and `_status` still reads the load this level is replacing at the
  /// moment this fires, not the `RunPlaying` this one becomes.
  final void Function(String asset, LevelReady level, GraphicsDevice device)
  onLevelBuilt;

  /// What the widget does with an edit of the level being played, once the
  /// run is back at now. [onLevelBuilt] when null.
  ///
  /// **Not the same as a load**, because the run goes on: a load begins a
  /// new demo, and an edit is written into the one being recorded
  /// (`DemoRecording.levelSwapped`). A widget that began a new demo here
  /// would lose everything played before the edit.
  final void Function(String asset, LevelReady level, GraphicsDevice device)?
  onLevelEdited;

  final int startingLives;

  /// A beat on the results screen before the next level: arriving somewhere new
  /// in the same frame the last place ended reads as a glitch.
  final Duration pauseBetweenLevels;

  Carried? _carried;

  /// The device the last [loadLevel] uploaded through, kept so [disposeLevel] can release
  /// a level's resources without waiting on [openDevice] again — a level only
  /// exists once the device does, so this is never null when [disposeLevel] runs.
  GraphicsDevice? _device;

  @override
  Future<LevelReady> loadLevel(String asset) async {
    final device = await openDevice();
    _device = device;
    final level = await _build(asset, device);
    onLevelBuilt(asset, level, device);
    return level;
  }

  Future<LevelReady> _build(
    String asset,
    GraphicsDevice device, {
    Level? document,
  }) async {
    // The run's physics, chosen once: the core, which the browser fetches
    // as WebAssembly, or the reference where it will not start.
    await preparePhysics();
    final (:kinds, :loaded, :fixtures) = await openLevel(
      asset,
      device: device,
      document: document,
      published: published,
    );

    final staged = stage(
      loaded.level,
      loaded.collision,
      input: input,
      registry: kinds,
      onFixture: fixtures.add,
      coins: _carried?.coins ?? 0,
      lives: _carried?.lives ?? startingLives,
      deaths: _carried?.deaths ?? 0,
      elapsed: _carried?.elapsed ?? 0.0,
    );

    return LevelReady(loaded: loaded, staged: staged, fixtures: fixtures);
  }

  /// An edit of the level being played, built and waiting for
  /// [installEdit], with the build it was made to replace.
  ({LevelReady edited, LevelReady replaces})? _edit;

  /// Whether an edit went in and the widget has not been told yet.
  bool _editUntold = false;

  /// Builds [next], an edit of the level being played, without touching the
  /// run: textures, meshes, colliders and a simulation of its own, so the
  /// swap itself can be synchronous. Throws, and changes nothing, when
  /// nothing is being played, when [next] is another level, or when it does
  /// not build.
  Future<void> prepareEdit(Level next) async {
    final playing = status;
    if (playing is! RunPlaying<LevelReady>) {
      throw StateError('no level is being played');
    }
    final name = playing.level.loaded.level.name;
    if (next.name != name) {
      throw StateError('the game is playing $name, not ${next.name}');
    }
    final device = await openDevice();
    final edited = await _build(playing.asset, device, document: next);
    final waiting = _edit;
    if (waiting != null) disposeLevel(waiting.edited);
    _edit = (edited: edited, replaces: playing.level);
  }

  /// Swaps in what [prepareEdit] built, the run carried over. Called inside
  /// the timeline's replay, so nothing here may tell the widget: that is
  /// [announceEdit]'s, once the run has been brought back to now.
  ///
  /// A build made for a level that has since been left is let go.
  void installEdit() {
    final edit = _edit;
    if (edit == null) return;
    _edit = null;
    if (!identical(level, edit.replaces)) {
      disposeLevel(edit.edited);
      return;
    }
    _editUntold = replaceLevel(edit.edited);
  }

  /// Installs the edit if [installEdit] has not, then hands the new build to
  /// [onLevelEdited]: the runner's node, the camera, the edit written into
  /// the demo.
  void announceEdit() {
    installEdit();
    final playing = status;
    final device = _device;
    if (!_editUntold || playing is! RunPlaying<LevelReady> || device == null) {
      return;
    }
    _editUntold = false;
    (onLevelEdited ?? onLevelBuilt)(playing.asset, playing.level, device);
  }

  /// Plays [demo] in the level being played, from its start, with the edits
  /// it recorded swapped in where they were (`HR3`), and says whether it
  /// kept to its checkpoints. The run is left where the demo ended.
  ///
  /// **Every edit is built before the first step**, for the reason
  /// [prepareEdit] builds ahead: a build waits on the device, and a replay
  /// that stopped to wait in the middle would be a replay with a hole in it.
  /// The swap itself is [replaceLevel], as it was when the edit arrived live.
  ///
  /// Throws, and plays nothing, when the level up is not the one the demo
  /// starts in, by path or by content.
  ///
  /// The demo plays through a loop ([replayDemoOnLoop]), its start restored
  /// as the genre's part of the loop's snapshots: the plugins it switched
  /// are switched at the same steps, and each step's events are compared
  /// with the digests the file holds as well as its checkpoints
  /// ([DemoReplay.eventDivergence]). A run on another simulation is refused
  /// there with `ReplayException`. Given [loop] — the game's own, whose
  /// systems step this run's level — it plays through that; without one,
  /// through a loop of its own that steps the level as [Staged.step] does,
  /// the genre's step and then the elements', for a test or a tool with no
  /// view.
  Future<DemoReplay> replay(Demo demo, {EngineLoop? loop}) async {
    final playing = status;
    if (playing is! RunPlaying<LevelReady>) {
      throw StateError('no level is being played');
    }
    if (playing.asset != demo.level) {
      throw StateError(
        'the demo starts in ${demo.level}, and ${playing.asset} is up',
      );
    }
    final hash = playing.level.loaded.level.digestHex;
    if (hash != demo.levelHash) {
      throw StateError(
        '${demo.level} digests to $hash, and the demo was recorded in '
        '${demo.levelHash}; the level has changed since',
      );
    }
    // A run plays back on the backend it was recorded on, and this one's
    // level is built already: said, rather than replayed into a divergence.
    if (demo.physics case final String physics
        when physics != usePhysics().name) {
      throw StateError(
        'the demo was recorded on the $physics physics and this run is on '
        '${usePhysics().name}; start the game with '
        '--dart-define=FLUTTER3D_PHYSICS=$physics to replay it',
      );
    }
    final device = await openDevice();
    final edits = <LevelReady>[
      for (final swap in demo.levelSwaps)
        await _build(playing.asset, device, document: swap.level),
    ];
    final next = edits.iterator;
    void swapLevel(Level _) {
      if (next.moveNext()) replaceLevel(next.current);
    }

    if (loop != null) {
      return replayDemoOnLoop(
        demo: demo,
        loop: loop,
        part: PlatformerPlugin.id,
        swapLevel: swapLevel,
        simulation: platformerSimulationVersion,
      );
    }
    final (loop: own, :genre) = ownLoop();
    try {
      return replayDemoOnLoop(
        demo: demo,
        loop: own,
        part: PlatformerPlugin.id,
        swapLevel: swapLevel,
      );
    } finally {
      // The run publishes onto the game's bus again, not this loop's.
      genre.simulation = null;
    }
  }

  /// A loop of the run's own, on [input]: the genre stepping whichever
  /// level is up — an edit replaces it — and the level's elements after it,
  /// as [Staged.step] steps them; the genre's run is its part of the loop's
  /// snapshots, under [PlatformerPlugin.id].
  ///
  /// For a test or a tool with no view, whose loop is the game's own
  /// otherwise. While the genre holds a level, the run's events go onto this
  /// loop's bus; set [genre]'s simulation to null to let it go.
  ({EngineLoop loop, PlatformerPlugin genre}) ownLoop() {
    final genre = PlatformerPlugin(kinds: const <EntityKind>[]);
    final loop = EngineLoop(input: input, plugins: <Flutter3dPlugin>[genre])
      ..addSystem('platformer_run.level', LoopPhase.input, (_) {
        genre.simulation = level?.sim;
      })
      ..addSystem('platformer_run.elements', LoopPhase.fields, (
        LoopContext step,
      ) {
        final up = level;
        if (up != null) stepElements(up.sim, up.staged.elements, step.dt);
      });
    genre.simulation = level?.sim;
    return (loop: loop, genre: genre);
  }

  @override
  RunOutcome outcomeOf(LevelReady level) => level.sim.state.outcome;

  @override
  String? nextOf(LevelReady level) => level.sim.nextLevel;

  @override
  Snapshot snapshotOf(LevelReady level) => level.sim.save();

  @override
  void restoreInto(LevelReady level, Snapshot snapshot) =>
      level.sim.restore(snapshot);

  /// The elapsed time in steps. It is carried from level to level and adds up
  /// the loop's fixed sixtieths, so it is the run's step count across levels
  /// without a counter of its own.
  @override
  int stepOf(LevelReady level) => (level.sim.elapsed * 60.0).round();

  /// The tally of the run so far. Only this side knows what the level after
  /// this one is, so only this side can carry anything into it.
  @override
  void carryFrom(LevelReady level, String next) => _carried = (
    lives: level.sim.lives,
    deaths: level.sim.deaths,
    elapsed: level.sim.elapsed,
    coins: level.runner.purse['coin'],
  );

  @override
  void startFresh() => _carried = null;

  /// **A platformer has lives, so losing ends the run** — and a save from
  /// before the last life would undo the loss. The crypt disagrees, and is
  /// right for itself: it has no lives, so dying is a setback rather than an
  /// ending.
  @override
  void onLost(LevelReady level) {
    _carried = null;
    unawaited(saves.clear());
  }

  @override
  Future<void> beforeNext(String next) =>
      Future<void>.delayed(pauseBetweenLevels);

  /// Gives a finished level's uploads back to the device.
  ///
  /// The hook `RunSession.close`'s own doc was written for, wired up at last:
  /// the fixtures let go of their nodes, meshes and models, then the level's
  /// own brushes and maps go back. The level's last, because the fixtures
  /// were built on its textures and share the objects rather than copies.
  @override
  void disposeLevel(LevelReady level) {
    level.fixtures.dispose();
    // The core's world, which the collector would get to eventually, let go
    // with the rest of the level.
    if (level.staged.dynamics case final NativeDynamics native) {
      native.dispose();
    }
    level.staged.elements?.dispose();
    final device = _device;
    if (device != null) level.loaded.dispose(device);
  }
}
