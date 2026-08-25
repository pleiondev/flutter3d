import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vector_math/vector_math.dart';

/// What the screen is showing, as opposed to what the game is doing.
///
/// Three things, and all three change at most once a run: whether the title
/// card has been taken down, whether the run behind it came off the disk, and
/// whether the renderer refused to start at all.
final class ScreenState {
  const ScreenState({this.started = false, this.resumed = false, this.error});

  /// Whether the player has asked to play yet, which takes the title card down.
  final bool started;

  /// Whether the run behind the title card came off the disk.
  final bool resumed;

  /// Why there is no game to show, when there is none.
  ///
  /// The renderer and the audio device are the two that can refuse at startup;
  /// a level that will not load is `RunCubit`'s to report, because by then there
  /// is a screen to report it on.
  final Object? error;

  ScreenState copyWith({bool? started, bool? resumed, Object? error}) =>
      ScreenState(
        started: started ?? this.started,
        resumed: resumed ?? this.resumed,
        error: error ?? this.error,
      );

  @override
  bool operator ==(Object other) =>
      other is ScreenState &&
      other.started == started &&
      other.resumed == resumed &&
      other.error == error;

  @override
  int get hashCode => Object.hash(started, resumed, error);
}

/// The last of `_GameScreenState`'s own state that is not per-frame.
///
/// **What is left in the widget after this is machinery, not state.** A ticker,
/// a renderer and a follow camera are touched sixty times a second, and
/// `ARCHITECTURE.md` §11.3 keeps that side of the line out of a cubit on purpose:
/// state emitted per step is an allocation and a tree rebuild per step, and
/// holding the frame rate away from the fixed step is the whole point of
/// `GameSimulation`. So this is where the screen's state stops and the loop's
/// machinery begins.
///
/// The widget stays a `StatefulWidget` regardless, and not for want of trying:
/// `Ticker` needs a `TickerProvider`, which is a widget's state and not a
/// cubit's.
final class ScreenCubit extends Cubit<ScreenState> {
  ScreenCubit() : super(const ScreenState());

  /// Where the run was when it was last written to disk.
  ///
  /// A field rather than part of [ScreenState], for the same reason
  /// `AudioCubit` keeps its scene out of one: this is asked every frame and
  /// answered `false` almost every time. Emitting a state to say "the
  /// checkpoint has not moved" sixty times a second is the thing §2.4 forbids.
  Vector3? _savedFrom;

  void begin() {
    if (state.started) return;
    emit(state.copyWith(started: true));
  }

  void resumedFromDisk({required bool resumed}) =>
      emit(state.copyWith(resumed: resumed));

  void failed(Object error) => emit(state.copyWith(error: error));

  /// Forgets where the run was saved from, because it is a different run now.
  void forgetSave() => _savedFrom = null;

  /// Whether a save is worth writing, given the respawn point is now [at].
  ///
  /// **A save is worth writing when the respawn point *moves*** — that is what
  /// passing a checkpoint means — and at no other time. Writing every frame
  /// would put a file write in the frame budget; writing only on quit loses the
  /// whole run to a crash.
  ///
  /// Answers the question and records the answer, but does not do the writing:
  /// who to tell is the widget's business, and this way nothing here has to
  /// know what a run is.
  bool shouldSave(Vector3 at) {
    final was = _savedFrom;
    if (was != null && was.distanceToSquared(at) < 1e-6) return false;
    _savedFrom = at.clone();
    return true;
  }
}
