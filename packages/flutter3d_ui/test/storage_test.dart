/// Where what a player changed is kept.
///
///     flutter test
///     flutter test --platform chrome test/storage_test.dart
///
/// The second command names this file rather than the package, and that is not
/// fussiness: `@TestOn('vm')` filters what *runs*, not what is compiled, so the
/// two files here that touch `dart:io` would fail the whole browser run before
/// this one got a chance. This is the file with the browser's half in it —
/// `localStorage`, written and read back through the real thing.
///
/// **Two of the four platforms were losing it silently.** The settings and the
/// save were files under `$HOME/Library/Application Support`, which is right on
/// macOS — a sandboxed application's `HOME` *is* its container — and is nowhere
/// on the other three. In a browser `dart:io` throws on the way past
/// `Platform.environment` and the throw was swallowed into defaults, so every
/// launch was a first launch. On Android `HOME` is not the application's
/// anything, so the write failed and was swallowed the same way.
///
/// Neither was visible, and that is the point of this file: a settings document
/// that cannot be written looks exactly like a player who has changed no
/// settings, and a save that cannot be written looks exactly like a player who
/// has not reached a checkpoint.
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_ui/flutter3d_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// A storage that keeps everything in a map, for the callers above it.
final class MemoryStorage implements Storage {
  final Map<String, String> documents = <String, String>{};
  bool refuse = false;

  @override
  String? read(String name) => documents[name];

  @override
  bool write(String name, String contents) {
    if (refuse) return false;
    documents[name] = contents;
    return true;
  }

  @override
  void remove(String name) => documents.remove(name);
}

void main() {
  group('what a player changed', () {
    test('survives being written and read back', () {
      final storage = MemoryStorage();
      final config = GameConfig()
        ..setVolume('music', 0.4)
        ..setSetting('a11y.toggleSprint', 1.0)
        ..bindings.bind(InputSource.pad('face.east'), const GameAction('dash'));

      SettingsFile(appName: 'game', storage: storage).write(config);
      final read = SettingsFile(appName: 'game', storage: storage).read();

      expect(read.volumeOf('music'), 0.4);
      expect(read.settingOf('a11y.toggleSprint', 0.0), 1.0);
      expect(read.bindings[InputSource.pad('face.east')],
          const GameAction('dash'));
    });

    test('and a first run is defaults rather than a failure', () {
      final read = SettingsFile(appName: 'game', storage: MemoryStorage()).read();

      expect(read.volumeOf('master'), 1.0);
    });

    test('and a document somebody hand-edited into nonsense costs one launch',
        () {
      // Never throws. What is lost is the bindings, which is a bad day; what is
      // avoided is a game that will not start, which is a bug report nobody can
      // act on.
      final storage = MemoryStorage()
        ..documents['settings.json'] = '{"volumes": ';

      expect(SettingsFile(appName: 'game', storage: storage).read().volumeOf('sfx'),
          1.0);
    });

    test('and a storage that refuses says so rather than pretending', () {
      // A quota that ran out in a browser, or a disk that filled. The boolean is
      // for a caller that wants to tell the player.
      final storage = MemoryStorage()..refuse = true;

      expect(SettingsFile(appName: 'game', storage: storage).write(GameConfig()),
          isFalse);
    });

    test('and two games do not overwrite each other', () {
      // The failure that only happens to somebody who plays both, which is why
      // it went unnoticed until there were two.
      final one = MemoryStorage();
      final two = MemoryStorage();
      SettingsFile(appName: 'platformer', storage: one)
          .write(GameConfig()..setVolume('music', 0.1));
      SettingsFile(appName: 'dungeon', storage: two)
          .write(GameConfig()..setVolume('music', 0.9));

      expect(SettingsFile(appName: 'platformer', storage: one).read()
          .volumeOf('music'), 0.1);
    });
  });

  group('the storage this build actually gets', () {
    test('keeps a document across two of its own instances', () {
      // The real one, whichever it is: `localStorage` under chrome and a file
      // everywhere else. What is checked is the promise both make.
      final storage = defaultStorage('flutter3d_ui_test');
      addTearDown(() => storage.remove('probe.json'));

      expect(storage.write('probe.json', '{"kept":true}'), isTrue);

      expect(defaultStorage('flutter3d_ui_test').read('probe.json'),
          '{"kept":true}');
    });

    test('and forgets one when asked', () {
      final storage = defaultStorage('flutter3d_ui_test');
      storage.write('probe.json', 'x');

      storage.remove('probe.json');

      expect(storage.read('probe.json'), isNull);
    });

    test('and reading what was never written is null, not a throw', () {
      expect(defaultStorage('flutter3d_ui_test').read('absent.json'), isNull);
    });
  });
}
