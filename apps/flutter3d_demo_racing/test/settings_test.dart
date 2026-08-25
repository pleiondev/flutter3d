/// What a player changes about this game, and whether it survives.
///
///     flutter test test/settings_test.dart
///
/// **This game had none of it.** No volumes, no rebinding, no accessibility —
/// the only settings it has ever had were the ones its author compiled in. The
/// panel and the rules behind it are shared with the other two games; what is
/// this game's own is the table of controls, and a driver's table is not a
/// walker's.
library;

import 'dart:io';

import 'package:flutter3d_app/flutter3d_app.dart'; // SettingsCubit, Storage
import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Storage implements Storage {
  final Map<String, String> documents = <String, String>{};

  @override
  String? read(String name) => documents[name];

  @override
  bool write(String name, String contents) {
    documents[name] = contents;
    return true;
  }

  @override
  void remove(String name) => documents.remove(name);
}

const GameAction _throttle = GameAction('throttle');
const GameAction _brake = GameAction('brake');

/// The table this game ships, as `main.dart` builds it.
///
/// Copied here rather than reached for, because it is `static` and private to
/// the widget — and the shape of what it contains is what this file is about,
/// not the exact keys.
Bindings _keys() => Bindings(<InputSource, GameAction>{})
  ..bind(InputSource.key(0x77), _throttle)
  ..bind(InputSource.key(0x73), _brake);

({SettingsCubit cubit, _Storage storage, GameConfig config}) _open() {
  final storage = _Storage();
  final config = GameConfig();
  return (
    cubit: SettingsCubit(
      config: config,
      file: SettingsFile(appName: 'racing', storage: storage),
      apply: (GameConfig _) {},
    ),
    storage: storage,
    config: config,
  );
}

void main() {
  test('the panel is told whether a pad is connected, rather than assuming', () {
    // **A scan, because the call is inside a widget nothing mounts.** This game
    // passed a constant `false` where the other two ask the pad, so a driver
    // with a controller plugged in read "Gamepad (none connected)" above the
    // sliders that set its dead zone. Nothing failed; the screen simply lied.
    final game = File('lib/main.dart').readAsStringSync();

    expect(game, isNot(contains('padConnected: false')),
        reason: 'the settings panel is being told there is no pad');
    expect('padConnected: _pad.isConnected'.allMatches(game).length, 2,
        reason: 'the panel and the pause gate both have to ask');
  });

  test('a driver rebinds a throttle, not a forward', () {
    // The engine's default table names walking, and a car has a throttle and a
    // brake. Those are the actions the panel lists, and they are this game's.
    final config = GameConfig();

    final table = ownedBindings(config, _keys);

    expect(table[InputSource.key(0x77)], _throttle);
    expect(table.sourcesFor(GameAction.moveForward), isEmpty,
        reason: 'a racing game bound a walking action');
  });

  test('and what they rebind survives a launch', () {
    // The bug this repository fixed in both other games on the same day: the
    // config owns the table, so a rebind made on a first launch is in the
    // document that gets written.
    final it = _open();
    final table = ownedBindings(it.config, _keys);
    expect(identical(table, it.config.bindings), isTrue);

    it.cubit.rebind(_brake);
    it.cubit.capture(InputSource.key(0x20));

    final saved = SettingsFile(appName: 'racing', storage: it.storage).read();
    expect(saved.bindings[InputSource.key(0x20)], _brake);
  });

  test('and a volume survives one too', () {
    final it = _open();

    it.cubit.setVolume(AudioBus.sfx.name, 0.3);

    expect(
      SettingsFile(appName: 'racing', storage: it.storage).read()
          .volumeOf(AudioBus.sfx.name),
      0.3,
    );
  });

  test('and the panel being open is what stops the race', () {
    // Escape opens the settings and opening them is what pauses — the same
    // clause `shouldPause` calls a menu. This game could not be paused at all.
    final it = _open();
    expect(it.cubit.state.isOpen, isFalse);

    it.cubit.show();

    expect(
      shouldPause(
        ready: true,
        menuOpen: it.cubit.state.isOpen,
        pointerIsTheGate: false,
        pointerHeld: false,
        padConnected: false,
      ),
      isTrue,
    );
  });

  test('and reduce-motion reaches a camera that moves more than most', () {
    // A racing camera leans into corners, widens with speed and is kicked by
    // every kerb. Somebody who has turned reduce-motion on has said something
    // about exactly that, and this game was not listening.
    final it = _open();

    it.cubit.setSetting('a11y.cameraMotion', 0.0);

    expect(it.config.settingOf('a11y.cameraMotion', 1.0), 0.0);
  });
}
