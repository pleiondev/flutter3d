/// The allowance for work that can wait is never overrun on a scripted
/// burst, and a queue still drains when nothing fits — `N3`.
///
///     dart test test/engine/frame_work_budget_test.dart
library;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:test/test.dart';

/// A clock the test moves by hand, in microseconds.
final class _Clock {
  int now = 0;
  int read() => now;
}

void main() {
  test('a burst of equal pieces stops short of the allowance', () {
    final clock = _Clock();
    final budget = FrameWorkBudget(microseconds: 1000, clock: clock.read);
    for (var frame = 0; frame < 5; frame++) {
      budget.beginFrame();
      var ran = 0;
      for (var i = 0; i < 20; i++) {
        final did = budget.spend(() => clock.now += 300);
        if (!did) break;
        ran++;
      }
      // Mutation: allow while spent < allowance. The fourth piece runs and
      // the frame spends 1200.
      expect(budget.spent, lessThanOrEqualTo(1000), reason: 'frame $frame');
      expect(ran, 3);
      expect(budget.deferred, 1);
    }
  });

  test('a piece bigger than the allowance still runs, one a frame', () {
    final clock = _Clock();
    final budget = FrameWorkBudget(microseconds: 100, clock: clock.read)
      ..beginFrame();
    expect(budget.spend(() => clock.now += 5000), isTrue);
    expect(budget.spend(() => clock.now += 5000), isFalse);
    budget.beginFrame();
    expect(budget.spend(() => clock.now += 5000), isTrue);
  });

  test('no allowance is no limit', () {
    final clock = _Clock();
    final budget = FrameWorkBudget(clock: clock.read)..beginFrame();
    for (var i = 0; i < 100; i++) {
      expect(budget.spend(() => clock.now += 1000), isTrue);
    }
    expect(budget.deferred, 0);
  });
}
