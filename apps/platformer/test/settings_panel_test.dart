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
import 'package:flutter_test/flutter_test.dart';
import 'package:gamepad/gamepad.dart';
import 'package:platformer/src/settings_panel.dart';

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

  testWidgets('the bindings list counts controls, not keys', (
    WidgetTester tester,
  ) async {
    // Jump is a key and a face button once the pad's defaults are in the table,
    // and a row saying "2 keys" would be a lie in the one place a player goes to
    // find out what is bound.
    await tester.pumpWidget(_panel());

    expect(find.text('1 key'), findsNothing);
    expect(find.textContaining('controls'), findsWidgets);
  });
}

/// The panel as the game mounts it, inside the [Scaffold] the sliders need.
Widget _panel({
  Mixer? mixer,
  GameConfig? config,
  bool padConnected = false,
  void Function(String name, double value)? onSetting,
}) =>
    MaterialApp(
      home: Scaffold(
        body: SettingsPanel(
          mixer: mixer ?? _mixer(),
          // The same table the game builds: both halves of it, because that is
          // what the rows below are counting.
          bindings: PadInput.addDefaultsTo(DesktopInput.defaultBindings()),
          config: config ?? GameConfig(),
          padConnected: padConnected,
          onVolume: (AudioBus bus, double volume) {},
          onSetting: onSetting ?? (String name, double value) {},
          onClose: () {},
        ),
      ),
    );
