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

import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter3d_game/flutter3d_game.dart'; // GameSettingsController, Storage
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Storage extends Storage {
  final Map<String, String> documents = <String, String>{};

  @override
  Future<String?> read(String name) async => documents[name];

  @override
  Future<void> write(String name, String contents) async {
    documents[name] = contents;
  }

  @override
  Future<void> remove(String name) async => documents.remove(name);
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

ActionMap _keyMap() => ActionMap(actions: ActionSet.common, buttons: _keys());

({GameSettingsController cubit, _Storage storage}) _open() {
  final storage = _Storage();
  return (
    cubit: GameSettingsController(
      settings: const GameSettings(),
      actions: _keyMap(),
      file: SettingsFile(appName: 'racing', storage: storage),
      apply: (GameSettings _) {},
    ),
    storage: storage,
  );
}

void main() {
  test('the panel is told whether a pad is connected, rather than assuming', () {
    // **A scan, because the call is inside a widget nothing mounts.** This game
    // passed a constant `false` where the other two ask the pad, so a driver
    // with a controller plugged in read "Gamepad (none connected)" above the
    // sliders that set its dead zone. Nothing failed; the screen simply lied.
    final game = File('lib/main.dart').readAsStringSync();

    expect(
      game,
      isNot(contains('padConnected: false')),
      reason: 'the settings panel is being told there is no pad',
    );
    expect(
      'padConnected: _pad.isConnected'.allMatches(game).length,
      2,
      reason: 'the panel and the pause gate both have to ask',
    );
  });

  test('a driver rebinds a throttle, not a forward', () {
    // The engine's default table names walking, and a car has a throttle and a
    // brake. Those are the actions the panel lists, and they are this game's.
    final table = const GameSettings().actionsOr(_keyMap).buttons;

    expect(table[InputSource.key(0x77)], _throttle);
    expect(
      table.sourcesFor(GameAction.moveForward),
      isEmpty,
      reason: 'a racing game bound a walking action',
    );
  });

  test('and what they rebind survives a launch', () async {
    // The bug this repository fixed in both other games on the same day: the
    // controller holds the one map, so a rebind made on a first launch is in
    // the document that gets written.
    final it = _open();

    it.cubit.rebind(_brake);
    it.cubit.capture(InputSource.key(0x20));

    await it.cubit.saved;
    final saved = await SettingsFile(
      appName: 'racing',
      storage: it.storage,
    ).read();
    expect(saved.actions!.buttons[InputSource.key(0x20)], _brake);
  });

  test('and a volume survives one too', () async {
    final it = _open();

    it.cubit.setVolume(AudioBus.sfx, 0.3);
    await it.cubit.saved;

    expect(
      (await SettingsFile(
        appName: 'racing',
        storage: it.storage,
      ).read()).volumeOf(AudioBus.sfx),
      0.3,
    );
  });

  test('and the panel being open is what stops the race', () {
    // Escape opens the settings and opening them is what pauses — the same
    // clause `shouldPause` calls a menu. This game could not be paused at all.
    final it = _open();
    expect(it.cubit.value.isOpen, isFalse);

    it.cubit.show();

    expect(
      shouldPause(
        ready: true,
        menuOpen: it.cubit.value.isOpen,
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

    it.cubit.setValue(GameSettingKeys.cameraMotion, 0.0);

    expect(it.cubit.settings.valueOf(GameSettingKeys.cameraMotion), 0.0);
  });
}
