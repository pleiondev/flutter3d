/// `SectionLabel`: the modeller's own default look with no override, and the
/// two overrides that reproduce `apps/flutter3d_editor`'s own denser
/// headings — `ui-27`'s own P0, the reason `style`/`padding` exist at all.
///
///     flutter test test/section_label_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Text textOf(WidgetTester tester) => tester.widget<Text>(find.byType(Text));
Padding paddingOf(WidgetTester tester) =>
    tester.widget<Padding>(find.byType(Padding));

void main() {
  testWidgets('says the text upper-case, however it arrives', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SectionLabel('shading'))),
    );

    // Mutation: drop the `.toUpperCase()` call. A section heading in this
    // app's own look is always shouted, never whatever case a caller passed.
    expect(find.text('SHADING'), findsOneWidget);
    expect(find.text('shading'), findsNothing);
  });

  testWidgets('with no override, draws the modeller default look', (
    WidgetTester tester,
  ) async {
    final ThemeData theme = ThemeData(
      colorScheme: const ColorScheme.dark(outline: Color(0xFF899295)),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(body: SectionLabel('Shadows')),
      ),
    );

    final Text text = textOf(tester);
    // The design hand-over's own row for "Подписи разделов": 11/400,
    // `letter-spacing: 0.08em` (0.88 logical pixels at this size), coloured
    // `outline` rather than `onSurfaceVariant`.
    expect(text.style?.color, theme.colorScheme.outline);
    expect(text.style?.fontSize, 11);
    expect(text.style?.fontWeight, FontWeight.w400);
    expect(text.style?.letterSpacing, 0.88);
    expect(
      paddingOf(tester).padding,
      const EdgeInsets.only(top: 14, bottom: 6),
    );
  });

  testWidgets(
    'style/padding reproduce the level editor own inspector heading',
    (WidgetTester tester) async {
      // The exact literals `editor_inspector.dart` draws its own panel
      // title with, before `ui-27` — proof this widget can stand in for
      // that file's own `Text` without the level editor keeping a second
      // copy of it.
      const TextStyle inspectorStyle = TextStyle(
        color: Color(0xFF6F7885),
        fontSize: 11,
        letterSpacing: 1.6,
        fontWeight: FontWeight.w700,
      );
      const EdgeInsets inspectorPadding = EdgeInsets.fromLTRB(12, 0, 12, 6);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SectionLabel(
              'lighting',
              style: inspectorStyle,
              padding: inspectorPadding,
            ),
          ),
        ),
      );

      expect(textOf(tester).style, inspectorStyle);
      expect(paddingOf(tester).padding, inspectorPadding);
      expect(find.text('LIGHTING'), findsOneWidget);
    },
  );

  testWidgets(
    "style/padding reproduce the level editor's own material panel heading",
    (WidgetTester tester) async {
      // `material_panel.dart`'s own `_heading`, before `ui-27`.
      const TextStyle materialHeadingStyle = TextStyle(
        color: Color(0xFF525A66),
        fontSize: 10,
        letterSpacing: 1.4,
        fontWeight: FontWeight.w700,
      );
      const EdgeInsets materialHeadingPadding = EdgeInsets.fromLTRB(
        12,
        10,
        12,
        2,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SectionLabel(
              'not set',
              style: materialHeadingStyle,
              padding: materialHeadingPadding,
            ),
          ),
        ),
      );

      expect(textOf(tester).style, materialHeadingStyle);
      expect(paddingOf(tester).padding, materialHeadingPadding);
    },
  );

  testWidgets('is always one line, ellipsised rather than wrapped', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SectionLabel('Environment'))),
    );

    final Text text = textOf(tester);
    // Mutation: drop `maxLines`/`overflow`. Both editors lay a heading out
    // in a column no wider than the panel; a name too long to fit must
    // truncate rather than push every row below it down by a line.
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
  });
}
