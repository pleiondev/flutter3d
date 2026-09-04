import 'dart:math' as math;

/// Points, and the run of them a player is holding.
///
/// **What every genre counted and none of them scored.** The crypt counts kills
/// and secrets, the platformer counts coins and deaths, the circuit counts laps
/// — all of that is a [Tally], which answers "how many" and stops there. A
/// score is the other question: what those were *worth*, and whether they came
/// close enough together to be worth more.
///
/// **A combo is a clock, not a counter.** Every game that scores a chain does
/// it this way and for the same reason: counting to five and then waiting for
/// ever is a chain a player cannot lose, and losing it is the entire tension. A
/// run here ends when [window] passes with nothing scored, which is a rule a
/// player can feel from the third one.
///
/// Nothing in this class decides what anything is worth. A genre passes the
/// value in, because a coin, a headshot and a clean sector are worth what the
/// game says and there is no shared answer.
final class Scoring {
  Scoring({this.window = 2.0, this.step = 0.5, this.ceiling = 8.0})
    : assert(window > 0.0, 'a chain with no window cannot be broken'),
      assert(step >= 0.0, 'a chain that pays less each time is not a chain'),
      assert(ceiling >= 1.0, 'a multiplier below one is a penalty');

  /// How long a run survives with nothing added to it, in seconds.
  final double window;

  /// How much the multiplier grows with each scoring event.
  final double step;

  /// The most the multiplier may reach.
  ///
  /// **A limit rather than an open climb**, because a scoring system without
  /// one is a scoring system where the last minute of a long run is worth more
  /// than the whole of a short one, and nobody can read a number like that.
  final double ceiling;

  /// Everything scored this run.
  double get total => _total;
  double _total = 0.0;

  /// What the run in hand is worth so far. Zero when nothing is running.
  double get chain => _chain;
  double _chain = 0.0;

  /// How many things this run is made of.
  int get chainLength => _chainLength;
  int _chainLength = 0;

  /// What the next thing scored is multiplied by.
  double get multiplier =>
      _chainLength == 0 ? 1.0 : math.min(ceiling, 1.0 + step * _chainLength);

  /// How long the run has left before it lapses.
  double get remaining => _remaining;
  double _remaining = 0.0;

  /// Whether a run is going.
  bool get isRunning => _chainLength > 0;

  /// The longest run of this session, by what it was worth.
  double get bestChain => _bestChain;
  double _bestChain = 0.0;

  /// Scores [value], multiplied by the run in hand, and extends the run.
  ///
  /// Returns what was actually added, which is what a game shows floating over
  /// the thing that was scored — and it is the multiplied number rather than
  /// the one passed in, because that is the one a player is being rewarded
  /// with.
  double score(double value) {
    if (value <= 0.0) return 0.0;
    final scored = value * multiplier;
    _total += scored;
    _chain += scored;
    _chainLength += 1;
    _remaining = window;
    return scored;
  }

  /// Counts the window down and ends the run if it lapses.
  ///
  /// Returns what the run was worth if it ended on this step, or null on every
  /// other step. A return rather than a flag, for the reason every per-step
  /// flag in this repository became an event: the end of a chain is a moment,
  /// and a chain worth nought afterwards cannot be told from one that never
  /// happened.
  double? advance(double dt) {
    if (_chainLength == 0 || dt <= 0.0) return null;
    _remaining -= dt;
    if (_remaining > 0.0) return null;

    final was = _chain;
    if (was > _bestChain) _bestChain = was;
    _chain = 0.0;
    _chainLength = 0;
    _remaining = 0.0;
    return was;
  }

  /// Ends the run now, whatever is left on the clock.
  ///
  /// For the moment a game decides a chain is over for a reason of its own — a
  /// death, a lap, a room cleared — rather than because the clock ran out.
  double? breakChain() {
    if (_chainLength == 0) return null;
    _remaining = 0.0;
    return advance(double.maxFinite);
  }

  /// Forgets everything, for a run starting over.
  void clear() {
    _total = 0.0;
    _chain = 0.0;
    _chainLength = 0;
    _remaining = 0.0;
    _bestChain = 0.0;
  }

  Map<String, Object?> save() => <String, Object?>{
    'total': _total,
    'chain': _chain,
    'length': _chainLength,
    'remaining': _remaining,
    'best': _bestChain,
  };

  void restore(Map<String, Object?> from) {
    _total = (from['total'] as num?)?.toDouble() ?? 0.0;
    _chain = (from['chain'] as num?)?.toDouble() ?? 0.0;
    _chainLength = (from['length'] as num?)?.toInt() ?? 0;
    _remaining = (from['remaining'] as num?)?.toDouble() ?? 0.0;
    _bestChain = (from['best'] as num?)?.toDouble() ?? 0.0;
  }
}
