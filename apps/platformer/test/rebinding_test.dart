/// Moving a control to somewhere the player can reach.
///
///     flutter test test/rebinding_test.dart
///
/// **The gap this closes was three years wide.** `Bindings` has always been a
/// table of source to action, it has always been saved and read back, and the
/// settings panel has always *listed* what was bound — and nothing anywhere
/// could change one. A player who cannot reach `Ctrl`, who plays one-handed, or
/// whose controller has a dead button had no way in.
///
/// The rules are here rather than in `main.dart` because `main.dart` is imported
/// by no test, and these are the parts that can be wrong.
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platformer/src/rebinding.dart';

const GameAction _dash = GameAction('dash');

Bindings _table() => Bindings(<InputSource, GameAction>{
      InputSource.key(32): GameAction.jump,
      InputSource.key(9): _dash,
      InputSource.pad('face.south'): GameAction.jump,
    });

void main() {
  test('nothing is captured until something is waiting', () {
    // The panel is a list most of the time, and a key pressed while it is a list
    // belongs to whatever else wanted it.
    final bindings = _table();
    final rebinding = Rebinding(bindings: bindings);

    expect(rebinding.capture(InputSource.key(65)), isFalse);
    expect(bindings[InputSource.key(65)], isNull);
  });

  test('a captured control replaces the old one, rather than joining it', () {
    // **The decision worth defending.** A player rebinding a control is nearly
    // always moving it off something they cannot use, and an "as well" that left
    // the old key working would leave them exactly where they started.
    final bindings = _table();
    final rebinding = Rebinding(bindings: bindings)..start(GameAction.jump);

    expect(rebinding.capture(InputSource.key(65)), isTrue);

    expect(bindings[InputSource.key(65)], GameAction.jump);
    expect(bindings[InputSource.key(32)], isNull, reason: 'space still jumps');
    expect(bindings[InputSource.pad('face.south')], isNull,
        reason: 'the pad still jumps, so half the rebinding did nothing');
  });

  test('and it is taken from whatever else had it', () {
    // Two actions on one key is a table where the last writer wins silently, and
    // a player who cannot see which won thinks the rebinding failed.
    final bindings = _table();
    Rebinding(bindings: bindings)
      ..start(GameAction.jump)
      ..capture(InputSource.key(9));

    expect(bindings[InputSource.key(9)], GameAction.jump);
    expect(bindings.sourcesFor(_dash), isEmpty);
  });

  test('and a pad button binds exactly as a key does', () {
    // One table, both halves, which is what makes a controller rebindable at all
    // — and `pad:face.east` is what lands in the saved file, not `B`.
    final bindings = _table();
    Rebinding(bindings: bindings)
      ..start(_dash)
      ..capture(InputSource.pad('face.east'));

    expect(bindings[InputSource.pad('face.east')], _dash);
    expect(Bindings.fromJson(bindings.toJson())[InputSource.pad('face.east')],
        _dash);
  });

  test('and cancelling leaves the table alone', () {
    // Escape, or closing the panel. A rebinding that half happened is worse than
    // one that did not.
    final bindings = _table();
    final rebinding = Rebinding(bindings: bindings)
      ..start(GameAction.jump)
      ..cancel();

    expect(rebinding.capture(InputSource.key(65)), isFalse);
    expect(bindings[InputSource.key(32)], GameAction.jump);
  });

  test('and only one thing waits at a time', () {
    final bindings = _table();
    final rebinding = Rebinding(bindings: bindings)
      ..start(GameAction.jump)
      ..start(_dash);

    rebinding.capture(InputSource.key(65));

    expect(bindings[InputSource.key(65)], _dash);
    expect(rebinding.waitingFor, isNull);
  });

  test('resetting puts back what shipped', () {
    // The way out of a rebinding that made the game unplayable, which is not
    // hypothetical: the fastest way to find that out is to bind walking to a key
    // you then cannot reach.
    final bindings = _table();
    final rebinding = Rebinding(bindings: bindings)
      ..start(GameAction.jump)
      ..capture(InputSource.key(65));

    rebinding.reset(_table());

    expect(bindings[InputSource.key(32)], GameAction.jump);
    expect(bindings[InputSource.key(65)], isNull);
    expect(bindings[InputSource.pad('face.south')], GameAction.jump);
  });
}
