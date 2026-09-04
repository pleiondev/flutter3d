/// Points, and the run of them a player is holding.
///
///     dart test test/scoring_test.dart
///
/// What every genre counted and none of them scored. A Tally answers "how
/// many"; this answers what those were worth and whether they came close
/// enough together to be worth more.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

void main() {
  test('the first thing scored is worth what it is worth', () {
    final scoring = Scoring();

    expect(scoring.multiplier, 1.0);
    expect(scoring.score(100.0), 100.0);
    expect(scoring.total, 100.0);
  });

  test('and the second is worth more, because a run has started', () {
    final scoring = Scoring(step: 0.5)..score(100.0);

    expect(scoring.multiplier, 1.5);
    expect(scoring.score(100.0), 150.0);
    expect(scoring.total, 250.0);
    expect(scoring.chainLength, 2);
  });

  test('the multiplier stops at the ceiling', () {
    // A scoring system without one is a system where the last minute of a long
    // run is worth more than the whole of a short one, and nobody can read a
    // number like that.
    final scoring = Scoring(step: 1.0, ceiling: 3.0);
    for (var i = 0; i < 20; i++) {
      scoring.score(1.0);
    }

    expect(scoring.multiplier, 3.0);
  });

  test('a run ends when the window passes with nothing in it', () {
    // A combo is a clock, not a counter: counting to five and then waiting for
    // ever is a chain a player cannot lose, and losing it is the tension.
    final scoring = Scoring(window: 1.0)..score(100.0);

    expect(scoring.advance(0.5), isNull);
    expect(scoring.isRunning, isTrue);

    final ended = scoring.advance(0.6);

    expect(ended, 100.0);
    expect(scoring.isRunning, isFalse);
    expect(scoring.chain, 0.0);
    expect(scoring.total, 100.0, reason: 'the run was taken back');
  });

  test('and it is reported exactly once', () {
    final scoring = Scoring(window: 1.0)..score(10.0);

    expect(scoring.advance(2.0), 10.0);
    expect(scoring.advance(2.0), isNull);
  });

  test('scoring again inside the window keeps the run alive', () {
    final scoring = Scoring(window: 1.0)..score(10.0);

    scoring.advance(0.9);
    scoring.score(10.0);

    expect(scoring.advance(0.9), isNull, reason: 'the clock did not reset');
    expect(scoring.chainLength, 2);
  });

  test('breaking a run ends it now, for a reason of the game own', () {
    // A death, a lap, a room cleared — rather than the clock running out.
    final scoring = Scoring(window: 30.0)..score(40.0);

    expect(scoring.breakChain(), 40.0);
    expect(scoring.isRunning, isFalse);
    expect(scoring.breakChain(), isNull, reason: 'it broke twice');
  });

  test('the best run of a session is kept', () {
    final scoring = Scoring(window: 1.0)
      ..score(10.0)
      ..advance(2.0)
      ..score(50.0)
      ..advance(2.0)
      ..score(20.0)
      ..advance(2.0);

    expect(scoring.bestChain, 50.0);
    expect(scoring.total, 80.0);
  });

  test('and nothing is scored for nothing', () {
    final scoring = Scoring();

    expect(scoring.score(0.0), 0.0);
    expect(scoring.isRunning, isFalse, reason: 'a run started on nothing');
  });

  test('a round trip keeps the run as well as the total', () {
    final scoring = Scoring(window: 5.0)
      ..score(10.0)
      ..score(10.0);
    final saved = scoring.save();

    final loaded = Scoring(window: 5.0)..restore(saved);

    expect(loaded.total, scoring.total);
    expect(loaded.chain, scoring.chain);
    expect(loaded.chainLength, 2);
    expect(loaded.isRunning, isTrue);
  });
}
