/// What a run came to, counted off the events it produced.
///
///     dart test test/run_stats_test.dart
///
/// The results screen every game wrote by hand: three applications counted
/// kills, coins and laps, each in its own field, each cleared in its own place,
/// each wrong in its own way. All three were reading the same thing — how many
/// of a kind of moment happened.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

final class _Coin extends GameEvent {
  const _Coin();

  @override
  String get name => 'coin';
}

final class _Death extends GameEvent {
  const _Death();

  @override
  String get name => 'death';
}

void main() {
  test('counts nothing until a game says what to count', () {
    // A template that knew ShotFired would be a template that knew about
    // weapons.
    final stats = RunStats();

    stats.advance(1.0, <GameEvent>[const _Coin(), const _Death()]);

    expect(stats.tally.counts, isEmpty);
    expect(stats.elapsed, 1.0);
  });

  test('and counts what it was told to, by name', () {
    final stats = RunStats()
      ..count('coins', (GameEvent e) => e is _Coin)
      ..count('deaths', (GameEvent e) => e is _Death);

    stats.advance(1.0 / 60.0, <GameEvent>[
      const _Coin(),
      const _Coin(),
      const _Death(),
    ]);

    expect(stats.tally['coins'], 2);
    expect(stats.tally['deaths'], 1);
  });

  test('one event may be counted by two counters', () {
    // "Things taken" and "coins" are both true of a coin, and a game that
    // wanted both had to write the second by hand.
    final stats = RunStats()
      ..count('coins', (GameEvent e) => e is _Coin)
      ..count('taken', (GameEvent e) => e is _Coin);

    stats.advance(0.0, <GameEvent>[const _Coin()]);

    expect(stats.tally['coins'], 1);
    expect(stats.tally['taken'], 1);
  });

  test('the clock is the simulation own', () {
    // A run timed against the wall is a run whose record depends on the
    // machine it was set on.
    final stats = RunStats();
    for (var i = 0; i < 120; i++) {
      stats.advance(1.0 / 60.0, const <GameEvent>[]);
    }

    expect(stats.elapsed, closeTo(2.0, 1e-9));
  });

  test('clearing forgets the run but keeps the counters', () {
    // Clearing the counters would be a results screen that stops counting
    // after the first restart.
    final stats = RunStats()..count('coins', (GameEvent e) => e is _Coin);
    stats.advance(1.0, <GameEvent>[const _Coin()]);

    stats.clear();
    expect(stats.tally['coins'], 0);
    expect(stats.elapsed, 0.0);

    stats.advance(1.0, <GameEvent>[const _Coin()]);
    expect(stats.tally['coins'], 1, reason: 'it stopped counting');
  });

  test('and a round trip keeps both numbers', () {
    final stats = RunStats()..count('coins', (GameEvent e) => e is _Coin);
    stats.advance(3.0, <GameEvent>[const _Coin(), const _Coin()]);

    final loaded = RunStats()..restore(stats.save());

    expect(loaded.tally['coins'], 2);
    expect(loaded.elapsed, 3.0);
  });
}
