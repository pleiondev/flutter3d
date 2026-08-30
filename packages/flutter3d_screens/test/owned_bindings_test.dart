/// The table the game reads and the table the file saves are the same table.
///
///     flutter test test/owned_bindings_test.dart
///
/// **A shipped bug in both games**, and one that could only ever happen to a
/// player who had never changed a setting — which is why it lasted. See
/// `owned_bindings.dart` for the two lines that caused it.
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_screens/flutter3d_screens.dart';
import 'package:flutter_test/flutter_test.dart';

const GameAction _jump = GameAction('jump');
const GameAction _dash = GameAction('dash');

Bindings _defaults() => Bindings()
  ..bind(InputSource.key(32), _jump)
  ..bind(InputSource.key(81), _dash);

void main() {
  test('a first launch fills the config, and that is what gets saved', () {
    // The failing case. Before this, the empty branch handed the keyboard a
    // fresh table, the rebinding screen edited *that*, and the save wrote the
    // config — so the rebind worked until the player quit.
    final config = GameConfig();

    final table = ownedBindings(config, _defaults);

    expect(
      identical(table, config.bindings),
      isTrue,
      reason: 'the game is reading a table the file will not write',
    );
    expect(
      config.toJson()['bindings'],
      isNotEmpty,
      reason: 'the defaults never reached the document',
    );
  });

  test('and a rebind made on that first launch survives the save', () {
    // The end-to-end statement of the bug, through the document rather than
    // through object identity: bind something, serialise the config, read it
    // back. Before the fix the new key was simply not in there.
    final config = GameConfig();
    final table = ownedBindings(config, _defaults);

    table
      ..clearAction(_dash)
      ..bind(InputSource.key(70), _dash);

    final saved = GameConfig.fromJson(config.toJson());
    expect(saved.bindings[InputSource.key(70)], _dash);
    expect(
      saved.bindings[InputSource.key(81)],
      isNull,
      reason: 'the old key still works, so nothing was moved',
    );
  });

  test('a later launch keeps what the player chose, defaults and all', () {
    // The case that always worked, kept so the fix cannot be "always overwrite".
    // Mutation: drop the `length == 0` guard. Every launch resets the controls,
    // which is the opposite failure and a worse one.
    final config = GameConfig(
      bindings: Bindings()..bind(InputSource.key(70), _dash),
    );

    final table = ownedBindings(config, _defaults);

    expect(table[InputSource.key(70)], _dash);
    expect(
      table[InputSource.key(81)],
      isNull,
      reason: 'the defaults were put back over the player',
    );
  });

  test('and the table handed back is the one the config holds, either way', () {
    // Both branches, one promise. A caller that gets a different object in one
    // of the two cases has the original bug back in a new shape.
    for (final config in <GameConfig>[
      GameConfig(),
      GameConfig(bindings: Bindings()..bind(InputSource.key(70), _dash)),
    ]) {
      expect(
        identical(ownedBindings(config, _defaults), config.bindings),
        isTrue,
      );
    }
  });
}
