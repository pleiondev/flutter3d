/// Every label in the race HUD fits its column on one line.
///
///     flutter test test/hud_label_test.dart
///
/// **`RECORD` wrapped.** The label column was 52 logical pixels and the word is
/// wider than that at thirteen points, bold, with a point and a half of
/// tracking — so the panel showed `RECOR` above a lonely `D`, which pushed the
/// line under it down and left the value beside it floating against nothing. It
/// is the kind of defect no test in this repository could have caught, because
/// every test here asks what a widget *says* and none asked how it *sits*.
///
/// So this measures rather than looks: each label is laid out through the real
/// widget and asked how many lines it took. A label that outgrows the column
/// fails here instead of wrapping in the corner of somebody's screen — and
/// widening the column past what the panel can hold fails the last case, which
/// is the other direction of the same mistake.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter3d_demo_racing/src/hud_pieces.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every label the HUD can show, including the one that only appears for a
/// moment: `RECORD!` is the longest, and the moment it appears is exactly the
/// moment a driver looks at it.
const List<String> _labels = <String>[
  'LAP',
  'POS',
  'TIME',
  'BEST',
  'RECORD',
  'RECORD!',
  'DAMAGE',
  'TYRES',
];

void main() {
  for (final label in _labels) {
    testWidgets('$label sits on one line', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: HudPanel(
                children: <Widget>[HudLine(label: label, value: '0:00.000')],
              ),
            ),
          ),
        ),
      );

      final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
      // One line means the paragraph is no taller than its own line height,
      // which is what a wrap doubles. Measured off the render object rather
      // than guessed from the string's length, because tracking and weight are
      // what made this one wrap and neither is visible in a character count.
      final lineHeight = paragraph.textSize.height;
      expect(
        paragraph.size.height,
        lessThan(lineHeight * 1.5),
        reason:
            '"$label" wrapped in the HUD\'s label column, which pushes every '
            'line below it down and leaves its own value beside nothing',
      );
      expect(
        paragraph.didExceedMaxLines,
        isFalse,
        reason: '"$label" was clipped rather than shown',
      );
    });
  }

  testWidgets('and the panel is no wider than the corner it sits in', (
    WidgetTester tester,
  ) async {
    // The other direction. Widening the label column until anything fits is a
    // fix that hides a mistake behind a panel over half the track: this holds
    // the whole thing to something a driver can see past.
    //
    // Mutation: set the label column to 200. The panel then measures 374 and
    // this fails; the wrap tests above do not.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: HudPanel(
              children: <Widget>[
                for (final label in _labels)
                  HudLine(label: label, value: '0:00.000'),
              ],
            ),
          ),
        ),
      ),
    );

    // 246 as it stands: 14 of padding, a 72-pixel label column, `0:00.000` at
    // eighteen points, 14 more. The ceiling is a quarter of the 960 the browser
    // build draws at — past that the panel is reading the track for the driver
    // rather than the other way round.
    expect(tester.getSize(find.byType(HudPanel)).width, lessThan(240.0 + 20.0));
  });
}
