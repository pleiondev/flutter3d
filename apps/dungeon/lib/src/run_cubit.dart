import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_shooter/flutter3d_shooter.dart';
import 'package:flutter3d_ui/flutter3d_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'staging.dart';

/// A level, drawn and playable.
///
/// Holds the live objects rather than copies of their numbers: a scene, a
/// simulation and two sets of visuals are things the render loop reads sixty
/// times a second, and putting their contents in a state class would mean
/// emitting one per frame — which is exactly what the boundary beside the
/// `flutter_bloc` dependency says not to do.
///
/// What the *state machine* is about is which of these exists and whether the
/// run in it is over. That changes a handful of times per session.
final class LevelReady {
  const LevelReady({
    required this.asset,
    required this.loaded,
    required this.staged,
    required this.actorVisuals,
    required this.fixtureVisuals,
  });

  /// Which document this is. Kept because a save is a level and a snapshot
  /// together, and a snapshot restored into the wrong level is worse than no
  /// save at all.
  final String asset;

  final LoadedLevel loaded;
  final Staged staged;
  final ActorVisuals actorVisuals;
  final FixtureVisuals fixtureVisuals;
}

/// What the game is doing, as far as a screen is concerned.
sealed class RunState {
  const RunState();
}

/// Before the first level, and between one and the next.
final class RunLoading extends RunState {
  const RunLoading({this.asset});

  /// Which one is coming, when that is known. Null on the very first load, when
  /// the graphics device is still opening.
  final String? asset;
}

/// A level is up. [outcome] is the simulation's own answer, republished here so
/// a screen can watch one thing.
final class RunPlaying extends RunState {
  const RunPlaying(this.level, {this.outcome = GameState.playing});

  final LevelReady level;
  final GameState outcome;

  bool get isOver => outcome != GameState.playing;
}

/// Nothing is up, and this is why.
///
/// **A level that will not read used to be a black screen for ever.** The
/// application caught the throw and printed it, which is a line in a console
/// nobody playing the game can see.
final class RunFailed extends RunState {
  const RunFailed(this.asset, this.error);

  final String asset;
  final Object error;
}

/// The run: which level is up, what happened to it, and where to go next.
///
/// **Testable, and that is the reason it exists rather than four more fields on
/// the widget.** Loading a level needs a graphics device but not a window, so
/// this can be driven from a plain `test()` with `CpuDevice` — which is the
/// door round the wall `playing_the_game_test.dart` records: `LevelLoader` does
/// not complete under `testWidgets`, and it completes perfectly well in an
/// ordinary test. Restarting, moving to the next level, saving and resuming are
/// therefore all reachable without mounting anything.
///
/// [openScene] is the one seam to the renderer: it is handed a freshly loaded
/// level and returns the two sets of visuals. A test that only cares about the
/// chain hands back empty ones.
final class RunCubit extends Cubit<RunState> {
  RunCubit({
    required this.firstLevel,
    required this.registry,
    required this.input,
    required this.inventory,
    required this.saves,
    required this.loader,
    required this.openScene,
    this.eyeOffset = 0.7,
    this.lookSensitivity = 0.0022,
  }) : super(const RunLoading());

  /// Where a new game starts.
  final String firstLevel;

  /// One registry validates the document and then spawns it.
  final EntityRegistry registry;

  final InputState input;

  /// What the player is carrying.
  ///
  /// **Carried across levels on purpose**: health and ammunition are what a
  /// corridor costs you, and a game that refilled both at every door is a game
  /// with no corridors in it. Keys are not carried — see [_next].
  ///
  /// Replaced rather than emptied on a restart, which is the difference between
  /// starting again and continuing at nought health.
  Inventory inventory;

  final SaveFile saves;

  /// Reads the document and builds the scene. A function rather than the class
  /// so a test can hand over a device of its own.
  final Future<LoadedLevel> Function(String asset, EntityRegistry registry)
      loader;

  /// Builds what draws, once there is a scene to build it in.
  final ({ActorVisuals actors, FixtureVisuals fixtures}) Function(
    LoadedLevel loaded,
  ) openScene;

  final double eyeOffset;
  final double lookSensitivity;

  /// Guards the one-way trip out of a finished level.
  ///
  /// The simulation stays `complete` for every frame until the next level is
  /// up, and without this each of those frames would start loading it.
  bool _movingOn = false;

