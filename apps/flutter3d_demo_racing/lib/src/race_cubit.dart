import 'package:flutter_bloc/flutter_bloc.dart';

import 'circuits.dart';

/// What the screen is doing, as far as the season is concerned.
///
/// Not a `RunStatus`: see the doc comment on [Season] in `circuits.dart` for
/// why a season has no snapshot to restore and so no `RunSession` under it.
/// What is left, once the ceremony that class exists for is taken out, is
/// three questions rather than five — is a circuit up, did it fail to read,
/// and did the one just raced end the season or only the lap.
sealed class RaceStatus {
  const RaceStatus();
}

/// Before the first circuit, and between the finish line and the next one
/// being up.
final class RaceLoading extends RaceStatus {
  const RaceLoading();
}

/// A circuit is up and can be driven.
final class Racing extends RaceStatus {
  const Racing(this.circuit);

  final Circuit circuit;
}

/// The circuit in [circuit] has been won. [next] says what the screen does
/// about it: raced again after a pause, or nothing, because there was
/// nowhere further to go.
///
/// **One class for both rather than two.** A screen that has just finished a
/// circuit and a screen that has just finished the season look the same —
/// the race keeps running under a line of text — and differ only in whether
/// that text names somewhere to go. Two classes would still need the same
/// `if (next == null)` at the one place either is read.
final class RaceOver extends RaceStatus {
  const RaceOver(this.circuit, {required this.next});

  final Circuit circuit;

  /// The circuit raced after this one, or null when [circuit] was the last —
  /// the season is over, and the screen says so for good, since nothing here
  /// ever calls [RaceProgress.moveOn] to leave that behind.
  final Circuit? next;

  bool get seasonComplete => next == null;
}

/// A circuit would not read, or the device it is drawn through would not
/// open. Both land here: either way there is nothing on screen to race.
///
/// **[asset] is what tells the two apart**, and the screen needs to: a device
/// that will not open is the engine's problem and its screen carries the
/// shader-bundle sentence, while a circuit that will not read is a content
/// mistake and the only useful thing to say is which file. This carried
/// neither for a while — the screen printed the thrown object on black, with
/// no filename, no explanation and nothing to press.
final class RaceFailed extends RaceStatus {
  const RaceFailed(this.error, {this.asset});

  final Object error;

  /// The circuit document that would not read, or null when the failure was
  /// the graphics device rather than a file.
  final String? asset;
}

/// What a season came to: circuits won, laps driven, and the best of them.
///
/// **The screen at the end of the season had none of this to show**, because
/// nothing added it up: every number this game keeps belongs to one race —
/// `RacerProgress` is rebuilt with each circuit — and the season was five
/// unrelated races with a caption after the last.
///
/// Mutable fields rather than a value rebuilt per circuit. It is state; there
/// are five writes in a season, and the alternative is a copy constructor and
/// an emit for each.
final class SeasonTally {
  int circuits = 0;
  int laps = 0;

  /// The quickest lap of the season, or null before one is driven.
  ///
  /// **Not `GhostKeeper.record`**, which is what has ever been driven on a
  /// circuit across every evening. A screen reporting that at the end of a slow
  /// season would congratulate a driver on a lap they did not drive.
  double? bestLap;

  /// A circuit finished. [bestLap] is that race's own best, or null if the
  /// player never completed a clean lap of it.
  void won({required int laps, double? bestLap}) {
    circuits++;
    this.laps += laps;
    final best = this.bestLap;
    if (bestLap != null && (best == null || bestLap < best)) {
      this.bestLap = bestLap;
    }
  }

  void reset() {
    circuits = 0;
    laps = 0;
    bestLap = null;
  }
}

/// How far into the season the player has got, and what to say about it.
///
/// **What `RunSession` would have been, with the middle taken out.** The
/// other two games load a level, snapshot it, restore it and move on, and
/// `flutter3d_session` holds that shape for them. Racing has no middle: nobody
/// resumes a race half a lap in, so there is no snapshot here and nothing
/// this class calls `restoreInto`. What is left is three transitions —
/// [ready], [finish] and [moveOn] — where `RunSession` needed five.
///
/// The scene, the cars, the track and every other sixty-hertz thing stay out
/// of this on purpose: this only ever holds a [Circuit], which is a name and
/// two file paths, and the render loop's own state would turn every step of
/// it into an allocation and an emit.
final class RaceProgress {
  RaceProgress({this.onChanged});

