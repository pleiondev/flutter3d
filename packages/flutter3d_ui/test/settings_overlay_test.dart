/// The gear and the panel, as one widget instead of three copies.
///
///     flutter test test/settings_overlay_test.dart
///
/// The copies had already drifted — one game told the panel there was no
/// controller connected while the other two asked the pad — so what is tested
/// here is the wiring each game used to do by hand.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_ui/flutter3d_ui.dart';
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

const GameAction _jump = GameAction('jump');

Bindings _defaults() =>
    Bindings(<InputSource, GameAction>{})..bind(InputSource.key(0x20), _jump);

({
  Widget widget,
  SettingsCubit settings,
  GameConfig config,
  List<String> opened,
})
_overlay({bool canOpen = true, bool padConnected = true}) {
  final config = GameConfig();
  final opened = <String>[];
  final settings = SettingsCubit(
    config: config,
    file: SettingsFile(appName: 'test', storage: _Storage()),
    apply: (GameConfig _) {},
  );
  return (
    widget: MaterialApp(
      home: Scaffold(
        body: Stack(
          children: <Widget>[
            SettingsOverlay(
              settings: settings,
              mixer: Mixer(),
              bindings: ownedBindings(config, _defaults),
              config: config,
              padConnected: padConnected,
              actions: const <GameAction>[_jump],
              defaultBindings: _defaults,
              opening: () => opened.add('opening'),
              canOpen: canOpen,
            ),
          ],
        ),
      ),
    ),
    settings: settings,
    config: config,
    opened: opened,
  );
}

void main() {
  testWidgets('the gear opens the panel, and lets go of the game first', (
    WidgetTester tester,
  ) async {
    // [opening] is the same callback `settingsKeys` takes: a panel opened by a
    // gear and a panel opened by Escape have to arrive in the same state, or a
    // key held as the panel appeared stays held and closing it sends the player
    // walking off on their own.
    final it = _overlay();
    await tester.pumpWidget(it.widget);

    expect(find.byIcon(Icons.settings), findsOneWidget);

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();

    expect(it.opened, <String>[
      'opening',
    ], reason: 'the gear opened a panel without letting go of the game');
    expect(it.settings.state.isOpen, isTrue);
    expect(
      find.byIcon(Icons.settings),
      findsNothing,
      reason: 'the gear and the panel are the same state seen twice',
    );
  });

  testWidgets('and closing it puts the gear back', (WidgetTester tester) async {
    final it = _overlay();
    await tester.pumpWidget(it.widget);
    it.settings.show();
    await tester.pumpAndSettle();

    it.settings.hide();
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.settings), findsOneWidget);
  });

  testWidgets('and a screen with no gear still shows a panel that is open', (
    WidgetTester tester,
  ) async {
    // The platformer's title card carries the same settings on it, so a stray
    // gear has nothing to add — but a game that reaches that screen with the
    // panel up should not have it vanish.
    final it = _overlay(canOpen: false);
    await tester.pumpWidget(it.widget);

    expect(find.byIcon(Icons.settings), findsNothing);

    it.settings.show();
    await tester.pumpAndSettle();

    expect(find.byType(SettingsPanel), findsOneWidget);
  });

  testWidgets('and what the panel changes reaches the config', (
    WidgetTester tester,
  ) async {
    // The volume, the setting, the rebind and the close used to be four
    // callbacks each game forwarded to the cubit by hand. They are wired once.
    final it = _overlay();
    await tester.pumpWidget(it.widget);
    it.settings.show();
    await tester.pumpAndSettle();

    final panel = tester.widget<SettingsPanel>(find.byType(SettingsPanel));
    panel.onVolume(AudioBus.sfx, 0.25);
    panel.onSetting('a11y.cameraMotion', 0.0);

    expect(it.config.volumeOf(AudioBus.sfx.name), 0.25);
    expect(it.config.settingOf('a11y.cameraMotion', 1.0), 0.0);

    panel.onClose();
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.settings), findsOneWidget);
  });

  testWidgets('and resetting the controls asks the game for its own table', (
    WidgetTester tester,
  ) async {
    // Its own, not the engine's: a driver rebinds a throttle and a runner
    // rebinds a jump, and a reset that handed back `GameAction.common` would
    // leave a game bound to actions it does not have.
    final it = _overlay();
    await tester.pumpWidget(it.widget);
    it.settings.show();
    await tester.pumpAndSettle();

    it.settings.rebind(_jump);
    it.settings.capture(InputSource.key(0x41));
    expect(it.config.bindings[InputSource.key(0x41)], _jump);

    tester.widget<SettingsPanel>(find.byType(SettingsPanel)).onResetControls();

    expect(it.config.bindings[InputSource.key(0x41)], isNull);
    expect(it.config.bindings[InputSource.key(0x20)], _jump);
  });

  testWidgets('and the panel is told what it was told, not a constant', (
    WidgetTester tester,
  ) async {
    final it = _overlay(padConnected: false);
    await tester.pumpWidget(it.widget);
    it.settings.show();
    await tester.pumpAndSettle();

    expect(
      tester.widget<SettingsPanel>(find.byType(SettingsPanel)).padConnected,
      isFalse,
    );
  });
}
