/// What a rollback costs and what it lost: the time each step run again
/// took, and the corrections that came too late, counted once each.
///
///     dart test test/rollback_stats_test.dart
library;

import 'package:flutter3d_net/flutter3d_net.dart';
import 'package:test/test.dart';

/// Two machines adding up each other's hands, over a wire [delaySteps]
/// ticks long, for [steps] steps. [hands] is what slot [slot] presses on a
/// step; [onStep] hears every step run on machine nought, again or not.
({RollbackSession<int> first, RollbackSession<int> second}) _play({
  required int delaySteps,
  required int steps,
  required Map<String, Object?> Function(int slot, int step) hands,
  int maxRollbackFrames = 8,
  Duration Function()? elapsed,
  void Function(RollbackSession<int> session)? onStep,
}) {
  final LoopbackPair(:first, :second) = LoopbackWire.pair(
    delaySteps: delaySteps,
  );
  final sums = <int>[0, 0];
  late final RollbackSession<int> a;
  late final RollbackSession<int> b;
  RollbackSession<int> session(int slot) => RollbackSession<int>(
    wire: slot == 0 ? first : second,
    localSlot: slot,
    maxRollbackFrames: maxRollbackFrames,
    captureLocalFrame: () => hands(slot, slot == 0 ? a.step : b.step),
    applyAndStep: (step) {
      sums[slot] += step.frames.values.fold<int>(
        0,
        (sum, frame) => sum + ((frame['move'] as int?) ?? 0),
      );
      if (slot == 0) onStep?.call(a);
    },
    save: () => sums[slot],
    restore: (saved) => sums[slot] = saved,
    elapsed: slot == 0 ? elapsed : null,
  );
  a = session(0);
  b = session(1);
  for (var i = 0; i < steps; i++) {
    a.advance();
    first.tick();
    b.advance();
    second.tick();
  }
  return (first: a, second: b);
}

void main() {
  test('nothing run again, nothing timed', () {
    final played = _play(
      delaySteps: 0,
      steps: 50,
      hands: (slot, step) => <String, Object?>{'move': slot + 1},
    );
    final stats = played.first.stats;
    expect(stats.steps, 50);
    expect(stats.rollbacks, 0);
    expect(stats.stepsRerun, 0);
    expect(stats.resimulationP50, Duration.zero);
    expect(stats.resimulationP99, Duration.zero);
    expect(stats.resimulationMax, Duration.zero);
    expect(stats.droppedCorrectionShare, 0.0);
  });

  test('each step run again is timed, and the stats give its median, its '
      '99th percentile and its worst', () {
    var now = Duration.zero;
    final charged = <int>[];
    final played = _play(
      delaySteps: 4,
      steps: 300,
      // A hand that changes every step, so every guess is wrong.
      hands: (slot, step) => <String, Object?>{'move': (step * 7 + slot) % 5},
      elapsed: () => now,
      onStep: (session) {
        if (!session.isResimulating) {
          // A step run once costs time too, and must not be counted.
          now += const Duration(milliseconds: 3);
          return;
        }
        final cost = 100 + (charged.length * 37) % 900;
        charged.add(cost);
        now += Duration(microseconds: cost);
      },
    );
    final stats = played.first.stats;
    // Mutation: time nothing, or time the steps run once as well.
    expect(stats.stepsRerun, charged.length);
    expect(stats.rollbacks, greaterThan(0));
    expect(charged, isNotEmpty);
    final sorted = charged.toList()..sort();
    int nearestRank(int percent) =>
        sorted[(percent * sorted.length + 99) ~/ 100 - 1];
    expect(stats.resimulationP50.inMicroseconds, nearestRank(50));
    expect(stats.resimulationP99.inMicroseconds, nearestRank(99));
    expect(stats.resimulationMax.inMicroseconds, sorted.last);
  });

  test('a step longer than the histogram reads as the worst', () {
    var now = Duration.zero;
    final played = _play(
      delaySteps: 4,
      steps: 60,
      hands: (slot, step) => <String, Object?>{'move': step % 3},
      elapsed: () => now,
      onStep: (session) {
        if (session.isResimulating) now += const Duration(milliseconds: 80);
      },
    );
    final stats = played.first.stats;
    expect(stats.resimulationP50, const Duration(milliseconds: 80));
    expect(stats.resimulationMax, const Duration(milliseconds: 80));
  });

  test('a late copy of a frame already had is no dropped correction', () {
    // A wire slower than the window, and hands that never change from the
    // first step on: empty, as a slot not heard from yet is guessed to be.
    // Every step settles on a guess, and every guess is right.
    final played = _play(
      delaySteps: 12,
      steps: 200,
      hands: (slot, step) => const <String, Object?>{},
    );
    final stats = played.first.stats;
    expect(stats.settledOnGuess, greaterThan(0));
    // Mutation: count every copy that comes past the window, as before —
    // the eight copies redundancy sends of each frame count eight times
    // over, on a match that lost nothing.
    expect(stats.droppedCorrections, 0);
    expect(stats.droppedCorrectionShare, 0.0);
  });

  test('on a wire slower than the window, the guess is still the latest '
      'word', () {
    final played = _play(
      delaySteps: 12,
      steps: 200,
      hands: (slot, step) => <String, Object?>{'move': 1},
    );
    // Only the steps before the first frame came run on the empty hand and
    // lose their correction: about the wire's twelve and the delay's two.
    // Mutation: learn nothing from a frame past the window, and every step
    // is guessed empty and lost — 188 of them.
    expect(played.first.stats.droppedCorrections, lessThanOrEqualTo(14));
  });

  test('a frame that contradicts the guess its step settled on is a '
      'dropped correction, once', () {
    final played = _play(
      delaySteps: 12,
      steps: 200,
      hands: (slot, step) => <String, Object?>{'move': (step ~/ 3) % 4},
    );
    final stats = played.first.stats;
    expect(stats.droppedCorrections, greaterThan(0));
    // Once a step, however many copies of its frame come.
    expect(stats.droppedCorrections, lessThanOrEqualTo(stats.settledOnGuess));
    expect(
      stats.droppedCorrectionShare,
      stats.droppedCorrections / stats.steps,
    );
    expect(played.first.droppedCorrections, stats.droppedCorrections);
  });

  test('a machine\'s stats read back from its line of the report', () {
    const stats = RollbackStats(
      steps: 36000,
      rollbacks: 812,
      stepsRerun: 2950,
      settledOnGuess: 14,
      droppedCorrections: 3,
      droppedEarly: 0,
      resimulationP50: Duration(microseconds: 410),
      resimulationP99: Duration(microseconds: 2240),
      resimulationMax: Duration(microseconds: 9050),
    );
    final back = RollbackStats.fromJson(stats.toJson());
    expect(back.toJson(), stats.toJson());
    expect(back.droppedCorrectionShare, closeTo(3 / 36000, 1e-12));
  });
}
