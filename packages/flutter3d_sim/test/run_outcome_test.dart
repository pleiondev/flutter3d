/// The three words every game shares about how a run ended.
///
///     flutter test test/run_outcome_test.dart
///
/// Three genres grew three enums saying the same thing, and everything above
/// them — a save that must not be written for a finished run, a restart key, a
/// pause gate, a HUD — asked each one separately. This is the vocabulary they
/// answer in.
///
/// The mapping itself is tested in each genre package, because that is where it
/// lives. What is here is the part that belongs to nobody: that "over" is one
/// question and not three spellings of `!= playing`.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

void main() {
  test('a run that is being played is not over', () {
    expect(RunOutcome.playing.isOver, isFalse);
  });

  test('and both ways of ending are over', () {
    // The whole reason `isOver` exists rather than `!= playing` at each call
    // site: that is the same sentence written four times with one chance each
    // of being inverted, and the fourth one is written at midnight.
    expect(RunOutcome.lost.isOver, isTrue);
    expect(RunOutcome.won.isOver, isTrue);
  });

  test('and there are three of them, not four', () {
    // Deliberately no "ended, and I am not saying how". A screen cannot draw
    // that and a save cannot decide about it, and every caller that had one
    // grew a second flag beside it within a week.
    expect(RunOutcome.values, hasLength(3));
  });

  test('and losing and winning are told apart', () {
    // They are opposite outcomes that a game has to show differently — which is
    // why the platformer's own enum keeps `lost` and `finished` apart, and the
    // note there says exactly this.
    expect(RunOutcome.lost, isNot(RunOutcome.won));
  });
}
