/// A step takes no randomness and no clock except the ones it was handed.
///
///     flutter test test/determinism_test.dart
///
/// **SPEC §4.10 said this was already true and named the test as missing.** It
/// was not true. `ActorSystem` and `flutter3d_game_shooter`'s `Hitscan` both
/// defaulted to an unseeded `math.Random`, `apps/flutter3d_demo_dungeon` took both defaults,
/// and its `GameSimulation.random` was left null — so the shipped crypt rolled
/// dice nobody could write down and `save()` wrote none of them. Every part of
/// that passed review for as long as the rule lived in a document.
///
/// The rule is kept in three places, because no one of them can do the others'
/// work:
///
///   * **the scan**, `a step reaches for no clock and no loose dice` in
///     `tool/structure.dart`, which reads every simulation package before a
///     build. It fails on the *next* `Random()` or `DateTime.now()` somebody
///     writes, at the moment they write it, and names the file. It cannot tell
///     whether a simulation actually diverges.
///   * **the behavioural tests**, which live with each game because a step is a
///     game's — see `flutter3d_game_shooter/test/snapshot_test.dart` and its
///     siblings. They cannot say *where* a leak is.
///   * **this file**, which is about the one piece the other two rest on: a
///     generator whose state is a number you can write down. If [GameRandom]
///     does not come back the same, nothing above it can.
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the generator every step is required to take', () {
    test('gives the same sequence from the same seed', () {
      List<double> roll(GameRandom of) =>
          <double>[for (var i = 0; i < 16; i++) of.nextDouble()];

      expect(roll(GameRandom(7)), roll(GameRandom(7)));
      expect(roll(GameRandom(7)), isNot(roll(GameRandom(8))));
    });

    test('and writing its state down puts the sequence back', () {
      // This is the whole of why `math.Random` cannot be used: there is no
      // value to write down. A snapshot restores where the dice were or it
      // restores a world that agrees for one step and then drifts.
      final dice = GameRandom(3);
      for (var i = 0; i < 5; i++) {
        dice.nextDouble();
      }

      final written = dice.state;
      final after = <double>[for (var i = 0; i < 8; i++) dice.nextDouble()];

      // Mutation: leave `state` out of the snapshot, which is what the shooter
      // did whenever its caller passed no generator.
      final restored = GameRandom(999)..state = written;
      expect(
        <double>[for (var i = 0; i < 8; i++) restored.nextDouble()],
        after,
      );
    });
  });
}
