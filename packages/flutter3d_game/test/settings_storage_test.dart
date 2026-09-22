/// What a player changed, kept through a [Storage].
///
///     flutter test test/settings_storage_test.dart
///
/// The storage's own promise — a document written is a document read back,
/// on whichever platform this build is — is `flutter3d_app`'s and is tested
/// there. What a settings document does with that promise is a game's, and is
/// tested here.
///
/// A settings document that cannot be written looks exactly like a player who
/// has changed no settings, which is why each failure below is asked for by
/// name rather than trusted to show up.
library;

import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
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
      expect(
        read.bindings[InputSource.pad('face.east')],
        const GameAction('dash'),
      );
    });

    test('and a first run is defaults rather than a failure', () {
      final read = SettingsFile(
        appName: 'game',
        storage: MemoryStorage(),
      ).read();

      expect(read.volumeOf('master'), 1.0);
    });

    test('and a document somebody hand-edited into nonsense costs one launch', () {
      // Never throws. What is lost is the bindings, which is a bad day; what is
      // avoided is a game that will not start, which is a bug report nobody can
      // act on.
      final storage = MemoryStorage()
        ..documents['settings.json'] = '{"volumes": ';

      expect(
        SettingsFile(appName: 'game', storage: storage).read().volumeOf('sfx'),
        1.0,
      );
    });

    test('and a storage that refuses says so rather than pretending', () {
      // A quota that ran out in a browser, or a disk that filled. The boolean is
      // for a caller that wants to tell the player.
      final storage = MemoryStorage()..refuse = true;

      expect(
        SettingsFile(appName: 'game', storage: storage).write(GameConfig()),
        isFalse,
      );
    });

    test('and two games do not overwrite each other', () {
      // The failure that only happens to somebody who plays both, which is why
      // it went unnoticed until there were two.
      final one = MemoryStorage();
      final two = MemoryStorage();
      SettingsFile(
        appName: 'platformer',
        storage: one,
      ).write(GameConfig()..setVolume('music', 0.1));
      SettingsFile(
        appName: 'dungeon',
        storage: two,
      ).write(GameConfig()..setVolume('music', 0.9));

      expect(
        SettingsFile(
          appName: 'platformer',
          storage: one,
        ).read().volumeOf('music'),
        0.1,
      );
    });
  });
}
