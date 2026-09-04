/// What is running on somebody, and for how much longer.
///
///     dart test test/powers_test.dart
///
/// Bookkeeping every genre wants and one of them had written: a platformer's
/// shield, a racer's boost and a crypt's berserk are the same name and the same
/// countdown. What a power *does* is the game's; this only counts.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

void main() {
  test('nothing is running to begin with', () {
    final powers = Powers();

    expect(powers.remaining, isEmpty);
    expect(powers.has('shield'), isFalse);
    expect(powers.remainingOf('shield'), 0.0);
  });

  test('a power refreshes rather than stacking', () {
    // A player who hoards four of them gets thirty seconds and not two
    // minutes, which is the difference between a power-up and a savings
    // account.
    final powers = Powers()
      ..empower('shield', 30.0)
      ..empower('shield', 10.0);

    expect(powers.remainingOf('shield'), 30.0);

    powers.empower('shield', 45.0);
    expect(powers.remainingOf('shield'), 45.0);
  });

  test('and a power of no length starts nothing', () {
    final powers = Powers()..empower('shield', 0.0);

    expect(powers.has('shield'), isFalse);
  });

  test('counting down ends it exactly once', () {
    // The moment a player notices, and the one a countdown on a HUD cannot
    // report: the number is nought on the frame it ends and on every frame
    // after it.
    final powers = Powers()..empower('shield', 0.05);

    // Counted across steps rather than asserted on one, because three steps
    // of a sixtieth leave a floating-point crumb of the fiftieth and the end
    // lands on the fourth. Which step it is does not matter; that there is
    // exactly one does.
    var reports = 0;
    for (var i = 0; i < 10; i++) {
      reports += powers.step(1.0 / 60.0).length;
    }

    expect(reports, 1);
    expect(powers.has('shield'), isFalse);
  });

  test('and two ending on one step are both reported', () {
    final powers = Powers()
      ..empower('shield', 0.01)
      ..empower('wings', 0.01);

    expect(powers.step(1.0).toSet(), <String>{'shield', 'wings'});
  });

  test('a round trip keeps what is left and drops what is not', () {
    final powers = Powers()
      ..empower('shield', 12.0)
      ..empower('wings', 3.0);
    final saved = powers.save();

    final loaded = Powers()..restore(saved);

    expect(loaded.remainingOf('shield'), 12.0);
    expect(loaded.remainingOf('wings'), 3.0);

    // And a document holding something finished does not start it again.
    final stale = Powers()..restore(<String, Object?>{'shield': 0.0});
    expect(stale.has('shield'), isFalse);
  });

  test('revoking ends one now, whatever was left', () {
    final powers = Powers()..empower('shield', 30.0);

    powers.revoke('shield');

    expect(powers.has('shield'), isFalse);
    expect(powers.step(1.0), isEmpty, reason: 'it ended twice');
  });
}
