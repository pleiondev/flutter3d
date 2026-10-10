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
import 'package:flutter3d_audio_core/flutter3d_audio_core.dart' show AudioBus;
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

/// A storage that keeps everything in a map, for the callers above it.
final class MemoryStorage extends Storage {
  final Map<String, String> documents = <String, String>{};
  bool refuse = false;

  @override
  Future<String?> read(String name) async => documents[name];

  @override
  Future<void> write(String name, String contents) async {
    if (refuse) throw StorageException(name, 'refused');
    documents[name] = contents;
  }

  @override
  Future<void> remove(String name) async => documents.remove(name);
}

void main() {
  group('what a player changed', () {
    test('survives being written and read back', () async {
      final storage = MemoryStorage();
      final config = const GameSettings()
          .withVolume(AudioBus.music, 0.4)
          .withValue(GameSettingKeys.toggleSprint, true)
          .copyWith(
            actions: ActionMap(actions: ActionSet.common)
              ..buttons.bind(
                InputSource.pad('face.east'),
                const GameAction('dash'),
              ),
          );

      await SettingsFile(appName: 'game', storage: storage).write(config);
      final read = await SettingsFile(appName: 'game', storage: storage).read();

      expect(read.volumeOf(AudioBus.music), 0.4);
      expect(read.valueOf(GameSettingKeys.toggleSprint), isTrue);
      expect(
        read.actions!.buttons[InputSource.pad('face.east')],
        const GameAction('dash'),
      );
    });

    test('and a first run is defaults rather than a failure', () async {
      final read = await SettingsFile(
        appName: 'game',
        storage: MemoryStorage(),
      ).read();

      expect(read.volumeOf(AudioBus.master), 1.0);
    });

    test(
      'and a document somebody hand-edited into nonsense costs one launch',
      () async {
        // Never throws. What is lost is the bindings, which is a bad day; what is
        // avoided is a game that will not start, which is a bug report nobody can
        // act on.
        final storage = MemoryStorage()
          ..documents['settings.json'] = '{"volumes": ';

        expect(
          (await SettingsFile(
            appName: 'game',
            storage: storage,
          ).read()).volumeOf(AudioBus.sfx),
          1.0,
        );
      },
    );

    test('and a storage that refuses says so rather than pretending', () async {
      // A quota that ran out in a browser, or a disk that filled. The boolean is
      // for a caller that wants to tell the player.
      final storage = MemoryStorage()..refuse = true;

      expect(
        await SettingsFile(
          appName: 'game',
          storage: storage,
        ).write(const GameSettings()),
        isFalse,
      );
    });

    test('and two games do not overwrite each other', () async {
      // The failure that only happens to somebody who plays both, which is why
      // it went unnoticed until there were two.
      final one = MemoryStorage();
      final two = MemoryStorage();
      await SettingsFile(
        appName: 'platformer',
        storage: one,
      ).write(const GameSettings().withVolume(AudioBus.music, 0.1));
      await SettingsFile(
        appName: 'dungeon',
        storage: two,
      ).write(const GameSettings().withVolume(AudioBus.music, 0.9));

      expect(
        (await SettingsFile(
          appName: 'platformer',
          storage: one,
        ).read()).volumeOf(AudioBus.music),
        0.1,
      );
    });
  });
}
