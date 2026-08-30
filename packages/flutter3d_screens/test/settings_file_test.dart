/// A settings file is read on every launch and written by a process that may be
/// killed mid-write. Both of those are what these are about.
///
/// On the VM only: what is being checked is a real document on a real disk,
/// including that nothing is left beside it after a write. Where the settings go
/// is `storage_test.dart`'s question, and it has the browser's half.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter3d_game/flutter3d_game.dart'
    show GameConfig, InputSource, GameAction;
import 'package:flutter3d_screens/flutter3d_screens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporary;
  late FileStorage storage;
  late SettingsFile settings;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('platformer_settings');
    storage = FileStorage(appName: 'test', directory: temporary);
    settings = SettingsFile(appName: 'test', storage: storage);
  });

  tearDown(() => temporary.deleteSync(recursive: true));

  test('the first launch reads defaults rather than failing', () {
    // Mutation: let `read` throw when the file is missing. Every fresh install
    // then fails to start, which is the worst possible way to lose a setting.
    expect(File('${temporary.path}/settings.json').existsSync(), isFalse);
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
    temporary.createSync(recursive: true);
    File(
      '${temporary.path}/settings.json',
    ).writeAsStringSync('{ this is not json');

    final config = settings.read();
    expect(config.volumeOf('master'), 1.0);
  });

  test('a document that is valid json but the wrong shape is defaults too', () {
    temporary.createSync(recursive: true);
    File(
      '${temporary.path}/settings.json',
    ).writeAsStringSync('["a list, not an object"]');

    expect(settings.read().bindings.length, 0);
  });

  test('writing leaves no half-written file behind', () {
    // Mutation: write straight to `settings.json` instead of to a temporary
    // and renaming. The failure this guards against cannot be produced in a
    // test without killing the process, so what is asserted is the property
    // that makes it impossible: nothing is left beside the file afterwards.
    settings.write(GameConfig()..setVolume('music', 0.5));

    final leftovers = temporary
        .listSync()
        .map((FileSystemEntity e) => e.uri.pathSegments.last)
        .where((String name) => name != 'settings.json')
        .toList();

    expect(leftovers, isEmpty, reason: 'the temporary was renamed, not left');
  });

  test('a document that is not an object says so rather than resetting', () {
    // **This arm said nothing at all**, which is worse than the `catch` beside
    // it: a stored `null`, a `[]`, a write truncated on a platform where the
    // atomic rename did not apply — all of them parse as JSON, none of them is
    // a settings document, and every one went back as defaults with no word
    // anywhere. A player whose bindings had just been silently reset had
    // nothing to report. `SaveFile.read` got exactly this right next door.
    //
    // Mutation: return `GameConfig()` without calling `onIssue`. The config
    // still comes back and nothing says the player's settings are gone.
    final said = <String>[];
    final file = SettingsFile(
      appName: 'test',
      storage: storage,
      onIssue: said.add,
    );
    storage.write('settings.json', '[]');

    final config = file.read();

    expect(config.volumeOf('music'), GameConfig().volumeOf('music'));
    expect(said.single, contains('not an object'));
  });
}
