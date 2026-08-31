/// Rebinding is only worth having if it survives the process, so most of these
/// are about the file rather than about the table.
library;

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';

const GameAction _dash = GameAction('dash');

void main() {
  group('the table', () {
    test('two sources can drive one action', () {
      final bindings = Bindings()
        ..bind(InputSource.key(1), GameAction.moveForward)
        ..bind(InputSource.key(2), GameAction.moveForward);

      expect(bindings[InputSource.key(1)], GameAction.moveForward);
      expect(bindings[InputSource.key(2)], GameAction.moveForward);
      expect(bindings.sourcesFor(GameAction.moveForward), hasLength(2));
    });

    test('binding a source again replaces what it did', () {
      final bindings = Bindings()
        ..bind(InputSource.key(1), GameAction.jump)
        ..bind(InputSource.key(1), _dash);

      expect(bindings[InputSource.key(1)], _dash);
      expect(bindings.sourcesFor(GameAction.jump), isEmpty);
    });

    test('clearing an action frees every source pointing at it', () {
      // Mutation: have `clearAction` remove only the first match. The second
      // key goes on jumping, and a rebind screen that said "press a key for
      // jump" has quietly left the old one working too.
      final bindings = Bindings()
        ..bind(InputSource.key(1), GameAction.jump)
        ..bind(InputSource.key(2), GameAction.jump)
        ..clearAction(GameAction.jump);

      expect(bindings.sourcesFor(GameAction.jump), isEmpty);
      expect(bindings.length, 0);
    });
  });

  group('the file', () {
    test('a table round-trips through text unchanged', () {
      final saved = Bindings()
        ..bind(InputSource.key(107), GameAction.jump)
        ..bind(InputSource.pointer(0), _dash)
        ..bind(InputSource.pad('a'), GameAction.jump);

      final read = Bindings.fromJson(
        jsonDecode(jsonEncode(saved.toJson())) as Map<String, Object?>,
      );

      expect(read[InputSource.key(107)], GameAction.jump);
      expect(read[InputSource.pointer(0)], _dash);
      expect(read[InputSource.pad('a')], GameAction.jump);
      expect(read.length, saved.length);
    });

    test('an action this build has never heard of is kept', () {
      // Mutation: filter `fromJson` down to `GameAction.common`. The grapple
      // disappears, and a player who loads their config in a build where the
      // feature is temporarily off loses the binding permanently the next time
      // the game saves.
      final read = Bindings.fromJson(<String, Object?>{
        'grapple': <String>['key:71'],
      });

      expect(read[InputSource.key(71)], const GameAction('grapple'));
      expect(read.toJson()['grapple'], <String>['key:71']);
    });

    test('saving twice produces the same bytes', () {
      // Mutation: drop either `sort` in `toJson`. Map iteration order then
      // decides the file, and every save is a diff nobody can review.
      final bindings = Bindings()
        ..bind(InputSource.key(3), GameAction.jump)
        ..bind(InputSource.key(1), GameAction.jump)
        ..bind(InputSource.key(2), GameAction.use);

      final once = jsonEncode(bindings.toJson());
      final twice = jsonEncode(bindings.copy().toJson());

      expect(twice, once);
      expect(once.indexOf('jump'), lessThan(once.indexOf('use')));
    });

    test('a source id survives a name change, because it is not a name', () {
      // `LogicalKeyboardKey.keyId` is the stable half of a key; its debug name
      // is for people. Binding by the id is what makes a config outlive an SDK
      // upgrade, and this is the assertion that says so out loud.
      final source = InputSource.key(LogicalKeyboardKey.space.keyId);
      expect(source.id, 'key:${LogicalKeyboardKey.space.keyId}');
      expect(source.id, isNot(contains('Space')));
    });
  });

  group('the defaults', () {
    test('every call gets a table of its own', () {
      // Mutation: make `defaultBindings` a `static final` field. Rebinding
      // anything then rebinds it for every other DesktopInput in the process —
      // the menu, the next level, the second window.
      final first = DesktopInput.defaultBindings()
        ..clearAction(GameAction.jump);
      final second = DesktopInput.defaultBindings();

      expect(first.sourcesFor(GameAction.jump), isEmpty);
      expect(second.sourcesFor(GameAction.jump), isNotEmpty);
    });

    test('the arrow keys walk as well as WASD', () {
      final bindings = DesktopInput.defaultBindings();
      expect(
        bindings[InputSource.key(LogicalKeyboardKey.arrowUp.keyId)],
        GameAction.moveForward,
      );
      expect(
        bindings[InputSource.key(LogicalKeyboardKey.keyW.keyId)],
        GameAction.moveForward,
      );
    });
  });
}