  /// Called after every transition. [RaceCubit] passes its own `emit` through
  /// here, the same way a game's cubit does for `RunSession`.
  void Function(RaceStatus status)? onChanged;

  RaceStatus get status => _status;
  RaceStatus _status = const RaceLoading();

  /// Which circuit is current — being read, being raced, or just finished.
  ///
  /// Always the first at a launch. Nothing about a season is saved: it is one
  /// sitting, and a game that remembered the circuit reached opened on the
  /// second one for anybody who had won the first.
  Circuit get current => _current;
  Circuit _current = Season.first;

  /// What this season has come to, for the screen at the end of it.
  final SeasonTally season = SeasonTally();

  /// The circuit in [current] has been read and is ready to draw.
  void ready() => _emit(Racing(_current));

  /// It would not read, or the device under it would not open. [asset] names
  /// the document in the first case and is left out in the second.
  void failed(Object error, {String? asset}) =>
      _emit(RaceFailed(error, asset: asset));

  /// Throws the season away and starts it again at the first circuit.
  ///
  /// **The one transition this class did not have**, and the two places that
  /// wanted it were the ends of the game: a season that is complete keeps
  /// running under a caption, and a circuit that will not read is a screen
  /// with nothing on it to press. Neither had a way back, because there is no
  /// `restart` here either — the other two games get one from `RunSession`,
  /// and a season is not one.
  ///
  /// Loading is still the screen's: this only says where the season is.
  void startOver() {
    _current = Season.first;
    // A season raced again is a season, not a longer one. Without this the
    // ending screen after the second run of it would report ten circuits.
    season.reset();
    _emit(const RaceLoading());
  }

  /// The circuit in [current] has been won. Decides what comes next but does
  /// not load it — [moveOn] does that once the screen's own pause at the
  /// finish line has run out.
  ///
  /// Returns the same circuit as [RaceOver.next], which is what the screen
  /// needs in order to know whether to schedule that pause at all.
  /// [laps] and [bestLap] are the race that has just been won, added into
  /// [season] — the only moment either is knowable, since the next circuit
  /// rebuilds every number this game keeps about a race.
  Circuit? finish({int laps = 0, double? bestLap}) {
    season.won(laps: laps, bestLap: bestLap);
    final next = Season.after(_current);
    _emit(RaceOver(_current, next: next));
    return next;
  }

  /// Leaves the circuit that was just won and starts reading [next].
  void moveOn(Circuit next) {
    _current = next;
    _emit(const RaceLoading());
  }

  void _emit(RaceStatus next) {
    _status = next;
    onChanged?.call(next);
  }
}

/// The season, as the widget tree sees it.
///
/// A wrapper and nothing more, which is the point: [RaceProgress] decides
/// nothing about state management, and this game happens to use BLoC — see
/// the note in `packages/flutter3d_screens/pubspec.yaml`.
final class RaceCubit extends Cubit<RaceStatus> {
  RaceCubit(this.progress) : super(progress.status) {
    progress.onChanged = emit;
  }

  final RaceProgress progress;

  Circuit get circuit => progress.current;

  /// What the season has come to. See [SeasonTally].
  SeasonTally get season => progress.season;

  void ready() => progress.ready();
  void failed(Object error, {String? asset}) =>
      progress.failed(error, asset: asset);
  Circuit? finish({int laps = 0, double? bestLap}) =>
      progress.finish(laps: laps, bestLap: bestLap);
  void moveOn(Circuit next) => progress.moveOn(next);
  void startOver() => progress.startOver();

  @override
  Future<void> close() {
    // Unhooked before the stream closes: a circuit load still in flight
    // reports through [RaceProgress.onChanged] when it lands, and that report
    // would otherwise be an emit into a closed cubit — a `StateError` over
    // whatever the screen was being torn down for.
    progress.onChanged = null;
    return super.close();
  }
}
