/// The first thing a player reads, and whether it is true.
///
///     flutter test test/title_card_test.dart
///
/// **Every line on this card was wrong in some build.** They were a `const`
/// list: it said "click to dash" in a browser, where clicking turns the camera
/// and `Q` dashes; it promised that Escape opens the settings, which nothing
/// did; and once the game grew a controller it said nothing about one. A list of
/// what the controls are, written beside the controls and checked by nothing,
/// goes stale the first time either changes — and it is the one text in the game
/// a player is guaranteed to read.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platformer/src/title_card.dart';

Widget _card({required bool dashOnPointer, bool touch = false}) => MaterialApp(
      home: TitleCard(
        prompt: 'Click to begin.',
        dashOnPointer: dashOnPointer,
        touch: touch,
      ),
    );

void main() {
  testWidgets('the desktop build dashes with the mouse', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_card(dashOnPointer: true));

    expect(find.textContaining('click to dash'), findsOneWidget);
    expect(find.textContaining('Q to dash'), findsNothing);
  });

  testWidgets('and the web build dashes with a key, because clicking looks', (
    WidgetTester tester,
  ) async {
    // The line this test exists for. In a browser there is no pointer to
    // capture, so a drag turns the camera — and a drag that also dashed would
    // spend a dash on every turn of the head.
    await tester.pumpWidget(_card(dashOnPointer: false));

    expect(find.textContaining('Q to dash'), findsOneWidget);
    expect(find.textContaining('click to dash'), findsNothing);
  });

  testWidgets('Escape is described as what it now does', (
    WidgetTester tester,
  ) async {
    // It promised the settings and only released the mouse. Both halves happen
    // now, and on the web there is no mouse to give back.
    await tester.pumpWidget(_card(dashOnPointer: true));
    expect(
      find.text('Escape gives the mouse back and opens the settings.'),
      findsOneWidget,
    );

    await tester.pumpWidget(_card(dashOnPointer: false));
    expect(find.text('Escape opens the settings.'), findsOneWidget);
  });

  testWidgets('and a phone is told about none of the keys', (
    WidgetTester tester,
  ) async {
    // **The same failure in a new shape.** A card that recited `W A S D` and
    // Escape to somebody holding a phone would be a screen of nonsense, and it
    // is the first screen they see. What a finger has instead is a stick, three
    // buttons and a drag.
    await tester.pumpWidget(_card(dashOnPointer: false, touch: true));

    expect(find.textContaining('W A S D'), findsNothing);
    expect(find.textContaining('Escape'), findsNothing);
    expect(find.textContaining('stick walks'), findsOneWidget);
    expect(find.textContaining('Drag anywhere else'), findsOneWidget);
  });

  testWidgets('and the controller is mentioned by position, not by label', (
    WidgetTester tester,
  ) async {
    // The game cannot know whether the pad in the player's hands calls its lower
    // face button `A` or Cross, and deliberately does not try to find out — so
    // the card must not print a label it would be guessing at.
    await tester.pumpWidget(_card(dashOnPointer: true));

    expect(find.textContaining('controller'), findsOneWidget);
    expect(find.textContaining('lower face button'), findsOneWidget);
  });
}
