/// One frame's worth of submitted work, and who is waiting for it.
library;

/// A frame is done when nothing this side will add to it and the GPU has
/// reported every buffer it holds. Both halves matter: a frame with one pass
/// submitted and another about to be is not finished, and a frame whose passes
/// are all submitted is not finished either until the queue says so.
final class GpuFrame {
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
  }
}
