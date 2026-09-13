/// `ui-12`'s own row: `E` with a mesh tool armed starts extrude; the same
/// key typed into a focused `NumberField` enters the character instead.
///
/// **Why this does not pump `_ModelerScreenState`.** `_Keys` (`main.dart`) is
/// library-private and nothing in this app's own test suite pumps the whole
/// screen — every other test here exercises one `src/` piece at a time. This
/// test reconstructs `_Keys`'s own one-line binding rule —
/// `for (tool in tools) SingleActivator(tool.shortcut): () => onTool(tool.id)`
/// — over `toolsFor(ModelerMode.mesh)`, the real production tool table, so it
/// proves the actual mechanism `_Keys` relies on rather than a stand-in.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter3d_modeler/src/ui/number_field.dart';
import 'package:flutter3d_modeler/src/ui/tools.dart';
import 'package:flutter_test/flutter_test.dart';

/// The same guard `_Keys._typingSafe` applies in `main.dart` — reconstructed
/// here because that method is private to that library. A letter or digit
/// shortcut must not fire while a text field holds the keyboard focus, since
/// Flutter delivers the character to the field through the text-input
/// channel, a path the raw key event this binding sees does not go through.
VoidCallback _typingSafe(VoidCallback action) => () {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context != null &&
      context.findAncestorWidgetOfExactType<EditableText>() != null) {
    return;
  }
  action();
};

Widget _harness({required VoidCallback onExtrude, required Widget child}) {
  final tools = toolsFor(ModelerMode.mesh);
  return MaterialApp(
    home: CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        for (final ModelerTool tool in tools)
          SingleActivator(tool.shortcut): _typingSafe(() {
            if (tool.id == 'mesh.extrude') onExtrude();
          }),
      },
      child: Focus(autofocus: true, child: Scaffold(body: child)),
    ),
  );
}

void main() {
  group("ui-12's own acceptance", () {
    testWidgets('E with the mesh tool table armed starts extrude', (
      tester,
    ) async {
      var extrudeStarted = 0;
      await tester.pumpWidget(
        _harness(
          onExtrude: () => extrudeStarted++,
          child: const SizedBox.shrink(),
        ),
      );
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
      await tester.pump();

      expect(extrudeStarted, 1);
    });

    testWidgets(
      'E does not arm a tool while a NumberField holds focus, and the field '
      'stays a normal, working field',
      (tester) async {
        var extrudeStarted = 0;
        var reported = 0.0;
        await tester.pumpWidget(
          _harness(
            onExtrude: () => extrudeStarted++,
            child: NumberField(
              label: 'X',
              value: 0,
              onChanged: (double to) => reported = to,
            ),
          ),
        );
        await tester.pump();

        await tester.tap(find.byType(TextField));
        await tester.pump();
        expect(
          tester.testTextInput.isVisible,
          isTrue,
          reason:
              'the field must actually hold focus for this test to mean anything',
        );

        // The raw key event is what `_typingSafe` guards against — Flutter
        // delivers the actual character to a focused field through the
        // text-input channel, a separate path `enterText` below exercises;
        // this line only proves the shortcut itself backs off.
        await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
        await tester.pump();
        expect(
          extrudeStarted,
          0,
          reason: 'the tool shortcut must not fire while this field is focused',
        );

        // And the field is not somehow left broken by the guard: it still
        // takes ordinary input and reports a real value once one parses.
        await tester.enterText(find.byType(TextField), '1.5');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        expect(reported, 1.5);
      },
    );
  });
}
