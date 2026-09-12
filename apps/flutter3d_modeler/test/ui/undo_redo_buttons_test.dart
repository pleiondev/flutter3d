/// `UndoRedoButtons`: the tooltip that says what undo would actually do —
/// `ui-11`'s own row.
///
///     flutter test test/ui/undo_redo_buttons_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_modeler/src/ui/undo_redo_buttons.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> show(
  WidgetTester tester, {
  bool canUndo = false,
  bool canRedo = false,
  String? undoSays,
  String? redoSays,
  VoidCallback? onUndo,
  VoidCallback? onRedo,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: UndoRedoButtons(
        canUndo: canUndo,
        canRedo: canRedo,
        undoSays: undoSays,
        redoSays: redoSays,
        onUndo: onUndo ?? () {},
        onRedo: onRedo ?? () {},
      ),
    ),
  ),
);

void main() {
  testWidgets('an empty stack shows a neutral tooltip and a disabled button', (
    WidgetTester tester,
  ) async {
    await show(tester);

    final undo = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.undo),
    );
    expect(undo.onPressed, isNull, reason: 'nothing to undo yet');

    await tester.longPress(find.byIcon(Icons.undo));
    await tester.pumpAndSettle();
    expect(find.text('nothing to undo'), findsOneWidget);
  });

  testWidgets("the tooltip says what undo would take back, by name", (
    WidgetTester tester,
  ) async {
    await show(tester, canUndo: true, undoSays: 'move');

    final undo = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.undo),
    );
    expect(undo.onPressed, isNotNull);

    await tester.longPress(find.byIcon(Icons.undo));
    await tester.pumpAndSettle();
    expect(find.text('undo move'), findsOneWidget);
  });

  testWidgets('redo mirrors undo: text, enabling and the callback', (
    WidgetTester tester,
  ) async {
    var redone = false;
    await show(
      tester,
      canRedo: true,
      redoSays: 'extrude',
      onRedo: () => redone = true,
    );

    await tester.longPress(find.byIcon(Icons.redo));
    await tester.pumpAndSettle();
    expect(find.text('redo extrude'), findsOneWidget);

    // The tooltip's own overlay sits on top of the button now; tap the
    // button directly by its own finder rather than through the tooltip.
    await tester.tapAt(tester.getCenter(find.byIcon(Icons.redo)));
    expect(redone, isTrue);
  });

  testWidgets('tapping undo calls onUndo, not onRedo', (
    WidgetTester tester,
  ) async {
    var undone = false;
    var redone = false;
    await show(
      tester,
      canUndo: true,
      canRedo: true,
      onUndo: () => undone = true,
      onRedo: () => redone = true,
    );

    await tester.tap(find.byIcon(Icons.undo));
    expect(undone, isTrue);
    expect(redone, isFalse);
  });
}
