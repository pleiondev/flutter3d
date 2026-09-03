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
final class RaceFailed extends RaceStatus {
  const RaceFailed(this.error);

  final Object error;
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

  /// The circuit in [current] has been read and is ready to draw.
  void ready() => _emit(Racing(_current));

  /// It would not read, or the device under it would not open.
  void failed(Object error) => _emit(RaceFailed(error));

  /// The circuit in [current] has been won. Decides what comes next but does
  /// not load it — [moveOn] does that once the screen's own pause at the
  /// finish line has run out.
  ///
  /// Returns the same circuit as [RaceOver.next], which is what the screen
  /// needs in order to know whether to schedule that pause at all.
  Circuit? finish() {
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

  void ready() => progress.ready();
  void failed(Object error) => progress.failed(error);
  Circuit? finish() => progress.finish();
  void moveOn(Circuit next) => progress.moveOn(next);

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
