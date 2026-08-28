import 'dart:math' as math;

/// Whether the machine is keeping up, and what it cost when it did not.
///
/// **`FixedStep.droppedSteps` was read by nobody.** The loop refuses to run
/// more than `maxStepsPerFrame` steps for one frame — it has to, or a long
/// frame asks for a longer one and the application hangs — and the simulated
/// time it will not run is thrown away and counted. Nothing read the count, so
/// a machine that could not keep up ran the game in **silent slow motion**, and
/// the run timer, which counts simulated seconds, quietly stopped agreeing with
/// the clock on the wall.
///
/// A class rather than two fields in the widget, for the reason `Soundtrack` is
/// one: a decision can be tested and an effect inside a `build` cannot.
///
/// **Any drop at all already means trouble.** Five steps of a sixtieth is 83
/// milliseconds, so nothing is dropped until a frame takes longer than that —
/// twelve frames a second. This is not a tuning warning; it is the game running
/// at a speed nobody chose.
final class Pace {
  Pace({this.window = 3.0, this.tolerance = 0.5})
    : assert(window > 0.0),
      assert(tolerance > 0.0);

  /// How long a stall keeps counting against the machine, as a time constant.
  final double window;

  /// How much lost time inside that window is worth telling the player about,
  /// in seconds.
  ///
  /// Not zero, because one hitch is not a slow machine — a garbage collection
  /// or a window being dragged between monitors drops a step and means nothing.
  /// Half a second of simulated time inside three is a game that is visibly
  /// running slowly.
  final double tolerance;

  int _seen = 0;
  double _recent = 0.0;
  double _lost = 0.0;

  /// Simulated time this run never ran, in seconds.
  ///
  /// Cumulative, and it is what makes the run timer honest: a run showing 9:12
  /// after four seconds were dropped took 9:16 of the player's life.
  double get lost => _lost;

  /// Whether the machine has been failing to keep up just now.
  bool get behind => _recent > tolerance;

  /// Takes the loop's running total and the length of the frame just drawn.
  ///
  /// The **total**, not a delta, because that is what [FixedStep] exposes and
  /// asking the caller to difference it is asking the caller to hold state this
  /// class is already holding.
  void note({
    required int dropped,
    required double dt,
    required double stepSeconds,
  }) {
    final fresh = dropped - _seen;
    _seen = dropped;
    final justLost = fresh > 0 ? fresh * stepSeconds : 0.0;
    _lost += justLost;
    _recent = _recent * math.exp(-dt / window) + justLost;
  }

  /// Forgets everything, keeping the loop's total so it is not counted twice.
  ///
  /// **Called when a level loads**, and that is not a way of hiding the number.
  /// Reading a level takes far longer than a frame and drops a second of
  /// simulated time every time, so a run that counted it would open with the
  /// warning lit on every machine, which is the same as having no warning.
  void reset(int dropped) {
    _seen = dropped;
    _recent = 0.0;
    _lost = 0.0;
  }
}
