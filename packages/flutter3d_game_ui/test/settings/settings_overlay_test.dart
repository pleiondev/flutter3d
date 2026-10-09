/// The gear and the panel, as one widget instead of three copies.
///
///     flutter test test/settings/settings_overlay_test.dart
///
/// The copies had already drifted — one game told the panel there was no
/// controller connected while the other two asked the pad — so what is tested
/// here is the wiring each game used to do by hand.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_audio_core/flutter3d_audio_core.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_ui/flutter3d_game_ui.dart';
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

const GameAction _jump = GameAction('jump');

ActionMap _defaults() => ActionMap(
  actions: const ActionSet('test', <ActionDeclaration>[
    ActionDeclaration(_jump),
  ]),
  buttons: Bindings(<InputSource, GameAction>{})
    ..bind(InputSource.key(0x20), _jump),
);

({Widget widget, GameSettingsController settings, List<String> opened})
_overlay({
  bool canOpen = true,
  bool padConnected = true,
  List<AudioBus> buses = settableBuses,
  Consents? privacy,
}) {
  final opened = <String>[];
  final settings = GameSettingsController(
    settings: const GameSettings(),
    actions: _defaults(),
    file: SettingsFile(appName: 'test', storage: _Storage()),
    apply: (GameSettings _) {},
  );
  return (
    widget: MaterialApp(
      home: Scaffold(
        body: Stack(
          children: <Widget>[
            SettingsOverlay(
              settings: settings,
              sections: SettingsSection.standard(
                buses: buses,
                defaultActions: _defaults,
                padConnected: padConnected,
                privacy: privacy,
              ),
              opening: () => opened.add('opening'),
              canOpen: canOpen,
            ),
          ],
        ),
      ),
    ),
    settings: settings,
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
    expect(it.settings.value.isOpen, isTrue);
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

  testWidgets('and what the panel changes reaches the settings', (
    WidgetTester tester,
  ) async {
    // The volume, the setting, the rebind and the close used to be four
    // callbacks each game forwarded to the cubit by hand. The sections call
    // the controller themselves.
    final it = _overlay();
    await tester.pumpWidget(it.widget);
    it.settings.show();
    await tester.pumpAndSettle();

    // The first slider is the first bus's: the master volume.
    await tester.drag(find.byType(Slider).first, const Offset(-2000, 0));
    await tester.pumpAndSettle();
    expect(it.settings.settings.volumeOf(AudioBus.master), 0.0);

    await tester.tap(find.text('Back to the game'));
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
    expect(it.settings.actions.buttons[InputSource.key(0x41)], _jump);

    tester
        .widget<ActionBindingsSection>(find.byType(ActionBindingsSection))
        .onReset();

    expect(it.settings.actions.buttons[InputSource.key(0x41)], isNull);
    expect(it.settings.actions.buttons[InputSource.key(0x20)], _jump);
  });

  testWidgets('and the panel is told what it was told, not a constant', (
    WidgetTester tester,
  ) async {
    final it = _overlay(padConnected: false);
    await tester.pumpWidget(it.widget);
    it.settings.show();
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<SettingsPanel>(find.byType(SettingsPanel))
          .sections
          .whereType<GamepadSection>()
          .single
          .isConnected,
      isFalse,
    );
  });

  testWidgets('and the sliders it was given are the sliders it hands on', (
    WidgetTester tester,
  ) async {
    // **The link the three games actually use.** Each passes `busesIn` of
    // its own bank to `SettingsSection.standard`, so a list that used
    // `settableBuses` instead would put the Music slider back over a game
    // with no music and nothing would notice.
    //
    // Mutation: build the volumes section from `settableBuses` in
    // `standard` and this fails.
    final it = _overlay(buses: const <AudioBus>[AudioBus.master, AudioBus.sfx]);
    await tester.pumpWidget(it.widget);
    it.settings.show();
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<SettingsPanel>(find.byType(SettingsPanel))
          .sections
          .whereType<VolumesSection>()
          .single
          .buses,
      const <AudioBus>[AudioBus.master, AudioBus.sfx],
    );
    expect(find.text('music'), findsNothing);
  });

  testWidgets('and the questions about the player\'s data reach the panel, '
      'both off', (WidgetTester tester) async {
    // Mutation: an overlay that does not hand them on, which leaves every
    // game's settings without them while the section's own test passes.
    final consents = Consents(storage: _Storage(), policy: '2026-10');
    final it = _overlay(privacy: consents);
    await tester.pumpWidget(it.widget);
    it.settings.show();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('privacy:telemetry')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    for (final key in <String>['privacy:cloud', 'privacy:telemetry']) {
      expect(
        tester
            .widget<Switch>(
              find.descendant(
                of: find.byKey(ValueKey<String>(key)),
                matching: find.byType(Switch),
              ),
            )
            .value,
        isFalse,
        reason: key,
      );
    }
  });
}
