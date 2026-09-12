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
