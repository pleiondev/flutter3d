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
}
