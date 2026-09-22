/// `EditorWidgetsTheme`: the row-level sizing every widget in this package
/// reads, and the fallback that lets one render with no theme opted in.
///
///     flutter test test/editor_widgets_theme_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('defaults', () {
    test('are the numbers ui-27 asks for', () {
      // Mutation: change any one of the four literals. Nothing else in this
      // package checks them against a document, so a drift here is a drift
      // every widget quietly inherits.
      expect(EditorWidgetsTheme.defaults.rowHeight, 32);
      expect(EditorWidgetsTheme.defaults.labelWidth, 96);
      expect(EditorWidgetsTheme.defaults.fieldRadius, 6);
      expect(EditorWidgetsTheme.defaults.thumbnailSize, 26);
    });
  });

  group('of(context)', () {
    testWidgets('falls back to defaults when nothing is registered', (
      WidgetTester tester,
    ) async {
      late EditorWidgetsTheme read;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext context) {
              read = EditorWidgetsTheme.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      // Mutation: throw, or return null, when the extension is absent. A
      // widget from this package dropped into an application that has not
      // opted in must still render sensibly rather than crash.
      expect(read, EditorWidgetsTheme.defaults);
    });

    testWidgets('reads whatever is registered on the ambient ThemeData', (
      WidgetTester tester,
    ) async {
      const EditorWidgetsTheme dense = EditorWidgetsTheme(
        rowHeight: 28,
        labelWidth: 80,
        fieldRadius: 4,
        thumbnailSize: 22,
      );
      late EditorWidgetsTheme read;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const <ThemeExtension<dynamic>>[dense]),
          home: Builder(
            builder: (BuildContext context) {
              read = EditorWidgetsTheme.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(read, dense);
    });
  });

  group('copyWith', () {
    test('changes only the field given', () {
      const EditorWidgetsTheme base = EditorWidgetsTheme.defaults;
      final EditorWidgetsTheme changed = base.copyWith(rowHeight: 28);

      expect(changed.rowHeight, 28);
      expect(changed.labelWidth, base.labelWidth);
      expect(changed.fieldRadius, base.fieldRadius);
      expect(changed.thumbnailSize, base.thumbnailSize);
    });
  });

  group('lerp', () {
    test('at t=0.5 is the midpoint of every field', () {
      const EditorWidgetsTheme a = EditorWidgetsTheme(
        rowHeight: 20,
        labelWidth: 80,
        fieldRadius: 0,
        thumbnailSize: 10,
      );
      const EditorWidgetsTheme b = EditorWidgetsTheme(
        rowHeight: 40,
        labelWidth: 100,
        fieldRadius: 8,
        thumbnailSize: 30,
      );

      final EditorWidgetsTheme mid = a.lerp(b, 0.5);

      expect(mid.rowHeight, 30);
      expect(mid.labelWidth, 90);
      expect(mid.fieldRadius, 4);
      expect(mid.thumbnailSize, 20);
    });

    test('against null returns the same instance', () {
      // Mutation: `lerp(null, t)` reaching for `other.rowHeight` would throw
      // rather than answer — the case `ThemeExtension` itself documents as
      // "the extension is not in both themes being interpolated between".
      const EditorWidgetsTheme theme = EditorWidgetsTheme.defaults;
      expect(theme.lerp(null, 0.5), same(theme));
    });
  });
}
