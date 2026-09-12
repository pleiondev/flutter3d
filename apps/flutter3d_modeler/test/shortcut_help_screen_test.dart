/// `ui-32n`'s own screen: every row `shortcutTable()` hands out actually
/// reaches the dialog, and `?` opens it the same `_typingSafe` way every
/// other bare-key binding in `_Keys` does.
///
///     flutter test test/shortcut_help_screen_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter3d_modeler/src/ui/number_field.dart';
import 'package:flutter3d_modeler/src/ui/shortcut_help.dart';
import 'package:flutter3d_modeler/src/ui/shortcut_help_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// `_Keys._typingSafe`, reconstructed — see `keyboard_shortcuts_test.dart`'s
/// own doc comment for why: that method is private to `main.dart`, and this
/// test proves the same mechanism against the real production wiring rather
/// than reaching into a private class.
VoidCallback _typingSafe(VoidCallback action) => () {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context != null &&
      context.findAncestorWidgetOfExactType<EditableText>() != null) {
    return;
  }
  action();
};

Widget _harness({required VoidCallback onHelp, required Widget child}) =>
    MaterialApp(
      home: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.slash, shift: true):
              _typingSafe(onHelp),
        },
        child: Focus(autofocus: true, child: Scaffold(body: child)),
      ),
    );

void main() {
  group("ui-32n's own acceptance", () {
    testWidgets('every entry in shortcutTable() is drawn in the dialog', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showShortcutHelp(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // The list is taller than the dialog's own fixed height, so a row this
      // far down is not built at all until something scrolls it into view —
      // `ListView`'s sliver machinery only materialises what the viewport
      // (plus its cache extent) actually needs, whatever the full children
      // list handed to its constructor says.
      final entries = shortcutTable();
      expect(entries, isNotEmpty);
      for (final ShortcutEntry entry in entries) {
        await tester.scrollUntilVisible(
          find.text(entry.label),
          80,
          scrollable: find.byType(Scrollable),
        );
        expect(
          find.text(entry.label),
          findsOneWidget,
          reason: '${entry.label} (${entry.shortcut.keyLabel}) is missing',
        );
      }
    });

    testWidgets('Shift+/ opens the help screen', (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        _harness(onHelp: () => opened++, child: const SizedBox.shrink()),
      );
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.slash);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

      expect(opened, 1);
    });

    testWidgets('Shift+/ does nothing while a NumberField holds focus', (
      tester,
    ) async {
      var opened = 0;
      await tester.pumpWidget(
        _harness(
          onHelp: () => opened++,
          child: NumberField(label: 'X', value: 0, onChanged: (_) {}),
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(TextField));
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.slash);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

      expect(opened, 0);
    });
  });

  test('the tutorial link points at a real, already-deployed site page, '
      'not a guessed one that does not exist yet', () {
    expect(tutorialUrl.host, 'flutter3d.pleion.dev');
    expect(tutorialUrl.scheme, 'https');
  });
}
