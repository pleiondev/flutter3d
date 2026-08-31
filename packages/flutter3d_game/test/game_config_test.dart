/// A settings file is read far more often than it is written, and usually by a
/// build that is not the one that wrote it. These are about that.
library;

import 'dart:convert';

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';

const GameAction _dash = GameAction('dash');

void main() {
  test('what was set comes back', () {
    final saved = GameConfig()
      ..bindings.bind(InputSource.key(71), _dash)
      ..setVolume('music', 0.3);

    final read = GameConfig.fromJson(
      jsonDecode(jsonEncode(saved.toJson())) as Map<String, Object?>,
    );

    expect(read.bindings[InputSource.key(71)], _dash);
    expect(read.volumeOf('music'), 0.3);
  });

  test('an empty document is a working config, not a throw', () {
    // Mutation: make either field required in `fromJson`. The first run of a
    // fresh install reads a file that is not there, gets `{}`, and the game
    // fails to start rather than starting with defaults.
    final read = GameConfig.fromJson(const <String, Object?>{});

    expect(read.bindings.length, 0);
    expect(read.volumeOf('master'), 1.0, reason: 'unset is full');
  });

  test('a field this build does not understand does not stop the rest', () {
    final read = GameConfig.fromJson(<String, Object?>{
      'volumes': <String, Object?>{'music': 0.5},
      'invertMouse': true,
      'bindings': 'nonsense from a later version',
    });

    expect(read.volumeOf('music'), 0.5);
    expect(read.bindings.length, 0, reason: 'unreadable, so left empty');
  });

  test('volumes are clamped on the way in and sorted on the way out', () {
    final config = GameConfig()
      ..setVolume('sfx', 3.0)
      ..setVolume('music', -1.0)
      ..setVolume('master', 0.5);

    expect(config.volumeOf('sfx'), 1.0);
    expect(config.volumeOf('music'), 0.0);

    final text = jsonEncode(config.toJson());
    expect(text.indexOf('master'), lessThan(text.indexOf('music')));
    expect(text.indexOf('music'), lessThan(text.indexOf('sfx')));
  });

  group('settings that are not volumes', () {
    // **A dead zone has nowhere to live**, and that was the whole reason this
    // map exists: it belongs to a gamepad package `flutter3d_game` does not
    // depend on, and a look sensitivity belongs to a camera. A name and a
    // number is all this class needs to know about either.
    test('a setting nobody has touched answers with the caller\'s default', () {
      // No universal default here, unlike a volume: a sensitivity of one means
      // nothing without knowing whose. Only the caller knows.
      final config = GameConfig();

      expect(config.settingOf('pad.deadzone.stick', 0.15), 0.15);
    });

    test('and one that has been touched answers with the number', () {
      final config = GameConfig()..setSetting('pad.deadzone.stick', 0.22);

      expect(config.settingOf('pad.deadzone.stick', 0.15), closeTo(0.22, 1e-9));
    });

    test('a sensitivity above one is an ordinary request', () {
      // Not clamped, because this map holds things that are not fractions — and
      // a class that knew which names were fractions would be a class that knew
      // what a gamepad is.
      final config = GameConfig()..setSetting('pad.look', 3.5);

      expect(config.settingOf('pad.look', 1.0), closeTo(3.5, 1e-9));
    });

    test('they round-trip, sorted, and are omitted when there are none', () {
      // Omitted when empty so a config written by a build that had no settings
      // reads back byte for byte — the same promise the level format now makes.
      expect(GameConfig().toJson().containsKey('settings'), isFalse);

      final config = GameConfig()
        ..setSetting('pad.look', 2.0)
        ..setSetting('mouse.look', 1.0);
      final json = config.toJson();

      expect((json['settings']! as Map<String, Object?>).keys,
          <String>['mouse.look', 'pad.look']);
      expect(GameConfig.fromJson(json).settingOf('pad.look', 0.0), 2.0);
    });

    test('and a hand-edited string costs one key, not the file', () {
      // A settings file is edited by hand more often than anybody admits.
      final config = GameConfig.fromJson(<String, Object?>{
        'settings': <String, Object?>{
          'pad.look': 'quite fast',
          'pad.deadzone.stick': 0.2,
        },
      });

      expect(config.settingOf('pad.look', 1.0), 1.0);
      expect(config.settingOf('pad.deadzone.stick', 0.15), closeTo(0.2, 1e-9));
    });
  });
}
