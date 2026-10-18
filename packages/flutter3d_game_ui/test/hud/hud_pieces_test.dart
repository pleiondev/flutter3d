/// The panel, its lines, the tallies, the banner and the speedometer.
///
///     flutter test test/hud_pieces_test.dart
///
/// Each piece takes values and draws them; these check that what a player is
/// told is what was handed in, that an empty panel leaves nothing behind,
/// and that a screen reader hears a tally as one thing.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_game_ui/hud.dart';
import 'package:flutter3d_game_ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  testWidgets('an empty panel draws nothing', (WidgetTester tester) async {
    await _pump(tester, const HudPanel(children: <Widget>[]));
    // Mutation: drop the `children.isEmpty` guard — an empty dark box
    // appears.
    expect(
      find.descendant(
        of: find.byType(HudPanel),
        matching: find.byType(Container),
      ),
      findsNothing,
    );
  });

  testWidgets('a line is its label and value, in the accent when it is one', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      const HudPanel(
        children: <Widget>[
          HudLine(label: 'BEST', value: '0:41.250'),
          HudLine(label: 'RECORD!', value: '0:39.000', accent: true),
        ],
      ),
    );
    expect(find.text('BEST'), findsOneWidget);
    expect(find.text('0:41.250'), findsOneWidget);
    final plain = tester.widget<Text>(find.text('0:41.250'));
    final accent = tester.widget<Text>(find.text('0:39.000'));
    expect(plain.style!.color, Colors.white);
    // Mutation: colour an accent line like any other — this fails.
    expect(accent.style!.color, GameUiTheme.fallback.accent);
  });

  testWidgets('a tally is read as one thing', (WidgetTester tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, const HudTally(label: 'coins', value: '12'));
    // Mutation: drop `excludeSemantics` — the reader hears `12` and `coins`
    // as two nodes, and this label is not found.
    expect(find.bySemanticsLabel('coins 12'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('a tally takes its style', (WidgetTester tester) async {
    const ink = Color(0xFFE8ECF4);
    await _pump(
      tester,
      const HudTally(
        label: 'stock',
        value: '137',
        style: HudTallyStyle(color: ink, valueSize: 24, tabular: true),
      ),
    );
    final value = tester.widget<Text>(find.text('137'));
    expect(value.style!.color, ink);
    expect(value.style!.fontSize, 24);
    // Mutation: ignore `tabular` — the figures go proportional.
    expect(value.style!.fontFeatures, const <FontFeature>[
      FontFeature.tabularFigures(),
    ]);
  });

  testWidgets('a banner says its sentence', (WidgetTester tester) async {
    await _pump(tester, const HudBanner('Click to play', fontSize: 22));
    final text = tester.widget<Text>(find.text('Click to play'));
    expect(text.style!.fontSize, 22);
  });

  test('the speedometer reads kilometres an hour', () {
    // Mutation: show metres a second — 25 rather than 90.
    expect(Speedometer.kphOf(25.0), 90);
    expect(Speedometer.kphOf(0.0), 0);
  });

  testWidgets('the speedometer shows the rounded figure', (
    WidgetTester tester,
  ) async {
    await _pump(tester, const Speedometer(metersPerSecond: 24.0));
    expect(find.text('86'), findsOneWidget);
    expect(find.text('km/h'), findsOneWidget);
  });
}
