/// `net-00`: what a rollback costs on the game that ships, not on a toy.
///
///     flutter test test/rollback_cost_test.dart
///
/// See `apps/flutter3d_demo_dungeon/test/rollback_cost_test.dart` for why
/// this prints a number rather than asserting a fixed threshold.
///
/// Measures `Match`, not `MatchSimulation` alone — the same object
/// `playthrough_test.dart` plays to an ending — since a bot's own head is
/// part of what a rollback has to restore, and `Match.save`/`restore` is
/// where that and the simulation are kept in the same document.
library;

import 'dart:io';

import 'package:flutter3d_demo_strategy/src/command.dart';
import 'package:flutter3d_demo_strategy/src/level_document.dart';
import 'package:flutter3d_demo_strategy/src/run.dart';
import 'package:flutter3d_demo_strategy/src/staging.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';

StrategyMap _map() =>
    StrategyMap.parse(File('assets/levels/map_a.json').readAsStringSync());

void main() {
  test('restore + k steps of the shipped map, k = 1..10', () {
    final StrategyMap map = _map();
    final StrategyStart start = openMatch(map);
    final command = CommandPost(simulation: start.simulation, side: viewerSide);

    // Three hundred ticks of an ordinary opening — restock every step, the
    // way the screen does on the player's behalf — before measuring, so the
    // snapshot restored below is mid-match rather than the empty start.
    for (var step = 0; step < 300; step++) {
      if (start.match.standing.isOver) break;
      command.restock();
      start.match.step(strategyStep);
    }
    final Snapshot snapshot = start.match.save();

    void stepOnce() {
      command.restock();
      start.match.step(strategyStep);
    }

    start.match.restore(snapshot);
    for (var i = 0; i < 10; i++) {
      stepOnce();
    }

    final results = <int, double>{};
    for (var k = 1; k <= 10; k++) {
      const trials = 20;
      final watch = Stopwatch();
      for (var trial = 0; trial < trials; trial++) {
        start.match.restore(snapshot);
        watch.start();
        for (var step = 0; step < k; step++) {
          stepOnce();
        }
        watch.stop();
      }
      results[k] = watch.elapsedMicroseconds / trials / 1000.0;
    }

    // ignore: avoid_print
    print(
      'net-00 strategy (map_a): ${[
        for (final k in results.keys) 'k=$k ${results[k]!.toStringAsFixed(4)}ms',
      ].join(', ')}',
    );

    expect(results[8], isNotNull);
    expect(results[10]!, greaterThanOrEqualTo(results[1]!));
  });
}
