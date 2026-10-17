/// One frame's worth of submitted work, and who is waiting for it.
library;

import 'dart:developer' show TimelineTask;

import 'package:flutter3d_hardware/flutter3d_hardware.dart'
    show GpuFrameTimings, GpuPassTiming;

/// A frame is done when nothing this side will add to it and the GPU has
/// reported every buffer it holds. Both halves matter: a frame with one pass
/// submitted and another about to be is not finished, and a frame whose passes
/// are all submitted is not finished either until the queue says so.
final class GpuFrame {
  /// Frame [number], timing its labelled passes by [now] (microseconds) and
  /// handing them to [report] once the frame is done.
  GpuFrame({this.number = 0, int Function()? now, this.report})
    : _now = now ?? _clock;

  /// Which frame, counted by `beginFrame` from the first.
  final int number;

  /// Where this frame's pass timings go once it settles; null takes none.
  final void Function(GpuFrameTimings timings)? report;

  final int Function() _now;
  static final Stopwatch _stopwatch = Stopwatch()..start();
  static int _clock() => _stopwatch.elapsedMicroseconds;

  /// Each labelled pass, in submission order, with how long the queue took
  /// over it — null until it completes.
  final List<({String label, int? micros})> _passes =
      <({String label, int? micros})>[];

  /// **GPU timings through the engine's own timeline, since 1.0.** flutter_gpu
  /// has no timestamp query, so the one span this side can see of a pass is
  /// from its submission to the queue's completion callback: the GPU's time
  /// on it, plus whatever it waited for behind the passes before it. Each
  /// labelled pass is that span on the Dart timeline (DevTools, Perfetto,
  /// `flutter run --profile`), named `GPU <label>` with its frame, and in the
  /// [GpuFrameTimings] the device's `onGpuTimings` listener receives.
  ///
  /// Call at submission; call what this returns at completion.
  void Function() timePass(String label) {
    final index = _passes.length;
    _passes.add((label: label, micros: null));
    final began = _now();
    final task = TimelineTask()
      ..start('GPU $label', arguments: <String, Object>{'frame': number});
    return () {
      task.finish();
      _passes[index] = (label: label, micros: _now() - began);
    };
  }

  /// Passes opened and not yet submitted.
  ///
  /// **Counted apart from [outstanding], which it used to share.** One number
  /// cannot tell "the GPU is still working" from "a pass was opened and the
  /// frame threw before it was submitted", and the difference decides whether
  /// waiting is right. A frame that threw mid-encode kept a count that nothing
  /// would ever decrement, so [settleIfDone] never fired and everything in
  /// [whenDone] — the callback that puts a composited frame back into
  /// rotation — never ran. One full-screen texture stranded per failed frame,
  /// on a path whose own comment notes that a frame which fails tends to fail
  /// again next frame.
  int encoding = 0;

  /// Buffers submitted whose completion the queue has not reported.
  int outstanding = 0;

  bool encoded = false;
  bool _settled = false;
  final List<void Function()> whenDone = <void Function()>[];

  /// Gives up on passes opened and never submitted.
  ///
  /// Called when the next frame begins, which is the moment nothing more can
  /// be added to this one: anything still open at that point was abandoned by
  /// a throw, and holding the frame open for it means holding it open for
  /// ever. What was genuinely submitted is still waited for — that is
  /// [outstanding], and it is untouched here.
  void abandonUnsubmitted() => encoding = 0;

  void settleIfDone() {
    if (_settled || !encoded || encoding > 0 || outstanding > 0) return;
    _settled = true;
    for (final callback in whenDone) {
      callback();
    }
    whenDone.clear();
    final sink = report;
    if (sink == null || _passes.isEmpty) return;
    sink(
      GpuFrameTimings(
        frame: number,
        passes: List<GpuPassTiming>.unmodifiable(<GpuPassTiming>[
          for (final (:label, :micros) in _passes)
            if (micros != null) GpuPassTiming(label: label, micros: micros),
        ]),
      ),
    );
  }
}
