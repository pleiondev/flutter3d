import 'package:flutter3d_app/flutter3d_app.dart'; // RunStatus
import 'package:flutter_bloc/flutter_bloc.dart';

import 'run.dart';

/// The run, as the widget tree sees it.
///
/// A wrapper and nothing more, which is the point: `RunSession` decides
/// nothing about state management, and this game happens to use BLoC — see
/// `RunSession`'s doc comment for why the class it wraps does not.
final class RunCubit extends Cubit<RunStatus<LevelReady>> {
  RunCubit(this.run) : super(run.status) {
    run.onChanged = emit;
  }

  final PlatformerRun run;

  LevelReady? get level => run.level;
  bool get isOver => run.isOver;

  Future<bool> begin() => run.begin();
  Future<void> restart() => run.restart();
  Future<void> startOver() => run.startOver();
  Future<void> advance() => run.advance();
  Future<void> load(String asset) => run.load(asset);
  void observe() => run.observe();
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
