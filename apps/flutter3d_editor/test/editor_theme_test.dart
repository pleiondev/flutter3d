/// `kEditorScheme`/`editorTheme()`, held to the five hexes `src/editor_theme.dart`
/// says it comes from, and to actually reaching a widget's `BuildContext`.
///
///     flutter test test/editor_theme_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_editor/src/editor_theme.dart';
import 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('kEditorScheme matches the five literals it was built from', () {
    // Mutation: change any one of these five. Nothing else here checks them
    // against a document, so a drift would otherwise be silent — the same
    // guard `apps/flutter3d_modeler/test/theme_test.dart` already keeps for
    // its own scheme.
    test('primary — the one warm accent', () {
      expect(kEditorScheme.primary, const Color(0xFFD98F4A));
    });

    test('surface — a dialog\'s own background', () {
      expect(kEditorScheme.surface, const Color(0xFF15181D));
    });

    test(
      'surfaceContainerHighest — a text field\'s fill, a dropdown\'s menu',
      () {
        expect(kEditorScheme.surfaceContainerHighest, const Color(0xFF171A1F));
      },
    );

    test('onSurfaceVariant — a row\'s own label', () {
      expect(kEditorScheme.onSurfaceVariant, const Color(0xFF8A93A0));
    });

    test('outline — the ring around a colour swatch', () {
      expect(kEditorScheme.outline, const Color(0xFF2A2F37));
    });
  });

  test('the scaffold background tracks surface, not a hand-copied tone', () {
    final theme = editorTheme();
    expect(theme.scaffoldBackgroundColor, kEditorScheme.surface);
  });

  test('editorTheme registers the editor\'s own denser row height', () {
    final theme = editorTheme();
    final sizes = theme.extension<EditorWidgetsTheme>();

    expect(sizes, isNotNull);
    expect(sizes!.rowHeight, 28);
    // Every other size is the package's own default — the editor has not
    // asked for a different one of those.
    expect(sizes.labelWidth, EditorWidgetsTheme.defaults.labelWidth);
    expect(sizes.fieldRadius, EditorWidgetsTheme.defaults.fieldRadius);
    expect(sizes.thumbnailSize, EditorWidgetsTheme.defaults.thumbnailSize);
  });

  testWidgets(
    'a widget built under editorTheme() actually resolves the dark scheme, '
    'not MaterialApp\'s own light default',
    (WidgetTester tester) async {
      late ColorScheme resolvedScheme;
      late EditorWidgetsTheme resolvedSizes;

      await tester.pumpWidget(
        MaterialApp(
          theme: editorTheme(),
          home: Builder(
            builder: (BuildContext context) {
              resolvedScheme = Theme.of(context).colorScheme;
              resolvedSizes = EditorWidgetsTheme.of(context);
              return const Scaffold(body: SizedBox.shrink());
            },
          ),
        ),
      );

      // This is the fix E1 is for: every M3 control the editor draws with
      // no colour of its own — `TextField`, `AlertDialog`, `DropdownButton`'s
      // own menu surface — reads exactly this `ColorScheme` off `Theme.of`,
      // rather than falling back to `ThemeData`'s bare light default.
      expect(resolvedScheme, kEditorScheme);
      expect(resolvedSizes.rowHeight, 28);
    },
  );
}
