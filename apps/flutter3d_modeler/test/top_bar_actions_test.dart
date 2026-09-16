/// The top bar's own right-hand side: adding a primitive, opening, saving,
/// exporting, and the small utility icons.
///
///     flutter test test/top_bar_actions_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_modeler/src/exporting.dart';
import 'package:flutter3d_modeler/src/ui/top_bar_actions.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> show(
  WidgetTester tester, {
  VoidCallback? onSave,
  VoidCallback? onPreview,
  VoidCallback? onImport,
  ValueChanged<String>? onAddPrimitive,
  ValueChanged<ExportFormat>? onExport,
}) {
  // Wide enough to lay out every button this row now holds — `tut-08`'s own
  // "Import" tipped the default 800-pixel test window into an overflow that
  // had nothing to do with what any test here actually checks.
  tester.view.physicalSize = const Size(1000, 600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  return tester.pumpWidget(
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
          onImport: onImport ?? () {},
          onSave: onSave ?? () {},
          onExport: onExport ?? (_) {},
          onMaterialStudio: () {},
          onPreview: onPreview ?? () {},
          onShortcutHelp: () {},
          onStartScreen: () {},
          onReportProblem: () {},
        ),
      ),
    ),
  );
}

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

  testWidgets('tapping Import calls onImport', (WidgetTester tester) async {
    var imports = 0;
    await show(tester, onImport: () => imports++);

    await tester.tap(find.widgetWithText(TextButton, 'Import'));
    await tester.pump();

    expect(imports, 1);
  });

  group(
    "ux-18: the Export menu offers every format, each under its own name",
    () {
      testWidgets('all six are listed, and none of them twice', (
        WidgetTester tester,
      ) async {
        await show(tester);
        await tester.tap(find.text('Export'));
        await tester.pumpAndSettle();

        // `builtInModelWriters` has had STL and USDZ since `fmt-09` and this
        // menu offered three of the six, so the one format somebody with a 3D
        // printer came for was the one they could not choose.
        for (final ExportFormat format in ExportFormat.values) {
          expect(
            find.textContaining(format.label),
            findsWidgets,
            reason: '${format.name} is not on the menu',
          );
        }
        // Binary and ASCII STL share a suffix; `label` is what keeps them
        // apart. Mutation: print `suffix` and this menu shows ".stl" twice
        // with no way to tell which is which.
        expect(find.textContaining('.stl (text)'), findsOneWidget);
      });

      testWidgets('choosing one hands the format on rather than writing it', (
        WidgetTester tester,
      ) async {
        ExportFormat? asked;
        await show(tester, onExport: (ExportFormat it) => asked = it);
        await tester.tap(find.text('Export'));
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('.stl (text)'));
        await tester.pumpAndSettle();

        // The menu names a format and nothing else. What happens next is the
        // one export screen, which is where "bake transforms", "selection
        // only" and every readiness issue are asked about once.
        expect(asked, ExportFormat.stlAscii);
      });
    },
  );
}
