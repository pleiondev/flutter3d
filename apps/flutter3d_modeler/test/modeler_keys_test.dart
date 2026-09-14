/// The keyboard, over the whole shell — `ModelerKeys`'s own two, mutually
/// exclusive jobs, picked by where the keyboard focus already is: the outer
/// `Focus`'s own `onKey` answers for every key while nothing else in the
/// shell holds focus (a modal transform's own case, since a drag never
/// clicks a text field), and `CallbackShortcuts`'s bindings — undo, redo,
/// export, the tools — answer once something below it does.
///
///     flutter test test/modeler_keys_test.dart
///
/// The tool-shortcut and typing-safety mechanism this widget also carries is
/// `keyboard_shortcuts_test.dart`'s own ground, reconstructed there before
/// this class was public; this file sticks to what only `ModelerKeys` itself
/// does — the two paths above and which of them a given focus reaches.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter3d_modeler/src/ui/modeler_keys.dart';
import 'package:flutter3d_modeler/src/ui/tools.dart';
import 'package:flutter_test/flutter_test.dart';

/// A held document with nothing yet focused: `CallbackShortcuts` (inside
/// `ModelerKeys`) only ever sees a key once one of its own descendants holds
/// focus — its own doc says so — and `ModelerKeys`'s own outer `Focus` wins
/// autofocus over anything below it, exactly so a transform in progress gets
/// first look at a key. [contentFocus] is the focus a click on the shell
/// would ordinarily leave behind; each test moves it there explicitly rather
/// than racing it against the outer `Focus`'s own autofocus.
Future<void> show(
  WidgetTester tester, {
  required FocusNode contentFocus,
  required VoidCallback onUndo,
  required VoidCallback onExport,
  bool Function(LogicalKeyboardKey, String?)? onKey,
}) => tester.pumpWidget(
  MaterialApp(
    // Forced rather than left to the host: `apple` inside `ModelerKeys`
    // reads `Theme.of(context).platform`, and a test that let it fall back
    // to `defaultTargetPlatform` would pass on a Mac and fail in CI, or the
    // other way round, depending only on where it happened to run.
    theme: ThemeData(platform: TargetPlatform.linux),
    home: ModelerKeys(
      onKey: onKey ?? (_, _) => false,
      onUndo: onUndo,
      onRedo: () {},
      onExport: onExport,
      onTool: (_) {},
      onLevel: (_) {},
      onSelectAll: () {},
      onSelectNone: () {},
      onInvertSelection: () {},
      onShortcutHelp: () {},
      tools: toolsFor(ModelerMode.object),
      child: Scaffold(
        body: Focus(focusNode: contentFocus, child: const SizedBox.shrink()),
      ),
    ),
  ),
);

void main() {
  testWidgets('Ctrl+Z calls onUndo, once something in the shell holds focus', (
    WidgetTester tester,
  ) async {
    var undone = 0;
    final contentFocus = FocusNode();
    addTearDown(contentFocus.dispose);
    await show(
      tester,
      contentFocus: contentFocus,
      onUndo: () => undone++,
      onExport: () {},
    );
    contentFocus.requestFocus();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(undone, 1);
  });

  testWidgets('onKey sees a key when nothing else in the shell holds focus', (
    WidgetTester tester,
  ) async {
    // Left unfocused on purpose: this is the state a modal transform runs
    // in — nothing has stolen focus away from `ModelerKeys`'s own outer,
    // autofocused `Focus`, so it alone answers for every key, exactly the
    // "sees keys before they mean what they usually mean" the doc names.
    LogicalKeyboardKey? seen;
    final contentFocus = FocusNode();
    addTearDown(contentFocus.dispose);
    await show(
      tester,
      contentFocus: contentFocus,
      onUndo: () {},
      onExport: () {},
      onKey: (LogicalKeyboardKey key, String? _) {
        seen = key;
        return true;
      },
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await tester.pump();

    // Mutation: build the outer `Focus` without `autofocus: true`, which
    // would leave nothing focused at all and `onKey` never called.
    expect(seen, LogicalKeyboardKey.keyX);
  });
}
