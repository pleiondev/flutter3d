/// Every verb the crypt's simulation reads has something to press.
///
///     flutter test test/shooter_keys_test.dart
///
/// The engine's default table knows about walking, jumping, sprinting and
/// using; a shooter's own two are `ShooterActions.fire` and
/// `ShooterActions.crouch`, and putting them in is the game's job. Only one of
/// them had ever been put in, which is what this exists to stop happening
/// again — and the way it is asked is from the simulation's side: whatever
/// `GameSimulation.step` reads has to be reachable.
library;

import 'package:flutter3d_demo_dungeon/src/shooter_keys.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter_test/flutter_test.dart';

Bindings _shipped() =>
    addShooterKeysTo(PadInput.addDefaultsTo(DesktopInput.defaultBindings()));

void main() {
  test('the crouch the body has is a key the player can press', () {
    // **The verb nothing could reach.** `GameSimulation.step` runs
    // `player.crouch(held: input.held(ShooterActions.crouch))` every step, and
    // no table in this repository bound `crouch` to anything: not the shared
    // defaults, which are the engine's and do not know a shooter's verbs, and
    // not this game, which added only `fire`. The body shrank, walked slower
    // and refused to stand under a lintel for nobody.
    //
    // Mutation: drop the two `crouch` binds from `addShooterKeysTo` and this
    // fails on both devices.
    final bindings = _shipped();

    expect(bindings.sourcesFor(ShooterActions.crouch), isNotEmpty);
    expect(
      bindings
          .sourcesFor(ShooterActions.crouch)
          .where((InputSource s) => s.id.startsWith(InputSource.padPrefix)),
      isNotEmpty,
      reason: 'a controller cannot crouch',
    );
    expect(
      bindings
          .sourcesFor(ShooterActions.crouch)
          .where((InputSource s) => !s.id.startsWith(InputSource.padPrefix)),
      isNotEmpty,
      reason: 'a keyboard cannot crouch',
    );
  });

  test('and firing still is', () {
    // The one that was already here, kept honest: the same function writes
    // both now, so a table that lost one would be a table that lost both.
    expect(_shipped().sourcesFor(ShooterActions.fire), isNotEmpty);
  });

  test('and nothing was taken away to make room', () {
    // Crouch went on C. The check that matters is that C was free: this
    // function binds over whatever was there, and quietly stealing a key from
    // walking would be a worse bug than the one it fixes.
    final before = DesktopInput.defaultBindings();
    final after = _shipped();

    for (final source in before.sources) {
      expect(
        after[source],
        before[source],
        reason:
            '$source used to do ${before[source]} and now does '
            '${after[source]}',
      );
    }
  });
}
