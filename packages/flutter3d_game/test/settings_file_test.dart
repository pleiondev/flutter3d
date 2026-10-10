/// A settings file is read on every launch and written by a process that may be
/// killed mid-write. Both of those are what these are about.
///
/// On the VM only: what is being checked is a real document on a real disk,
/// including that nothing is left beside it after a write. Where the settings go
/// is `storage_test.dart`'s question, and it has the browser's half.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_audio_core/flutter3d_audio_core.dart' show AudioBus;
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show ActionSet, GameAction;
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

  tearDown(() async => temporary.deleteSync(recursive: true));

  test('the first launch reads defaults rather than failing', () async {
    // Mutation: let `read` throw when the file is missing. Every fresh install
    // then fails to start, which is the worst possible way to lose a setting.
    expect(File('${temporary.path}/settings.json').existsSync(), isFalse);
    final config = await settings.read();

    expect(config.volumeOf(AudioBus.master), 1.0);
    expect(config.actions, isNull);
  });

  test('what is written comes back', () async {
    final saved = const GameSettings()
        .copyWith(
          actions: ActionMap(actions: ActionSet.common)
            ..buttons.bind(InputSource.key(32), GameAction.jump),
        )
        .withVolume(AudioBus.sfx, 0.25);

    expect(await settings.write(saved), isTrue);
    final read = await settings.read();

    expect(read.actions!.buttons[InputSource.key(32)], GameAction.jump);
    expect(read.volumeOf(AudioBus.sfx), 0.25);
  });

  test('a corrupted file is defaults, not a dead game', () async {
    // Mutation: drop the try/catch in `read`. A disk that filled up mid-write,
    // or a hand edit that lost a brace, then bricks the game permanently —
    // every launch reads the same broken file and dies the same way.
    temporary.createSync(recursive: true);
    File(
      '${temporary.path}/settings.json',
    ).writeAsStringSync('{ this is not json');

    final config = await settings.read();
    expect(config.volumeOf(AudioBus.master), 1.0);
  });

  test(
    'a document that is valid json but the wrong shape is defaults too',
    () async {
      temporary.createSync(recursive: true);
      File(
        '${temporary.path}/settings.json',
      ).writeAsStringSync('["a list, not an object"]');

      expect((await settings.read()).actions, isNull);
    },
  );

  test('writing leaves no half-written file behind', () async {
    // Mutation: write straight to `settings.json` instead of to a temporary
    // and renaming. The failure this guards against cannot be produced in a
    // test without killing the process, so what is asserted is the property
    // that makes it impossible: nothing is left beside the file afterwards.
    await settings.write(const GameSettings().withVolume(AudioBus.music, 0.5));

    final leftovers = temporary
        .listSync()
        .map((FileSystemEntity e) => e.uri.pathSegments.last)
        .where((String name) => name != 'settings.json')
        .toList();

    expect(leftovers, isEmpty, reason: 'the temporary was renamed, not left');
  });

  test('a document that is not an object says so rather than resetting', () async {
    // **This arm said nothing at all**, which is worse than the `catch` beside
    // it: a stored `null`, a `[]`, a write truncated on a platform where the
    // atomic rename did not apply — all of them parse as JSON, none of them is
    // a settings document, and every one went back as defaults with no word
    // anywhere. A player whose bindings had just been silently reset had
    // nothing to report. `SaveFile.read` got exactly this right next door.
    //
    // Mutation: return `const GameSettings()` without calling `onIssue`. The config
    // still comes back and nothing says the player's settings are gone.
    final said = <String>[];
    final file = SettingsFile(
      appName: 'test',
      storage: storage,
      onIssue: (Issue issue) => said.add(issue.message),
    );
    await storage.write('settings.json', '[]');

    final config = await file.read();

    expect(
      config.volumeOf(AudioBus.music),
      const GameSettings().volumeOf(AudioBus.music),
    );
    expect(said.single, contains('not an object'));
  });
}
