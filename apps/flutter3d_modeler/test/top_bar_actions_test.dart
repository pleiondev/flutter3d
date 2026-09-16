/// The top bar's own right-hand side: adding a primitive, opening, saving,
/// exporting, and the small utility icons.
///
///     flutter test test/top_bar_actions_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart'
    show AddPrimitive;
import 'package:flutter3d_modeler/src/exporting.dart';
import 'package:flutter3d_modeler/src/play/play_template.dart';
import 'package:flutter3d_modeler/src/ui/top_bar_actions.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> show(
  WidgetTester tester, {
  VoidCallback? onSave,
  VoidCallback? onPreview,
  VoidCallback? onImport,
  ValueChanged<String>? onAddPrimitive,
  ValueChanged<ExportFormat>? onExport,
  bool isDirty = false,
  ValueChanged<PlayTemplate>? onPlay,
  String? playBlocked,
  bool splitViewport = false,
  ValueChanged<bool>? onSplitViewport,
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
          isDirty: isDirty,
          onExport: onExport ?? (_) {},
          onMaterialStudio: () {},
          onPreview: onPreview ?? () {},
          onPlay: onPlay ?? (_) {},
          playBlocked: playBlocked,
          splitViewport: splitViewport,
          onSplitViewport: onSplitViewport,
          onShortcutHelp: () {},
          onStartScreen: () {},
          onReportProblem: () {},
        ),
      ),
    ),
  );
}

void main() {
  group('ux-51: the Play toolbar', () {
    testWidgets('the menu offers every template, and reports the one picked', (
      WidgetTester tester,
    ) async {
      final picked = <PlayTemplate>[];
      await show(tester, onPlay: picked.add);

      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();
      for (final PlayTemplate template in PlayTemplate.values) {
        expect(find.textContaining(template.label), findsOneWidget);
      }

      await tester.tap(find.textContaining(PlayTemplate.prop.label));
      await tester.pumpAndSettle();
      expect(picked, <PlayTemplate>[PlayTemplate.prop]);
    });

    testWidgets('an export error holds it back, in Export\'s own words', (
      WidgetTester tester,
    ) async {
      final picked = <PlayTemplate>[];
      await show(
        tester,
        onPlay: picked.add,
        playBlocked: 'will not export: 1 problem',
      );

      // **Mutation: let Play start regardless.** The document is handed
      // over exactly as an export hands it over, so a project that cannot
      // be exported cannot be played — and it would fail inside the
      // template, where the reason is no longer on screen.
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();
      expect(find.textContaining(PlayTemplate.prop.label), findsNothing);
      expect(picked, isEmpty);

      // And it says why in the sentence Export already says, not a second
      // one written for this button.
      expect(
        find.byTooltip('Play — will not export: 1 problem'),
        findsOneWidget,
      );
    });
  });

  group('ux-38: the split toggle', () {
    testWidgets('is not there for a shell with no layout to remember', (
      WidgetTester tester,
    ) async {
      await show(tester);

      // Null means nowhere to save the answer. **Mutation: draw it anyway.**
      // The button then flips a value nothing keeps, so a person turns the
      // second view on and finds it off again on the next rebuild.
      expect(find.bySemanticsLabel('Split the viewport'), findsNothing);
    });

    testWidgets('and reports the other state when it is', (
      WidgetTester tester,
    ) async {
      final asked = <bool>[];
      await show(tester, onSplitViewport: asked.add);

      await tester.tap(find.bySemanticsLabel('Split the viewport'));
      await tester.pump();
      expect(asked, <bool>[true]);

      await show(tester, splitViewport: true, onSplitViewport: asked.add);
      await tester.tap(find.bySemanticsLabel('Split the viewport'));
      await tester.pump();
      expect(asked, <bool>[true, false]);
    });
  });

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
    // "Box", since `ux-31`: the menu shows the word and answers with the key.
    await tester.tap(find.text('Box').last);
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

  group('ux-31: the Add menu shows words rather than command arguments', () {
    test('every kind the command knows has a label and an icon', () {
      // **`box` is an argument and "Box" is a word.** A primitive added to
      // `AddPrimitive` without an entry here would put the argument back on
      // the menu, which is the state this row found.
      for (final String kind in AddPrimitive.primitiveKinds) {
        expect(
          kPrimitiveLabels[kind],
          isNotNull,
          reason: '$kind has no label for the Add menu',
        );
      }
      expect(kPrimitiveLabels, hasLength(AddPrimitive.primitiveKinds.length));
    });

    test('and none of those labels is the key it stands for', () {
      for (final MapEntry<String, ({IconData icon, String label})> each
          in kPrimitiveLabels.entries) {
        expect(each.value.label, isNot(each.key));
        expect(each.value.label[0], each.value.label[0].toUpperCase());
      }
    });

    testWidgets('the menu prints them, and no lowercase key', (
      WidgetTester tester,
    ) async {
      await show(tester);
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      for (final String kind in AddPrimitive.primitiveKinds) {
        expect(find.text(kPrimitiveLabels[kind]!.label), findsOneWidget);
        // The row's own acceptance, and the mutation it guards: print the
        // kind and this finds it.
        expect(find.text(kind), findsNothing, reason: '$kind is on the menu');
      }
    });

    testWidgets('and choosing one still answers with the kind, not the word', (
      WidgetTester tester,
    ) async {
      String? added;
      await show(tester, onAddPrimitive: (String kind) => added = kind);
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sphere'));
      await tester.pumpAndSettle();

      // The label is for the person; the id is what the command runs on, and
      // an agent passing `sphere` over MCP means the same thing.
      expect(added, 'sphere');
    });
  });

  group(
    'ux-30: the bar says what is true rather than the same thing always',
    () {
      /// What the Save button is actually painted — which is the whole of
      /// the difference between filled and tonal, and the only part of it a
      /// person sees. `FilledButton.tonal` builds a `FilledButton` too, so
      /// the widget type cannot tell them apart.
      Color saveColour(WidgetTester tester) => tester
          .widget<Material>(
            find
                .descendant(
                  of: find.widgetWithText(FilledButton, 'Save'),
                  matching: find.byType(Material),
                )
                .first,
          )
          .color!;

      testWidgets('Save is the loud button only while there is work to save', (
        WidgetTester tester,
      ) async {
        await show(tester);
        final Color clean = saveColour(tester);
        final ColorScheme scheme = Theme.of(
          tester.element(find.text('Save')),
        ).colorScheme;

        await show(tester, isDirty: true);
        final Color dirty = saveColour(tester);

        // **A button that is always the loudest thing on the bar says
        // nothing by being loud.** Mutation: keep one style for both, as
        // this did, and "have I saved this" stops being a question the bar
        // can answer without being pressed.
        expect(dirty, scheme.primary);
        expect(clean, scheme.secondaryContainer);
      });

      testWidgets("and its tooltip says which of the two states it is in", (
        WidgetTester tester,
      ) async {
        await show(tester);
        expect(find.byTooltip('Save — everything is written'), findsOneWidget);

        await show(tester, isDirty: true);
        expect(
          find.byTooltip('Save — there are unsaved changes'),
          findsOneWidget,
        );
      });

      testWidgets('Open and Import each say which of them loses the scene', (
        WidgetTester tester,
      ) async {
        await show(tester);

        // Two buttons a word apart doing opposite things: the review watched
        // somebody press Open meaning Import and lose what they had built.
        expect(
          find.byTooltip('Open a file — replaces everything that is open now'),
          findsOneWidget,
        );
        expect(
          find.byTooltip(
            'Import a file — brings it in beside what is already open',
          ),
          findsOneWidget,
        );
      });
    },
  );

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
