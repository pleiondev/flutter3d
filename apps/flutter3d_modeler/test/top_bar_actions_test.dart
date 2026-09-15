/// The top bar's own right-hand side: adding a primitive, opening, saving,
/// exporting, and the small utility icons.
///
///     flutter test test/top_bar_actions_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_modeler/src/ui/top_bar_actions.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> show(
  WidgetTester tester, {
  VoidCallback? onSave,
  VoidCallback? onPreview,
  ValueChanged<String>? onAddPrimitive,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: TopBarActions(
        canUndo: false,
        canRedo: false,
        undoSays: null,
        redoSays: null,
        onUndo: () {},
        onRedo: () {},
        onAddPrimitive: onAddPrimitive ?? (_) {},
        onOpen: () {},
        onSave: onSave ?? () {},
        onExport: (_) {},
        onMaterialStudio: () {},
        onPreview: onPreview ?? () {},
        onShortcutHelp: () {},
        onStartScreen: () {},
        onReportProblem: () {},
      ),
    ),
  ),
);

void main() {
  testWidgets('tapping Save calls onSave', (WidgetTester tester) async {
    var saves = 0;
    await show(tester, onSave: () => saves++);

    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(saves, 1);
  });

  testWidgets('picking a primitive from the Add menu calls onAddPrimitive '
      "with the kind's own name", (WidgetTester tester) async {
    String? added;
    await show(tester, onAddPrimitive: (String kind) => added = kind);

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('box').last);
    await tester.pumpAndSettle();

    // Mutation: hand the menu `AddPrimitive` itself rather than a callback
    // fed its `kind`, which would make this widget reach into the document
    // instead of only ever rendering.
    expect(added, 'box');
  });

  testWidgets('tapping Preview calls onPreview', (WidgetTester tester) async {
    var previews = 0;
    await show(tester, onPreview: () => previews++);

    await tester.tap(
      find.byTooltip('Preview — see it the way the game would draw it'),
    );
    await tester.pump();

    expect(previews, 1);
  });
}
