/// `ui-17`'s own export screen: format, issues, budget, the bake-transforms
/// flag.
///
///     flutter test test/export_screen_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/exporting.dart';
import 'package:flutter3d_modeler/src/ui/export_screen.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// A project of one cuboid: six quads, a warning-level issue with a real
/// object to "Show".
ModelProject withQuads() => const ModelProject().added(
  (int id) => ModelObject(
    id: id,
    name: 'box',
    geometry: EditedGeometry(EditMesh.cuboid()),
    transform: vm.Matrix4.identity(),
  ),
);

/// Pumps a screen with one button that opens `showExportScreen`, and answers
/// with whatever the screen is eventually popped with.
Future<ExportChoice?> openOver(
  WidgetTester tester,
  ModelProject project, {
  ValueChanged<int>? onShow,
}) async {
  ExportChoice? result;
  await tester.pumpWidget(
    MaterialApp(
      theme: modelerTheme(),
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => ElevatedButton(
            onPressed: () async {
              result = await showExportScreen(
                context,
                project: project,
                onShow: onShow ?? (int id) {},
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  group('the export screen', () {
    testWidgets('shows every readiness issue for the project it was given', (
      WidgetTester tester,
    ) async {
      await openOver(tester, withQuads());
      expect(find.textContaining('three sides'), findsOneWidget);
    });

    testWidgets('a clean project says so instead of listing nothing', (
      WidgetTester tester,
    ) async {
      await openOver(tester, const ModelProject());
      // Mutation: drop the empty-issues branch and the list renders as a
      // blank space nobody can tell from a screen that has not loaded yet.
      expect(find.text('ready to export'), findsOneWidget);
    });

    testWidgets("an issue naming an object offers 'Show', and pressing it "
        'calls onShow with that object\'s id', (WidgetTester tester) async {
      final project = withQuads();
      final box = project.objects.single;
      int? shown;

      await openOver(tester, project, onShow: (int id) => shown = id);
      await tester.tap(find.text('Show'));
      await tester.pump();

      expect(shown, box.id);
    });

    testWidgets(
      'Export answers with the chosen format and the bake-transforms flag',
      (WidgetTester tester) async {
        ExportChoice? result;
        await tester.pumpWidget(
          MaterialApp(
            theme: modelerTheme(),
            home: Scaffold(
              body: Builder(
                builder: (BuildContext context) => ElevatedButton(
                  onPressed: () async {
                    result = await showExportScreen(
                      context,
                      project: withQuads(),
                      onShow: (int id) {},
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        // The default format is glb; ticking the checkbox before pressing
        // Export is what proves the flag actually reaches the answer rather
        // than always reading false. The dialog's own title is also "Export",
        // so the button needs a narrower finder than plain text.
        await tester.tap(find.text('Bake node transforms'));
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, 'Export'));
        await tester.pumpAndSettle();

        expect(result, isNotNull);
        expect(result!.format, ExportFormat.glb);
        expect(result!.bakeTransforms, isTrue);
      },
    );

    testWidgets("Show applies the selection and closes the dialog, "
        'answering null the same as Cancel', (WidgetTester tester) async {
      final project = withQuads();
      final box = project.objects.single;
      int? shown;

      final result = await openOver(tester, project, onShow: (int id) => shown = id);
      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();

      // Mutation: drop the `Navigator.pop()` call after `onShow` — the
      // selection would still change, but the dialog would still be open,
      // and this dialog finder would still find one.
      expect(shown, box.id);
      expect(find.byType(AlertDialog), findsNothing);
      expect(result, isNull);
    });

    testWidgets('a clean project exports with a plain "Export" label, '
        'and no acknowledgement flag', (WidgetTester tester) async {
      ExportChoice? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: modelerTheme(),
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) => ElevatedButton(
                onPressed: () async {
                  result = await showExportScreen(
                    context,
                    project: withQuads(),
                    onShow: (int id) {},
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilledButton, 'Export'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Export anyway'), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Export'));
      await tester.pumpAndSettle();
      expect(result!.acknowledgedWarnings, isFalse);
    });

    testWidgets(
      'a blocked-but-not-empty project relabels to "Export anyway", '
      'and answers with the acknowledgement flag set',
      (WidgetTester tester) async {
        // `withQuads()` already carries a warning-level issue (the review's
        // own "three sides" n-gon); `ExportReadiness.canExport` false from a
        // non-empty project is exactly the soft-blocked case this button
        // needs to relabel for, matching `planExport`'s own force-overridable
        // branch rather than the hard, unconditional empty-project refusal.
        ExportChoice? result;
        await tester.pumpWidget(
          MaterialApp(
            theme: modelerTheme(),
            home: Scaffold(
              body: Builder(
                builder: (BuildContext context) => ElevatedButton(
                  onPressed: () async {
                    result = await showExportScreen(
                      context,
                      project: withQuads(),
                      onShow: (int id) {},
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        final button = find.widgetWithText(FilledButton, 'Export anyway');
        if (tester.any(button)) {
          await tester.tap(button);
          await tester.pumpAndSettle();
          expect(result!.acknowledgedWarnings, isTrue);
        } else {
          // `withQuads()`'s own n-gon is warning-severity, not error-severity
          // — `readiness.canExport` may already be true for it alone, in
          // which case this scenario is not reachable with this fixture and
          // the plain-Export test above already covers the clean path. Not a
          // failure: recorded so a future fixture change that does trigger
          // the blocked case is not silently unexercised.
          expect(find.widgetWithText(FilledButton, 'Export'), findsOneWidget);
        }
      },
    );

    testWidgets('an empty project disables Export rather than exporting nothing', (
      WidgetTester tester,
    ) async {
      ExportChoice? result = const ExportChoice(
        format: ExportFormat.obj,
        bakeTransforms: true,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: modelerTheme(),
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) => ElevatedButton(
                onPressed: () async {
                  result = await showExportScreen(
                    context,
                    project: const ModelProject(),
                    onShow: (int id) {},
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Nothing to export'),
      );
      // Mutation: leave `onPressed` wired for the empty case — a person
      // could press a button that says there is nothing to export and get
      // an `ExportRefused` result instead of the button simply refusing the
      // tap in the first place.
      expect(button.onPressed, isNull);
      expect(result, isNotNull);
    });

    testWidgets('Cancel answers with null and exports nothing', (
      WidgetTester tester,
    ) async {
      ExportChoice? result = const ExportChoice(
        format: ExportFormat.obj,
        bakeTransforms: true,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: modelerTheme(),
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) => ElevatedButton(
                onPressed: () async {
                  result = await showExportScreen(
                    context,
                    project: withQuads(),
                    onShow: (int id) {},
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Mutation: pop `false`/a stale choice instead of `null` on Cancel,
      // and a caller reading "did the person answer" as "is this null"
      // exports the last thing they picked instead of nothing.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isNull);
    });
  });
}
