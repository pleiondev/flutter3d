/// The four axes, and a fifth setting a game makes up.
///
///     dart test test/difficulty_test.dart
///
/// The type is here rather than in a genre because every genre was asking the
/// same four questions of the same idea. What each genre *does* with them is
/// checked where it does it — the shooter scales what the player deals and
/// takes, the platformer scales what the runner is hurt by.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

void main() {
  test('normal changes nothing, which is what every number was tuned at', () {
    expect(Difficulty.normal.damageTaken, 1.0);
    expect(Difficulty.normal.damageDealt, 1.0);
    expect(Difficulty.normal.opponentReaction, 1.0);
    expect(Difficulty.normal.assistance, 0.0);
  });

  test('reaction is a duration, so the harder settings have less of it', () {
    // The sign everybody gets wrong, and the reason the field is named for
    // what it scales rather than for what it means.
    expect(Difficulty.gentle.opponentReaction, greaterThan(1.0));
    expect(Difficulty.hard.opponentReaction, lessThan(1.0));
    expect(
      Difficulty.punishing.opponentReaction,
      lessThan(Difficulty.hard.opponentReaction),
    );
  });

  test('and the four are ordered on what the player takes', () {
    final taken = Difficulty.offered
        .map((Difficulty d) => d.damageTaken)
        .toList();
    expect(taken, orderedEquals(<double>[...taken]..sort()));
  });

  group('a setting a game makes up', () {
    // The point of the value class. A game with "nightmare", or a slider a
    // player drags, writes one; as an enum it could not, and adding a value
    // would have broken every switch a published game had.

    test('is a difficulty like any other', () {
      const nightmare = Difficulty('nightmare', damageTaken: 4.0);

      expect(nightmare.name, 'nightmare');
      expect(nightmare.damageTaken, 4.0);
      // Unnamed axes keep the tuned value rather than becoming zero.
      expect(nightmare.damageDealt, 1.0);
    });

    test('and can be built at run time from what a player chose', () {
      // A slider, which is the shape a settings screen actually has and the
      // one a fixed list of four cannot express at all.
      Difficulty fromSlider(double hardness) => Difficulty(
        'custom',
        damageTaken: 1.0 + hardness,
        opponentReaction: 1.0 - hardness * 0.5,
      );

      expect(fromSlider(0.0), Difficulty('custom'));
      expect(fromSlider(1.0).damageTaken, 2.0);
      expect(fromSlider(1.0).opponentReaction, 0.5);
    });

    test('and two of the same name are the same difficulty', () {
      expect(const Difficulty('nightmare'), const Difficulty('nightmare'));
      expect(
        <Difficulty, int>{const Difficulty('nightmare'): 1}[const Difficulty(
          'nightmare',
        )],
        1,
      );
    });
  });

  group('what the numbers refuse', () {
    test('damage that heals', () {
      expect(() => Difficulty('x', damageTaken: -1.0), throwsA(anything));
    });

    test('an opponent that never reacts', () {
      expect(() => Difficulty('x', opponentReaction: 0.0), throwsA(anything));
    });

    test('more help than there is', () {
      expect(() => Difficulty('x', assistance: 1.5), throwsA(anything));
    });
  });
}
