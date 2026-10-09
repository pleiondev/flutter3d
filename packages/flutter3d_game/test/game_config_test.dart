/// A settings file is read far more often than it is written, and usually by a
/// build that is not the one that wrote it. These are about that.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_audio_core/flutter3d_audio_core.dart' show AudioBus;
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

const GameAction _dash = GameAction('dash');

GameSettings _roundTrip(GameSettings settings) => GameSettings.fromJson(
  jsonDecode(jsonEncode(settings.toJson())) as Map<String, Object?>,
);

void main() {
  test('what was set comes back', () {
    final saved = const GameSettings()
        .copyWith(
          actions: ActionMap(actions: ActionSet.common)
            ..buttons.bind(InputSource.key(71), _dash),
        )
        .withVolume(AudioBus.music, 0.3);

    final read = _roundTrip(saved);

    expect(read.actions!.buttons[InputSource.key(71)], _dash);
    expect(read.volumeOf(AudioBus.music), 0.3);
  });

  test('the file is in the envelope', () {
    final json = const GameSettings().toJson();
    // Mutation: write the body without `format.envelope()` — an older reader
    // cannot tell a settings file from any other JSON.
    expect(json['format'], 'f3d.settings');
    expect(json['version'], GameSettings.formatVersion);
  });

  test('an empty document is a working config, not a throw', () {
    // Mutation: make either field required in `fromJson`. The first run of a
    // fresh install reads a file that is not there, gets `{}`, and the game
    // fails to start rather than starting with defaults.
    final read = GameSettings.fromJson(const <String, Object?>{});

    expect(read.actions, isNull);
    expect(read.volumeOf(AudioBus.master), 1.0, reason: 'unset is full');
  });

  test('a field this build does not understand is kept and written back', () {
    final read = GameSettings.fromJson(<String, Object?>{
      'format': 'f3d.settings',
      'version': 2,
      'volumes': <String, Object?>{'music': 0.5},
      'invertMouse': true,
    });

    expect(read.volumeOf(AudioBus.music), 0.5);
    // Mutation: drop `unknown` from `toJson` — a later build's key is lost
    // the first time this one saves.
    expect(read.toJson()['invertMouse'], isTrue);
  });

  test('a file from a newer build is refused, naming both versions', () {
    expect(
      () => GameSettings.fromJson(<String, Object?>{
        'format': 'f3d.settings',
        'version': GameSettings.formatVersion + 1,
      }),
      throwsA(isA<GameSettingsFormatException>()),
    );
  });

  test('volumes are clamped on the way in and sorted on the way out', () {
    final config = const GameSettings()
        .withVolume(AudioBus.sfx, 3.0)
        .withVolume(AudioBus.music, -1.0)
        .withVolume(AudioBus.master, 0.5);

    expect(config.volumeOf(AudioBus.sfx), 1.0);
    expect(config.volumeOf(AudioBus.music), 0.0);

    final text = jsonEncode(config.toJson());
    expect(text.indexOf('master'), lessThan(text.indexOf('music')));
    expect(text.indexOf('music'), lessThan(text.indexOf('sfx')));
  });

  test('a change is a copy: the value it was made from does not move', () {
    const before = GameSettings();
    final after = before.withValue(GameSettingKeys.mouseLook, 2.0);
    // Mutation: write into `values` in place — `before` reads 2 as well.
    expect(before.valueOf(GameSettingKeys.mouseLook), 1.0);
    expect(after.valueOf(GameSettingKeys.mouseLook), 2.0);
    expect(after.withoutValue(GameSettingKeys.mouseLook).values, isEmpty);
  });

  group('typed settings', () {
    test('a setting nobody has touched is its fallback', () {
      expect(
        const GameSettings().valueOf(GameSettingKeys.stickDeadZone),
        GameSettingKeys.stickDeadZone.fallback,
      );
      expect(
        const GameSettings().chosenValueOf(GameSettingKeys.stickDeadZone),
        isNull,
      );
    });

    test('a game namespaces its own, and its type comes back', () {
      const subtitles = SettingKey<bool>('crypt.subtitles', fallback: true);
      expect(subtitles.namespace, 'crypt');
      final read = _roundTrip(const GameSettings().withValue(subtitles, false));
      expect(read.valueOf(subtitles), isFalse);
    });

    test('a sensitivity above one is an ordinary request', () {
      final config = const GameSettings().withValue(
        GameSettingKeys.padLook,
        3500.0,
      );
      expect(config.valueOf(GameSettingKeys.padLook), closeTo(3500.0, 1e-9));
    });

    test('they round-trip, sorted, and are omitted when there are none', () {
      expect(const GameSettings().toJson().containsKey('values'), isFalse);

      final json = const GameSettings()
          .withValue(GameSettingKeys.padLook, 2.0)
          .withValue(GameSettingKeys.mouseLook, 1.0)
          .toJson();

      expect((json['values']! as Map<String, Object?>).keys, <String>[
        'flutter3d.mouse.look',
        'flutter3d.pad.look',
      ]);
      expect(GameSettings.fromJson(json).valueOf(GameSettingKeys.padLook), 2.0);
    });

    test('and a hand-edited string costs one key, not the file', () {
      // A settings file is edited by hand more often than anybody admits.
      final config = GameSettings.fromJson(<String, Object?>{
        'format': 'f3d.settings',
        'version': 2,
        'values': <String, Object?>{
          'flutter3d.pad.look': 'quite fast',
          'flutter3d.pad.deadZone.stick': 0.2,
        },
      });

      expect(
        config.valueOf(GameSettingKeys.padLook),
        GameSettingKeys.padLook.fallback,
      );
      expect(config.valueOf(GameSettingKeys.stickDeadZone), closeTo(0.2, 1e-9));
    });
  });

  group('a file from before the envelope', () {
    test('reads its names under their namespaced ids', () {
      // Mutation: drop a name from `_renamedIn2` — a player's dead zone from
      // before the move is silently back to its default.
      final config = GameSettings.fromJson(<String, Object?>{
        'bindings': <String, Object?>{
          'dash': <Object?>['key:71'],
        },
        'volumes': <String, Object?>{'music': 0.25},
        'settings': <String, Object?>{
          'pad.deadzone.stick': 0.22,
          'a11y.toggleSprint': 1.0,
          'colour.enemy': 3.0,
          'crypt.torches': 0.5,
        },
      });

      expect(config.valueOf(GameSettingKeys.stickDeadZone), 0.22);
      expect(config.valueOf(GameSettingKeys.toggleSprint), isTrue);
      expect(config.valueOf(GameSettingKeys.colorRole('enemy')), 3);
      expect(config.values['crypt.torches'], 0.5);
      expect(config.volumeOf(AudioBus.music), 0.25);
      // The old button table is the action map's buttons now.
      expect(config.actions!.buttons[InputSource.key(71)], _dash);
    });
  });

  test('every version this build reads opens to the same settings', () {
    // A fixture per version, minted at it: version 1 is the file from before
    // the envelope. Mutation: drop `_liftFrom1` from the spec's migrations —
    // the old file reads its settings under names nobody asks for.
    final read = <GameSettings>[
      for (var v = 1; v <= GameSettings.formatVersion; v++)
        GameSettings.fromJson(
          jsonDecode(File('test/fixtures/v$v/settings.json').readAsStringSync())
              as Map<String, Object?>,
        ),
    ];
    for (final settings in read) {
      expect(settings.volumeOf(AudioBus.music), 0.4);
      expect(settings.valueOf(GameSettingKeys.cameraMotion), 0.5);
      expect(settings.valueOf(GameSettingKeys.toggleSprint), isTrue);
      expect(settings.valueOf(GameSettingKeys.colorRole('enemy')), 2);
      expect(settings.valueOf(GameSettingKeys.mouseLook), 1.5);
      expect(settings.valueOf(GameSettingKeys.stickDeadZone), 0.2);
      expect(
        settings.actions!.buttons[InputSource.pad('face.south')],
        GameAction.jump,
      );
    }
  });
}
