/// `ls-i-00`'s own acceptance, the "what if" half: "changing the value
/// creates a visible branch rather than overwriting history." Checked
/// directly against `DataSourceTrace.branchAt` (`flutter3d_sim`) applied
/// for the first time to the actual twin content this app ships, the same
/// way `flutter3d_lab`'s own `PendulumLabRun.branchAt` already proved the
/// identical claim for a pendulum's length.
///
///     dart test test/spindle_temp_run_test.dart
library;

import 'package:flutter3d_twin/flutter3d_twin.dart';
import 'package:test/test.dart';

void main() {
  test('a run with no branch reads exactly spindleTempAt at every step', () {
    final run = SpindleTempRun(steps: 50);
    expect(run.readings.valueAt(1)!['value'], spindleTempAt(1));
    expect(run.readings.valueAt(50)!['value'], spindleTempAt(50));
  });

  test(
    "ls-i-00's own acceptance: a branch leaves the original run untouched",
    () {
      final run = SpindleTempRun(steps: 100);
      final before = run.readings.toJson();

      run.branchAt(50, 100, (step) => 999.0);

      expect(run.readings.toJson(), before);
    },
  );

  test('the branch agrees with the original up to the branch point, then '
      'reads the substituted value instead', () {
    final run = SpindleTempRun(steps: 100);
    final branch = run.branchAt(50, 100, (step) => 999.0);

    // Up to and including the branch point, the branch is the original's
    // own history — not recomputed, not a different sampler run.
    expect(branch.readings.valueAt(50), run.readings.valueAt(50));
    expect(branch.readings.valueAt(1), run.readings.valueAt(1));

    // From the very next step on, the "what if" value replaces the
    // sensor's own — a visible branch, not the original overwritten.
    expect(branch.readings.valueAt(51)!['value'], 999.0);
    expect(branch.readings.valueAt(100)!['value'], 999.0);

    // And the original, unbranched, still reads the real sensor at that
    // same step — the two histories genuinely diverged.
    expect(run.readings.valueAt(100)!['value'], isNot(999.0));
  });

  test('a branch can itself be branched again, without disturbing either '
      'earlier run', () {
    final run = SpindleTempRun(steps: 100);
    final branchA = run.branchAt(30, 100, (step) => 10.0);
    final branchB = branchA.branchAt(60, 100, (step) => 20.0);

    // Up to and including the branch point itself, a branch is the
    // history it branched *from* — the "what if" only replaces what comes
    // strictly after — so step 30 (branchA's own branch point) is still
    // the real sensor reading in both branchA and branchB.
    expect(branchB.readings.valueAt(30)!['value'], spindleTempAt(30));
    expect(branchB.readings.valueAt(60)!['value'], 10.0);
    expect(branchB.readings.valueAt(61)!['value'], 20.0);

    // Neither earlier run moved.
    expect(branchA.readings.valueAt(61)!['value'], 10.0);
    expect(run.readings.valueAt(61)!['value'], spindleTempAt(61));
  });
}
