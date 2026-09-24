/// One allowance of time per frame for the work that can wait — `N3`.
library;

/// How many microseconds a frame may spend on work that can be spread over
/// frames: irradiance probe updates, point-shadow faces, static shadow
/// scrolls, reflection probe faces, texture uploads.
///
/// **Time, where each of those used to count items.** A count is a guess at
/// a cost: four irradiance probes are cheap in a small room and expensive in
/// a field of a thousand, and a scheduler that counts faces cannot know that
/// the face it picks this frame holds the whole level. What a player feels
/// is a frame that took three times as long as the one before it, so the
/// allowance is the thing that decides.
///
/// Each piece of work asks [allows] before it starts and [charge]s what it
/// cost when it ends; [spend] does both for a closure. A piece is allowed
/// when what the frame has spent plus what a piece has been costing still
/// fits, so the allowance is not overrun by the piece that tips it — the
/// cost is a running average, carried from frame to frame. The first piece
/// of a frame is always allowed, whatever the allowance, so every queue
/// drains even on a device too slow to fit one item: progress over
/// smoothness, one item at a time, rather than nothing ever. An allowance of
/// nought means no limit, which is what a frame had before this existed.
final class FrameWorkBudget {
  FrameWorkBudget({this.microseconds = 0, int Function()? clock})
    : _clock = clock ?? _stopwatchClock();

  /// The allowance, in microseconds; nought for none.
  final int microseconds;

  final int Function() _clock;

  int _spent = 0;
  int _items = 0;
  int _deferred = 0;

  /// What a piece of work has been costing, in microseconds: an average that
  /// leans on recent frames.
  double _average = 0.0;

  /// What a piece of work has been costing lately, in microseconds.
  double get averageCost => _average;

  /// What this frame has spent so far, in microseconds.
  int get spent => _spent;

  /// How many pieces of work ran this frame.
  int get items => _items;

  /// How many asked this frame and were told to wait.
  int get deferred => _deferred;

  /// What is left of this frame's allowance; unbounded with none.
  int get remaining =>
      microseconds <= 0 ? 1 << 62 : (microseconds - _spent).clamp(0, 1 << 62);

  /// Starts a frame: nothing spent, nothing deferred.
  void beginFrame() {
    _spent = 0;
    _items = 0;
    _deferred = 0;
  }

  /// Whether another piece of work may start now. Counts a refusal.
  bool allows() {
    if (microseconds <= 0 || _items == 0) return true;
    if (_spent + _average <= microseconds) return true;
    _deferred++;
    return false;
  }

  /// Records a piece of work that took [cost] microseconds.
  void charge(int cost) {
    final paid = cost < 0 ? 0 : cost;
    _spent += paid;
    _items++;
    _average = _average == 0.0 ? paid.toDouble() : _average * 0.8 + paid * 0.2;
  }

  /// This allowance's clock, in microseconds: for a piece of work whose
  /// cost is measured across code that cannot sit inside one closure handed
  /// to [spend], and is then [charge]d the difference.
  int now() => _clock();

  /// Runs [work] if [allows] says so, charging what it took; false when it
  /// did not run.
  bool spend(void Function() work) {
    if (!allows()) return false;
    final start = _clock();
    work();
    charge(_clock() - start);
    return true;
  }

  static int Function() _stopwatchClock() {
    final watch = Stopwatch()..start();
    return () => watch.elapsedMicroseconds;
  }
}
