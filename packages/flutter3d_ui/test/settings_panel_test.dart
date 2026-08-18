/// The screen where a player changes the game.
///
///     flutter test test/settings_panel_test.dart
///
/// **Written because a commit message about this panel was wrong.** It claimed
/// the panel had a music slider; the panel had `master` and `sfx`, the mixer had
/// carried a music bus since the soundtrack landed, and the application had been
/// restoring its saved volume all along. Nothing was broken except the one
/// slider a player reaches for first, and nothing could notice.
///
/// So the promises are tests now: every bus the mixer is carrying has a slider,
/// and a gamepad number can be moved and is shown while it moves. Both are read
/// off the mounted widget rather than off the list inside it, because the list
/// inside it is the thing that was wrong.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_ui/flutter3d_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gamepad/gamepad.dart';

/// The mixer the game hands the panel: every bus it restores from the config.
Mixer _mixer() => Mixer()
  ..setVolume(AudioBus.master, 0.8)
  ..setVolume(AudioBus.music, 0.5)
  ..setVolume(AudioBus.sfx, 0.9);

void main() {
  testWidgets('every bus the mixer carries has a slider', (
    WidgetTester tester,
  ) async {
    // **The test the missing music slider would have failed.** Read from the
    // mixer, because a list of buses written beside the mixer's own list is
    // exactly the duplication that went wrong.
    final mixer = _mixer();
    await tester.pumpWidget(_panel(mixer: mixer));

    for (final bus in mixer.configured) {
      expect(find.text(bus.name), findsOneWidget,
          reason: 'the mixer carries ${bus.name} and the panel does not offer '
              'it, so a player cannot change a volume the game restores');
    }
  });

  testWidgets('a gamepad number shows what it is set to', (
    WidgetTester tester,
  ) async {
    final config = GameConfig()..setSetting('pad.deadzone.stick', 0.28);
    await tester.pumpWidget(_panel(config: config));

    expect(find.text('0.28'), findsOneWidget);
  });

  testWidgets('and defaults to the device package rather than to a guess', (
    WidgetTester tester,
  ) async {
    // A panel with its own idea of the default would show one number while the
    // pad used another, and the player would be tuning against a lie.
    await tester.pumpWidget(_panel());

    expect(
      find.text(const Deadzone().stick.toStringAsFixed(2)),
      findsOneWidget,
    );
  });

  testWidgets('and moving it reports the change at once', (
    WidgetTester tester,
  ) async {
    // At once, because the point of a dead-zone slider is that a player moves it
    // and feels the stick change. One that took effect on the next launch could
    // not be chosen at all.
    final changed = <String, double>{};
    await tester.pumpWidget(_panel(
      onSetting: (String name, double value) => changed[name] = value,
    ));

    // Scrolled to first, because the panel is taller than the test window and a
    // tap at coordinates nobody can see lands nowhere. Tapped along the track
    // rather than dragged: a drag inside a scrolling panel is a gesture two
    // widgets can claim, and which one wins is not what this test is about.
    await tester.ensureVisible(find.byType(Slider).last);
    await tester.pumpAndSettle();
    final track = tester.getRect(find.byType(Slider).last);
    await tester.tapAt(Offset(track.right - 12.0, track.center.dy));

    expect(changed.keys, contains('pad.look'));
  });

  testWidgets('and the panel says when there is nothing to tune', (
    WidgetTester tester,
  ) async {
    // A slider that acts on a controller nobody has plugged in is a slider that
    // does nothing, and saying so is cheaper than hiding it and being asked
    // where the gamepad settings went.
    await tester.pumpWidget(_panel());
    expect(find.text('Gamepad (none connected)'), findsOneWidget);

    await tester.pumpWidget(_panel(padConnected: true));
    expect(find.text('Gamepad'), findsOneWidget);
  });

  group('accessibility', () {
    testWidgets('the camera can be told to stop flinching', (
      WidgetTester tester,
    ) async {
      // A camera that shakes on every landing is what makes some players ill,
      // and the following is the game. This turns down the first only.
      final changed = <String, double>{};
      await tester.pumpWidget(_panel(
        onSetting: (String name, double value) => changed[name] = value,
      ));

      // Found by its label rather than by an index, so adding a slider above it
      // does not silently move this test onto a different setting.
      final slider = find.descendant(
        of: find.widgetWithText(MergeSemantics, 'Camera motion'),
        matching: find.byType(Slider),
      );
      await tester.ensureVisible(slider);
      await tester.pumpAndSettle();
      final track = tester.getRect(slider);
      await tester.tapAt(Offset(track.left + 4.0, track.center.dy));

      expect(changed['a11y.cameraMotion'], isNotNull);
      expect(changed['a11y.cameraMotion'], lessThan(0.2));
    });

    testWidgets('and sprinting can be latched instead of held', (
      WidgetTester tester,
    ) async {
      // The accommodation every guideline names first: holding a key for the
      // length of a climb is a real barrier, and the switch reads as the thing
      // being turned *off* because that is what a player looks for.
      final changed = <String, double>{};
      await tester.pumpWidget(_panel(
        onSetting: (String name, double value) => changed[name] = value,
      ));

      final toggle = find.byType(Switch);
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(toggle);

      expect(changed['a11y.toggleSprint'], 1.0);
    });

    testWidgets('and a screen reader is told what each row is', (
      WidgetTester tester,
    ) async {
      // The panel is the one screen a player has to use before they can play,
      // and every row of it was an unnamed rectangle.
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_panel());

      expect(
        find.bySemanticsLabel(RegExp('jump, bound to')),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('rebinding', () {
    testWidgets('a row says what its action is bound to, by name', (
      WidgetTester tester,
    ) async {
      // `key:32` is what gets saved and is not a thing anybody can read. This is
      // the one place that translates, and it translates for showing only.
      await tester.pumpWidget(_panel());

      expect(find.textContaining('Space'), findsOneWidget);
      expect(find.textContaining('key:'), findsNothing);
    });

    testWidgets('and a pad button keeps its position name', (
      WidgetTester tester,
    ) async {
      // There is no way to know what is printed on it: `face.south` is where the
      // button is, and a screen that guessed `A` would guess wrong on half the
      // controllers in the world.
      await tester.pumpWidget(_panel());

      expect(find.textContaining('pad face.south'), findsOneWidget);
    });

    testWidgets('and tapping one asks for the new control', (
      WidgetTester tester,
    ) async {
      GameAction? asked;
      await tester.pumpWidget(_panel(
        onRebind: (GameAction? action) => asked = action,
      ));

      await tester.tap(find.textContaining('Space'));

      expect(asked, GameAction.jump);
    });

    testWidgets('and the row waiting says so', (WidgetTester tester) async {
      await tester.pumpWidget(_panel(waitingFor: GameAction.jump));

      expect(find.text('press a key or a button'), findsOneWidget);
    });

    testWidgets('and an action bound to nothing says that out loud', (
      WidgetTester tester,
    ) async {
      // An action with no control is a verb the player cannot reach, which is
      // the exact condition this screen exists to fix. An empty space would hide
      // it.
      await tester.pumpWidget(_panel(bindings: Bindings()));

      expect(find.text('nothing'), findsWidgets);
    });
  });

  testWidgets('the bindings list counts controls, not keys', (
    WidgetTester tester,
  ) async {
    // Jump is a key and a face button once the pad's defaults are in the table,
    // and a row saying "2 keys" would be a lie in the one place a player goes to
    // find out what is bound.
    await tester.pumpWidget(_panel());

    expect(find.text('1 key'), findsNothing);
  });
}

/// The panel as the game mounts it, inside the [Scaffold] the sliders need.
Widget _panel({
  Mixer? mixer,
  GameConfig? config,
  Bindings? bindings,
  bool padConnected = false,
  void Function(String name, double value)? onSetting,
  GameAction? waitingFor,
  void Function(GameAction? action)? onRebind,
  VoidCallback? onResetControls,
}) =>
    MaterialApp(
      home: Scaffold(
        body: SettingsPanel(
          mixer: mixer ?? _mixer(),
          // The same table the game builds: both halves of it, because that is
          // what the rows below are showing.
          bindings:
              bindings ?? PadInput.addDefaultsTo(DesktopInput.defaultBindings()),
          config: config ?? GameConfig(),
          padConnected: padConnected,
          onVolume: (AudioBus bus, double volume) {},
          onSetting: onSetting ?? (String name, double value) {},
          onClose: () {},
          actions: const <GameAction>[GameAction.jump, GameAction.sprint],
          waitingFor: waitingFor,
          onRebind: onRebind ?? (GameAction? action) {},
          onResetControls: onResetControls ?? () {},
        ),
      ),
    );
