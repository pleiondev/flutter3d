/// `showImportScreen`: `ui-16`'s own screen, over an already-decoded
/// document.
///
///     flutter test test/import_screen_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_geometry/flutter3d_geometry.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/import_plan.dart';
import 'package:flutter3d_modeler/src/ui/import_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

final Finder _importButton = find.widgetWithText(FilledButton, 'Import');
final Finder _cancelButton = find.widgetWithText(TextButton, 'Cancel');

ModelDocument _documentWithCuboid(
  Vector3 size, {
  List<String> warnings = const <String>[],
}) {
  final mesh = CuboidShape(size: size).build();
  return PlainModelDocument(
    surfaces: <ModelSurface>[ModelSurface(mesh: mesh)],
    warnings: warnings,
  );
}

/// Pumps a screen with one button that opens [showImportScreen], taps it
/// open, runs [interact] against the now-visible dialog, then settles and
/// hands back whatever [showImportScreen] was eventually popped with.
///
/// `showDialog` cannot be called directly from a widget's own `build`, so —
/// same shape `export_screen_test.dart`'s own `openOver` already
/// established for the sibling export screen — this opens it from a
/// button's `onPressed` instead. A surface bigger than the default test
/// window keeps every row, including the last checkbox, inside the
/// dialog's own hit-testable area.
Future<ImportChoice?> openOver(
  WidgetTester tester,
  ModelDocument document, {
  ProjectProfile profile = const ProjectProfile(),
  Future<void> Function()? interact,
}) async {
  ImportChoice? result;
  await tester.binding.setSurfaceSize(const Size(800, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => ElevatedButton(
            onPressed: () async {
              result = await showImportScreen(
                context,
                document: document,
                profile: profile,
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
  if (interact != null) await interact();
  await tester.pumpAndSettle();
  return result;
}

void main() {
  group('the import screen', () {
    testWidgets('shows the warning count from the decoded document', (
      WidgetTester tester,
    ) async {
      final result = await openOver(
        tester,
        _documentWithCuboid(
          Vector3(1, 1, 1),
          warnings: <String>['bad tangent', 'missing UV'],
        ),
        interact: () async {
          expect(find.text('2 warnings'), findsOneWidget);
          expect(find.textContaining('bad tangent'), findsOneWidget);
          expect(find.textContaining('missing UV'), findsOneWidget);
          // Mutation: read document.warnings.length - 1, and one real
          // warning is not shown for a file that carries exactly two.
          await tester.tap(_cancelButton);
        },
      );
      expect(result, isNull);
    });

    testWidgets(
      'an .stl in millimetres, "mm" chosen, confirms with that unit',
      (WidgetTester tester) async {
        final result = await openOver(
          tester,
          _documentWithCuboid(Vector3(2000, 2000, 2000)),
          interact: () async {
            await tester.tap(find.text('mm'));
            await tester.pumpAndSettle();
            await tester.tap(_importButton);
          },
        );

        expect(result, isNotNull);
        expect(result!.unit, ImportUnit.millimetres);
      },
    );

    testWidgets('cancelling returns null, not a default choice', (
      WidgetTester tester,
    ) async {
      final result = await openOver(
        tester,
        _documentWithCuboid(Vector3(1, 1, 1)),
        interact: () async => tester.tap(_cancelButton),
      );
      expect(result, isNull);
    });

    testWidgets('the weld/normals/triangulate checkboxes reach ImportChoice', (
      WidgetTester tester,
    ) async {
      final result = await openOver(
        tester,
        _documentWithCuboid(Vector3(1, 1, 1)),
        interact: () async {
          await tester.tap(find.text('Weld coincident vertices'));
          await tester.tap(find.text('Recalculate normals'));
          await tester.tap(find.text('Triangulate n-gons'));
          await tester.pumpAndSettle();
          await tester.tap(_importButton);
        },
      );

      expect(result, isNotNull);
      // The screen's own default is weld off, both others off — so all
      // three toggled once each land as true.
      expect(result!.weld, isTrue);
      expect(result.fixNormals, isTrue);
      expect(result.triangulate, isTrue);
    });

    testWidgets('warns against the mobile preset even on a desktop profile', (
      WidgetTester tester,
    ) async {
      final heavy = PlainModelDocument(
        surfaces: <ModelSurface>[
          for (
            var i = 0;
            i < ProjectProfile.mobile.maxTriangles ~/ 12 + 1;
            i++
          )
            ModelSurface(mesh: CuboidShape(size: Vector3(1, 1, 1)).build()),
        ],
      );
      await openOver(
        tester,
        heavy, // profile defaults to desktop
        interact: () async {
          expect(find.textContaining('mobile preset'), findsOneWidget);
          await tester.tap(_cancelButton);
        },
      );
    });
  });
}