  /// Starts a game: the saved run if there is one for a level that still
  /// exists, otherwise the first level.
  ///
  /// Returns whether it resumed, which is what a title card wants to say.
  Future<bool> begin() async {
    final saved = saves.read();
    if (saved == null) {
      await load(firstLevel);
      return false;
    }
    await load(saved.level, resume: saved.run);
    // A save naming a level that no longer exists lands in [RunFailed], and a
    // player whose save is broken should get a game rather than an error — so
    // the fallback is the first level and the save is dropped.
    if (state is RunFailed) {
      saves.clear();
      await load(firstLevel);
      return false;
    }
    return true;
  }

  /// Reads [asset] and puts it on screen. [resume] is a run to put back into
  /// it, and is only ever a snapshot saved from *this* level.
  Future<void> load(String asset, {Snapshot? resume}) async {
    emit(RunLoading(asset: asset));
    try {
      final loaded = await loader(asset, registry);
      final scene = openScene(loaded);
      final staged = stage(
        loaded.level,
        loaded.collision,
        input: input,
        registry: registry,
        inventory: inventory,
        onActorSpawned: scene.actors.add,
        onFixture: scene.fixtures.add,
        eyeOffset: eyeOffset,
        lookSensitivity: lookSensitivity,
      );

      // After the scene is built rather than during it: `restore` moves bodies
      // and re-indexes the broadphase, and doing that while the fixtures are
      // still being added would leave the grid describing a world that has
      // since changed.
      if (resume != null) staged.sim.restore(resume);

      _movingOn = false;
      emit(RunPlaying(LevelReady(
        asset: asset,
        loaded: loaded,
        staged: staged,
        actorVisuals: scene.actors,
        fixtureVisuals: scene.fixtures,
      )));
    } catch (error, trace) {
      debugPrint('level: could not load $asset: $error\n$trace');
      emit(RunFailed(asset, error));
    }
  }

  /// Reads the simulation's state and republishes it, once per step.
  ///
  /// Emitting only on a change is not an optimisation: `GameState.complete`
  /// stays true for every frame after the exit, and a state emitted per step
  /// would rebuild the tree sixty times a second — which is the boundary this
  /// application draws around `flutter_bloc` in its pubspec.
  void observe() {
    final playing = state;
    if (playing is! RunPlaying) return;
    final outcome = playing.level.staged.sim.state;
    if (outcome == playing.outcome) return;
    emit(RunPlaying(playing.level, outcome: outcome));
  }

  /// The level that is up, or null.
  LevelReady? get level => switch (state) {
        RunPlaying(:final level) => level,
        _ => null,
      };

  /// Puts the current level back the way it started.
  ///
  /// **The whole of what this game could do about dying was print a word.**
  /// There was no restart at all: the only way out of a death was to close the
  /// application. The inventory is rebuilt rather than reused, because a run
  /// that begins with the health you died at is not a restart.
  Future<void> restart() async {
    final here = level?.asset ?? firstLevel;
    saves.clear();
    inventory = startingInventory();
    await load(here);
  }

  /// Moves on if the level said there is somewhere to move on to.
  ///
  /// Call once per frame. Does nothing until the level is finished, and nothing
  /// twice.
  Future<void> advance() async {
    final playing = state;
    if (playing is! RunPlaying || _movingOn) return;
    if (playing.outcome != GameState.complete) return;

    _movingOn = true;
    final next = playing.level.staged.sim.nextLevel;
    if (next == null) {
      // The end of the game. The save goes, or the next launch resumes a run
      // that is over.
      saves.clear();
      return;
    }
    await _next(next);
  }

  Future<void> _next(String asset) async {
    // Keys do **not** carry. A key opens one door in one place, and a player
    // arriving at the second level already holding the third level's key is a
    // level designer's promise broken by the plumbing.
    inventory.keys.clear();
    saves.write(asset, const Snapshot(<String, Object?>{}));
    await load(asset);
    // Written again once the level is up, so the save describes where the
    // player actually is rather than a level they have not entered.
    save();
  }

  /// Writes where the run has got to, if there is one.
  ///
  /// Called when the respawn point moves rather than every frame: a file write
  /// in the frame budget is a stutter, and writing only on quit loses the whole
  /// run to a crash.
  void save() {
    final playing = state;
    if (playing is! RunPlaying || playing.isOver) return;
    saves.write(playing.level.asset, playing.level.staged.sim.save());
  }
}
