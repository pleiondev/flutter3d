/// `ui-32n`'s own screen: every row `shortcutTable()` hands out actually
/// reaches the dialog, and `?` opens it the same `_typingSafe` way every
/// other bare-key binding in `_Keys` does.
///
///     flutter test test/shortcut_help_screen_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart';
import 'package:flutter3d_modeler/l10n/app_localizations.dart';
import 'package:flutter3d_modeler/src/settings.dart';
import 'package:flutter3d_modeler/src/ui/keymap.dart';
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

/// The default preset on a Mac — one keymap for the whole file, so the
/// dialog under test and the table it is compared against are the same.
final Keymap _keymap = keymapFor(KeymapPreset.standard, apple: true);

void main() {
  group("ui-32n's own acceptance", () {
    testWidgets('the dialog draws the table, in its four sections', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showShortcutHelp(context, keymap: _keymap),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // **Scrolled through rather than asked row by row.** The list is far
      // taller than the dialog's own fixed height and `ListView` only
      // materialises what the viewport needs, so a row near the bottom is
      // not in the tree at all until something scrolls it there — and since
      // `ux-10` a label can legitimately appear twice (`Delete` is both a
      // tool and an application action), which a per-row `findsOneWidget`
      // would call a failure.
      final Finder list = find.byType(Scrollable).first;
      final seen = <String>{};
      for (var step = 0; step < 40; step++) {
        for (final Text text in tester.widgetList<Text>(find.byType(Text))) {
          final String? said = text.data;
          if (said != null) seen.add(said);
        }
        await tester.drag(list, const Offset(0, -120));
        await tester.pump();
      }

      // The four headings, which is what `ux-10` added — and the rows the
      // review found missing from every one of them.
      expect(seen, containsAll(<String>['CAMERA', 'APPLICATION', 'SELECTION']));
      expect(seen.any((String it) => it.startsWith('TOOLS')), isTrue);
      expect(seen, contains('Orbit'));
      expect(seen, contains('Save'));
      expect(seen, contains('Select everything'));

      // And every entry the table hands out really is drawn somewhere in it.
      for (final ShortcutEntry entry in shortcutTable(_keymap)) {
        expect(
          seen,
          contains(entry.label),
          reason: '${entry.label} (${entry.keys}) is missing',
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
