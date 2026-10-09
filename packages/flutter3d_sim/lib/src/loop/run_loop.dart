/// A headless run stepped through an [EngineLoop], so a tool that drives a
/// game blind uses the loop's one path for state like a game does.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

import '../input/input_state.dart';
import '../save/snapshot.dart';
import 'engine_loop.dart';
import 'engine_time.dart';
import 'headless_run.dart';

/// A [HeadlessRun] inside an [EngineLoop] of its own: the run steps in the
/// loop's `rules` phase, and its save is a part of the loop's snapshots.
///
/// **The adapter that puts a run on the loop's one path** (item 27). A
/// [HeadlessGame] starts a run that steps itself and saves itself; a tool
/// that wants to rewind it, bisect two of it or keep captures of it would
/// otherwise carry a pair of functions — `run.save` and `run.restore` —
/// beside the run, and every such pair is a path for state the loop's own
/// checks do not cover. Here the loop's [EngineLoop.capture],
/// [EngineLoop.restore] and [EngineLoop.rewindTo] reach the run through its
/// part, [partId], and the loop's input, tape playback and step count are
/// the run's.
///
/// A capture holds the run's save under [savePath]; [captureFrom] makes one
/// from a run's own save (a `.f3drun`'s start), and [saveIn] reads it back.
final class RunLoop {
  /// [run], stepped through a new loop reading [input] at [timing]'s rate.
  ///
  /// The run must step at that rate too: the loop hands it its own `dt`.
  RunLoop(this.run, {required InputState input, WorldTiming? timing})
    : loop = EngineLoop(input: input, timing: timing ?? const WorldTiming()) {
    loop
      ..addSystem(
        systemName,
        LoopPhase.rules,
        (context) => run.step(context.dt),
      )
      ..snapshots.add(
        SnapshotPart.of(
          id: partId,
          capture: () => run.save().data,
          restore: (data, _) {
            final saved = data is Map
                ? Snapshot(data.cast<String, Object?>())
                : throw StateError(
                    'the run\'s part of the capture is not a save: $data',
                  );
            switch (run) {
              case final RestorableRun restorable:
                restorable.restore(saved);
              default:
                throw StateError(
                  'a ${run.runtimeType} cannot be put back to a state it '
                  'saved: it is not a RestorableRun',
                );
            }
          },
        ),
      );
  }

  /// The run the loop steps.
  final HeadlessRun run;

  /// The loop it steps in.
  final EngineLoop loop;

  /// The name of the run's system in the `rules` phase.
  static const String systemName = 'headless.run';

  /// The run's part of the loop's snapshots.
  static const String partId = 'run';

  /// Where a capture holds the run's own save: what an `EntityLayout` written
  /// for the run's save reads under (`EntityLayout.under`).
  static const List<String> savePath = <String>[partId, 'data'];

  /// Whether the run can be put back, which a rewind and a bisection need.
  bool get isRestorable => run is RestorableRun;

  /// A capture of the loop with the run put back to [save], one of the
  /// run's own saves: the start a `ReplaySide.loop` plays a tape from.
  Snapshot captureFrom(Snapshot save) {
    loop.restore(
      Snapshot(<String, Object?>{
        partId: <String, Object?>{'version': 1, 'data': save.data},
      }),
    );
    return loop.capture();
  }

  /// The run's own save inside [captured], a capture of this loop; null when
  /// it holds none (absent).
  static Snapshot? saveIn(Snapshot captured) => switch (captured.data[partId]) {
    {'data': final Map<Object?, Object?> data} => Snapshot(
      data.cast<String, Object?>(),
    ),
    _ => null,
  };
}
