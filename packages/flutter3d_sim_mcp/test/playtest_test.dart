/// `ai-01`: many independent playthroughs of the real crypt, in real
/// isolates, reduced to a heatmap.
///
///     flutter test test/playtest_test.dart
library;

import 'package:flutter3d_game_shooter/staging.dart';
import 'package:flutter3d_sim_mcp/flutter3d_sim_mcp.dart';
import 'package:flutter_test/flutter_test.dart';

const String _crypt =
    '../../apps/flutter3d_demo_dungeon/assets/levels/crypt.json';

void main() {
  test('eight playthroughs each reach an outcome, and the heatmap accounts '
      'for every one of them', () async {
    final runs = await const Playtest(
      game: ShooterHeadlessGame(),
      maxSteps: 600,
      sampleEvery: 30,
    ).run(_crypt, 8);

    expect(runs, hasLength(8));
    expect(runs.map((r) => r.seed).toSet(), <int>{0, 1, 2, 3, 4, 5, 6, 7});
    for (final run in runs) {
      expect(run.steps, greaterThan(0));
      expect(run.positions, isNotEmpty);
    }

    final heatmap = Playtest.heatmap(runs, cellSize: 2.0);
    final outcomes = heatmap['outcomes']! as Map<String, int>;
    expect(
      outcomes.values.fold<int>(0, (a, b) => a + b),
      8,
      reason: 'every run should be counted under exactly one outcome',
    );
    expect((heatmap['cells']! as List<Object?>), isNotEmpty);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('the same seed plays the same run twice', () async {
    const playtest = Playtest(
      game: ShooterHeadlessGame(),
      maxSteps: 300,
      sampleEvery: 20,
    );
    final first = await playtest.run(_crypt, 1);
    final second = await playtest.run(_crypt, 1);

    expect(second.single.steps, first.single.steps);
    expect(second.single.outcome, first.single.outcome);
    expect(second.single.positions, first.single.positions);
  });

  test('a policy that never learns eventually gets marked stuck, not just '
      'timed out', () async {
    // A long cap and a short patience, on a level with dead ends a random
    // walk finds often enough in a handful of tries — this is the honest
    // way to prove `PlaytestOutcome.stuck` fires at all, rather than
    // asserting it on one specific seed that could stop being true the
    // day the crypt's own geometry changes.
    final runs = await const Playtest(
      game: ShooterHeadlessGame(),
      maxSteps: 1800,
      stuckAfter: 120,
      stuckStride: 0.5,
    ).run(_crypt, 6);
    expect(
      runs.map((r) => r.outcome),
      anyElement(PlaytestOutcome.stuck),
      reason:
          'none of six tries got stuck — stuckAfter/stuckStride may be '
          'miscalibrated for this level, or the detector may not be firing '
          'at all',
    );
  }, timeout: const Timeout(Duration(seconds: 60)));
}
