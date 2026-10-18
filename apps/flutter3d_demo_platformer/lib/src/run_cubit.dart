import 'package:flutter3d_game/flutter3d_game.dart'; // RunStatus
import 'package:flutter_bloc/flutter_bloc.dart';

import 'run.dart';

/// The run, as the widget tree sees it.
///
/// A wrapper and nothing more, which is the point: `RunSession` decides
/// nothing about state management, and this game happens to use BLoC — see
/// `RunSession`'s doc comment for why the class it wraps does not.
final class RunCubit extends Cubit<RunStatus<LevelReady>> {
  /// A cubit over [run], starting at its status and emitting each change.
  RunCubit(this.run) : super(run.status) {
    run.onChanged = emit;
  }

  /// The run this cubit reports.
  final PlatformerRun run;

  /// The level being played, or null while none is up.
  LevelReady? get level => run.level;

  /// Whether the run has ended, either way.
  bool get isOver => run.isOver;

  /// Starts the saved run if there is one, otherwise the first level, and
  /// answers whether it resumed.
  Future<bool> begin() => run.begin();

  /// Puts the level that is up back the way it started.
  Future<void> restart() => run.restart();

  /// Throws the run away and starts again from the first level, the save
  /// cleared.
  Future<void> startOver() => run.startOver();

  /// Moves on if the level said there is somewhere to move on to.
  Future<void> advance() => run.advance();

  /// Reads the level at [asset] and puts it on screen.
  Future<void> load(String asset) => run.load(asset);

  /// Reads how the run is going and republishes it if it changed; once a
  /// step.
  void observe() => run.observe();

  /// Writes where the runner is to the save, without waiting for the write.
  void save() => run.save();

  @override
  Future<void> close() {
    // Unhooked before the stream closes: a load or an advance still in flight
    // finishes on the session's side, and its report would otherwise be an
    // emit into a closed cubit — a `StateError` over whatever the screen was
    // being torn down for.
    run.onChanged = null;
    return super.close();
  }
}
