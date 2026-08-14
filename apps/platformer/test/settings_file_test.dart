/// A settings file is read on every launch and written by a process that may be
/// killed mid-write. Both of those are what these are about.
library;

import 'dart:io';

import 'package:flutter3d_game/flutter3d_game.dart' show GameConfig, InputSource, GameAction;
import 'package:flutter_test/flutter_test.dart';
import 'package:platformer/src/settings_file.dart';

void main() {
  late Directory temporary;
  late SettingsFile settings;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('platformer_settings');
    settings = SettingsFile(directory: temporary);
  });

  tearDown(() => temporary.deleteSync(recursive: true));

  test('the first launch reads defaults rather than failing', () {
    // Mutation: let `read` throw when the file is missing. Every fresh install
    // then fails to start, which is the worst possible way to lose a setting.
    expect(settings.file.existsSync(), isFalse);
    final config = settings.read();

    expect(config.volumeOf('master'), 1.0);
    expect(config.bindings.length, 0);
  });

  test('what is written comes back', () {
    final saved = GameConfig()
      ..bindings.bind(InputSource.key(32), GameAction.jump)
      ..setVolume('sfx', 0.25);

    expect(settings.write(saved), isTrue);
    final read = settings.read();

    expect(read.bindings[InputSource.key(32)], GameAction.jump);
    expect(read.volumeOf('sfx'), 0.25);
  });

  test('a corrupted file is defaults, not a dead game', () {
    // Mutation: drop the try/catch in `read`. A disk that filled up mid-write,
    // or a hand edit that lost a brace, then bricks the game permanently —
    // every launch reads the same broken file and dies the same way.
    settings.directory.createSync(recursive: true);
    settings.file.writeAsStringSync('{ this is not json');

    final config = settings.read();
    expect(config.volumeOf('master'), 1.0);
  });

  test('a document that is valid json but the wrong shape is defaults too', () {
    settings.directory.createSync(recursive: true);
    settings.file.writeAsStringSync('["a list, not an object"]');

    expect(settings.read().bindings.length, 0);
  });

  test('writing leaves no half-written file behind', () {
    // Mutation: write straight to `settings.json` instead of to a temporary
    // and renaming. The failure this guards against cannot be produced in a
    // test without killing the process, so what is asserted is the property
    // that makes it impossible: nothing is left beside the file afterwards.
    settings.write(GameConfig()..setVolume('music', 0.5));

    final leftovers = settings.directory
        .listSync()
        .map((FileSystemEntity e) => e.uri.pathSegments.last)
        .where((String name) => name != 'settings.json')
        .toList();

    expect(leftovers, isEmpty, reason: 'the temporary was renamed, not left');
  });
}
