/// What the game owes the people whose work it ships.
///
///     flutter test test/credits_test.dart
///
/// **This is a licence condition, and it was being breached.** `penguin.glb`
/// and `coin.glb` are CC BY 4.0; `assets/models/LICENSES.md` records that
/// attribution "must appear wherever the game does"; and neither the
/// application nor the web page contained the author's name, the licence or a
/// link to it. It went unnoticed for the reason such things do — the file
/// recording the duty is not the file that discharges it, and nothing connected
/// the two.
///
/// So these tests connect them: one reads what the game actually ships from
/// disk, and one reads the screen a player can reach.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_ui/flutter3d_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platformer/src/credits.dart';

/// The panel as the game mounts it: inside a [Scaffold], because the volume
/// sliders need a [Material] ancestor and the game gives them one.
Widget _panel({GameConfig? config, bool padConnected = false}) => MaterialApp(
      home: Scaffold(
        body: SettingsPanel(
          mixer: Mixer(),
          bindings: PadInput.addDefaultsTo(DesktopInput.defaultBindings()),
          config: config ?? GameConfig(),
          padConnected: padConnected,
          onVolume: (AudioBus bus, double volume) {},
          onSetting: (String name, double value) {},
          onClose: () {},
          actions: const <GameAction>[GameAction.jump],
          waitingFor: null,
          onRebind: (GameAction? action) {},
          onResetControls: () {},
          credits: const CreditsSection(credits: Credits.models),
        ),
      ),
    );

void main() {
  test('every model the game ships is accounted for', () {
    // **From the directory, not from a list written beside the other list.**
    // The failure this catches is an asset added to the game and to nothing
    // else, which is exactly how the untraced key arrived.
    final shipped = Directory('assets/models')
        .listSync()
        .whereType<File>()
        .map((File f) => 'models/${f.uri.pathSegments.last}')
        .where((String name) => name.endsWith('.glb'))
        .toSet();
    final credited = Credits.models.map((Credit c) => c.file).toSet();

    expect(shipped, isNotEmpty, reason: 'no models found to check');
    expect(credited.difference(shipped), isEmpty,
        reason: 'credited something the game does not ship');
    expect(shipped.difference(credited), isEmpty,
        reason: 'shipped a model nobody is credited for');
  });

  test('nothing this game ships is untraceable any more', () {
    // **This test used to assert the opposite.** `key.glb` came from an archive
    // with no licence file, no readme and no author, and while it was here the
    // game could not be released at all — no amount of looking fixes an asset
    // with no provenance. It was replaced by one this repository generates, so
    // the list is empty and the release blocker is gone.
    //
    // The machinery stays: the next model dropped into `assets/models` is one
    // somebody found somewhere, and the test above reads that directory.
    expect(Credits.untraced, isEmpty,
        reason: 'this game cannot be released while anything is in this list');
  });

  test('and the way of saying so still works', () {
    // Kept because the check above is now an assertion about an empty list, and
    // an empty list passes whatever the code does. This is the half that fails
    // if `untraced` stops meaning anything.
    const found = Credit.untraced(file: 'models/found.glb', work: 'A thing');

    expect(found.traced, isFalse);
    expect(found.line, contains('untraced'));
    expect(found.owesAttribution, isFalse, reason: 'nobody to attribute it to');
  });

  testWidgets('the screen a player can reach names the authors', (
    WidgetTester tester,
  ) async {
    // Through the panel the game actually shows, with the list the game
    // actually holds. A test that built its own widget out of its own strings
    // would pass with the credits deleted from the game.
    await tester.pumpWidget(_panel());

    for (final credit in Credits.owed) {
      expect(find.textContaining(credit.author!), findsWidgets,
          reason: '${credit.work} is CC BY and its author is not on screen');
      expect(find.textContaining(credit.licence!), findsWidgets);
      expect(find.text(credit.licenceUrl!), findsWidgets,
          reason: 'the licence has to be reachable, not just named');
    }
  });

  testWidgets('and the screen lists every model, not only the owed ones', (
    WidgetTester tester,
  ) async {
    // **This used to walk `Credits.untraced`**, which is empty now — so it
    // passed without looking at anything. What it was reaching for is the real
    // obligation: a credits screen listing three of four models reads as a
    // complete one, and the licence is discharged by the whole list.
    await tester.pumpWidget(_panel());

    expect(Credits.models, isNotEmpty);
    for (final credit in Credits.models) {
      expect(find.text(credit.line), findsOneWidget, reason: credit.file);
    }
  });
}
