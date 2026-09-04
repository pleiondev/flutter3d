import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_screens/flutter3d_screens.dart';

import 'run_status.dart';

export 'run_status.dart';

/// The run: which level is up, what happened to it, and where to go next.
///
/// ## What this replaces
///
/// Three games, three answers, none of them shared:
///
/// | | |
/// |---|---|
/// | dungeon | a 278-line cubit with nine tests |
/// | platformer | nine private methods and five fields inside a 1441-line widget |
/// | racing | nothing at all |
///
/// The same sequence in each: load a document, say why if it will not read,
/// start again, move on when the level says there is somewhere to move on to,
/// write the run down, put it back, and tell the screen how it ended.
///
/// ## Why the awkward parts are here
///
/// Everything in this class that is longer than a line is a rule that has been
/// got wrong at least once:
///
/// * **[advance] does nothing twice.** A finished level stays finished for
///   every frame until the next one is up, and without the guard each of those
///   frames starts another load — a dozen of them on a slow disk.
/// * **[begin] falls back.** A save naming a level that no longer exists is a
///   player whose game will not start, and renaming a level file should not
///   brick every save that mentions it.
/// * **[save] refuses a finished run.** A save written at the exit is a save
///   the next launch resumes, putting the player back at the end of a level
///   they already beat.
/// * **[restart] rebuilds rather than resumes.** A run that begins with the
///   health you died at is not a restart.
///
/// ## Not a cubit
///
/// An ordinary class, so this package makes no choice about state management
/// for the games above it. Two of the three wrap it in a cubit; [onChanged]
/// fires on every transition and each transition builds a fresh [RunStatus], so
/// a `Cubit.emit` of it is a distinct state and rebuilds.
///
/// [L] is whatever a game gets back from loading a level. This class never
/// looks inside it — the five methods below are how it asks.
abstract base class RunSession<L> {
  RunSession({required this.firstLevel, required this.saves, this.onChanged});

  /// Where a new game starts.
  final String firstLevel;

  final SaveFile saves;

  /// Called after every transition. A cubit passes its own `emit` through here.
  void Function(RunStatus<L> status)? onChanged;

  RunStatus<L> get status => _status;
  RunStatus<L> _status = RunLoading<L>();

  /// The level that is up, or null.
  L? get level => switch (_status) {
    RunPlaying<L>(:final level) => level,
    _ => null,
  };

  /// Whether the run has ended, either way.
  bool get isOver => switch (_status) {
    RunPlaying<L>(:final outcome) => outcome.isOver,
    _ => false,
  };

  /// Guards the one-way trip out of a finished level.
  bool _movingOn = false;

  // ── What a game has to answer ──────────────────────────────────────────────

  /// Reads [asset] and builds everything it takes to play it.
  ///
  /// Throwing is the way to say it could not be read; the caller lands in
  /// [RunFailed] with the error, and the player sees the filename rather than
  /// a black screen.
  Future<L> open(String asset);

  /// How the run in [level] is going, in the words every game shares.
  RunOutcome outcomeOf(L level);

  /// Which document comes after this one, or null for the end of the game.
  String? nextOf(L level);

  /// The run so far, for the save file.
  Snapshot snapshotOf(L level);

  /// Puts a saved run back into a freshly loaded level.
  ///
  /// Called **after** the level is fully built rather than during it: restoring
  /// moves bodies and re-indexes the broadphase, and doing that while a level
  /// is still being populated leaves the grid describing a world that has since
  /// changed.
  void restoreInto(L level, Snapshot snapshot);

  /// What the player takes with them into [next]. Empty by default.
  ///
  /// Called on the level being left, before the next one is read — which is the
  /// only moment both are knowable. The dungeon empties the key ring here; the
  /// platformer copies the lives, the deaths and the elapsed time.
  void carryFrom(L level, String next) {}

  /// What a fresh run starts with. Empty by default.
  ///
  /// Called by [restart] and by [begin] when there is nothing to resume.
  void startFresh() {}

  /// Lets go of a level that is being left. Nothing by default.
  ///
  /// **There was no such hook**, and its absence is what made a level change
  /// leak: the whole surface here was about building a level and reading how
  /// it was going, and nothing ever told a game that the last one was over.
  /// The scene nodes, the uploaded meshes, the actor visuals and the
  /// registered step systems all stayed built, and the next level added its
  /// own beside them.
  ///
  /// Called at two moments, both of which are "this level will never be seen
  /// again": on the level being left, once the next one has started loading;
  /// and on a level that finished loading only to find a newer load had
  /// started while it was reading — see [load], where dropping that one on the
  /// floor used to be the only option.
  ///
  /// Not called for a level the player is coming back to, because there is no
  /// such thing here: [restart] reads the document again rather than rewinding
  /// what is in memory.
  void close(L level) {}

  /// What a game does about a run that ended badly. Nothing by default.
  ///
  /// **The two genres disagree here and both are right.** A platformer has
  /// lives, so losing ends the *run* and the save goes with it — coming back to
  /// a save from before the last life would undo the loss. A crypt has no
  /// lives, so dying is a setback and the save is where you come back to.
  ///
  /// So this is a hook rather than a rule: the shared part is noticing, and
  /// what it means belongs to the game.
  void onLost(L level) {}

  /// A beat before the next level is read. Immediate by default.
  ///
  /// The platformer waits on its results screen: arriving somewhere new in the
  /// same frame the last place ended reads as a glitch. Awaited here rather
  /// than slept through by the caller, because the guard against moving on
  /// twice has to be held for the whole wait — which is exactly when a second
  /// frame would try.
  Future<void> beforeNext(String next) async {}

  // ── What this class does with the answers ─────────────────────────────────

  /// Starts a game: the saved run if there is one, otherwise [firstLevel].
  ///
  /// Returns whether it resumed, which is what a title card wants to say.
  Future<bool> begin() async {
    final saved = saves.read();
    if (saved == null) {
      startFresh();
      await load(firstLevel);
      return false;
    }
    await load(saved.level, resume: saved.run);
    if (_status is RunFailed<L>) {
      // A save naming a level that is gone. The player gets a game rather than
      // an error, and the broken save goes with it — keeping it would fail the
      // same way on every launch from here on.
      saves.clear();
      startFresh();
      await load(firstLevel);
      return false;
    }
    return true;
  }

  /// Reads [asset] and puts it on screen.
  ///
  /// [resume] is a run to put back into it, and is only ever a snapshot saved
  /// from *this* level — [SaveFile] stores the two together for that reason.
  Future<void> load(String asset, {Snapshot? resume}) async {
    // **Which load this is.** `_movingOn` guarded `advance` and nothing else,
    // so a restart pressed during a slow load — or a second `load` from an
    // application's own code — ran two `open` calls at once, and whichever
    // finished second won. The loser was a fully built level: colliders, scene
    // nodes, uploaded meshes, registered systems, all dropped on the floor
    // with no way to reclaim them, which is the leak `close` exists for.
    final generation = ++_loadGeneration;

    final leaving = switch (_status) {
      RunPlaying<L>(:final level) => level,
      _ => null,
    };
    _emit(RunLoading<L>(asset: asset));
    // Before the read rather than after it, so two levels are never alive at
    // once. The status is already `RunLoading`, so nothing is drawing this one.
    if (leaving != null) close(leaving);

    try {
      final level = await open(asset);
      if (generation != _loadGeneration) {
        // A newer load started while this one was reading, and its level is
        // the one the player will see. Finish with this one rather than
        // dropping it, and emit nothing — a stale load publishing its status
        // would put the newer one's screen back to this one's.
        close(level);
        return;
      }
      if (resume != null) restoreInto(level, resume);
      _movingOn = false;
      _emit(RunPlaying<L>(asset, level));
    } catch (error, trace) {
      if (generation != _loadGeneration) return;
      debugPrint('level: could not load $asset: $error\n$trace');
      _emit(RunFailed<L>(asset, error));
    }
  }

  /// Counts loads, so one that finishes late can tell it has been overtaken.
  int _loadGeneration = 0;

  /// Reads how the run is going and republishes it if it changed.
  ///
  /// Call once per step. **Only on a change**, and that is not an optimisation:
  /// a finished run stays finished for every frame afterwards, so a status
  /// emitted per step would rebuild the tree sixty times a second.
  void observe() {
    final playing = _status;
    if (playing is! RunPlaying<L>) return;
    final now = outcomeOf(playing.level);
    if (now == playing.outcome) return;
    _emit(RunPlaying<L>(playing.asset, playing.level, outcome: now));
  }

  /// Puts the current level back the way it started.
  Future<void> restart() async {
    final here = switch (_status) {
      RunPlaying<L>(:final asset) => asset,
      RunFailed<L>(:final asset) => asset,
      _ => firstLevel,
    };
    saves.clear();
    startFresh();
    await load(here);
  }

  /// Throws the run away and starts the game again from [firstLevel].
  ///
  /// **Not [restart]**, and the difference is the whole point of it: [restart]
  /// reloads the level that is up, and the reason a player reaches for this is
  /// usually that the level that is up will not load. Restarting there reads
  /// the same broken document again, for ever.
  ///
  /// [begin] already does this on the one path it can see — a save naming a
  /// level that has been renamed away — but a level that exists and throws
  /// halfway through is a content mistake it cannot detect, and until this
  /// existed the only way out of one was to close the application. The
  /// platformer had written the half of it that clears the save; without
  /// [startFresh] beside it the lives and the elapsed time of the abandoned
  /// run followed the player into the new one.
  Future<void> startOver() async {
    saves.clear();
    startFresh();
    await load(firstLevel);
  }

  /// Moves on if the level said there is somewhere to move on to.
  ///
  /// Call once per frame. Does nothing until the run is won, and nothing twice.
  Future<void> advance() async {
    final playing = _status;
    if (playing is! RunPlaying<L> || _movingOn) return;
    if (!playing.outcome.isOver) return;

    _movingOn = true;
    if (playing.outcome == RunOutcome.lost) {
      onLost(playing.level);
      return;
    }
    final next = nextOf(playing.level);
    if (next == null) {
      // The end of the game. The save goes, or the next launch resumes a run
      // that is already over.
      saves.clear();
      return;
    }
    carryFrom(playing.level, next);
    await beforeNext(next);
    await load(next);
    // Written once the level is up, so the save describes where the player
    // actually is rather than a level they have not entered.
    save();
  }

  /// Writes where the run has got to, if there is one worth writing.
  void save() {
    final playing = _status;
    if (playing is! RunPlaying<L> || playing.outcome.isOver) return;
    saves.write(playing.asset, snapshotOf(playing.level));
  }

  void _emit(RunStatus<L> next) {
    _status = next;
    onChanged?.call(next);
  }
}
