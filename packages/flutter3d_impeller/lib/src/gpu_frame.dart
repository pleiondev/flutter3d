/// One frame's worth of submitted work, and who is waiting for it.
library;

/// A frame is done when nothing this side will add to it and the GPU has
/// reported every buffer it holds. Both halves matter: a frame with one pass
/// submitted and another about to be is not finished, and a frame whose passes
/// are all submitted is not finished either until the queue says so.
final class GpuFrame {
  int outstanding = 0;
  bool encoded = false;
  bool _settled = false;
  final List<void Function()> whenDone = <void Function()>[];

  void settleIfDone() {
    if (_settled || !encoded || outstanding > 0) return;
    _settled = true;
    for (final callback in whenDone) {
      callback();
    }
    whenDone.clear();
  }
}
