/// `anim-23`'s own modal: template chips, the "N bones · M deforming" card,
/// Cancel discarding everything, and Create landing one `SetRig` step —
/// `lathe_dialog_test.dart`'s own `cpuTestDevice`/`Renderer.create` shape,
/// since this dialog draws a real (throwaway) [ModelerStage] the same way.
///
///     flutter test test/ui/autorig_dialog_test.dart
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide Material, Matrix4;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/l10n/app_localizations.dart';
import 'package:flutter3d_modeler/src/modeler_cubit.dart';
import 'package:flutter3d_modeler/src/staging.dart';
import 'package:flutter3d_modeler/src/ui/autorig_dialog.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Matrix4;

Renderer _testRenderer() {
  final it = cpuTestDevice();
  return Renderer.create(
    device: it.device,
    fallbackAlbedo: it.albedo,
    fallbackNormal: it.normal,
  );
}

ModelProject _projectWithFigure() => ModelProject(
  objects: <ModelObject>[
    ModelObject(
      id: 1,
      name: 'figure',
      geometry: EditedGeometry(EditMesh.cuboid()),
      transform: Matrix4.identity(),
    ),
  ],
  nextId: 2,
);

ModelerCubit _readyCubit(Renderer renderer, ModelProject project) {
  final cubit = ModelerCubit();
  cubit.opened(
    ModelHistory(project),
    renderer: renderer,
    stage: ModelerStage.build(device: renderer.device),
  );
  return cubit;
}

/// A fixed number of frames rather than [WidgetTester.pumpAndSettle] — the
/// dialog's own `ModelerViewport` renders every rebuild, including its own
/// open/close transition, and `pumpAndSettle` waits for *no* frame to be
/// scheduled at all — `lathe_dialog_test.dart`'s own `_settle`.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _open(
  WidgetTester tester, {
  required ModelerCubit cubit,
  required Renderer renderer,
  required ModelProject project,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: modelerTheme(),
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => ElevatedButton(
            onPressed: () => showAutorigDialog(
              context,
              cubit: cubit,
              renderer: renderer,
              project: project,
              skinObjectId: 1,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await _settle(tester);
}

void main() {
  Future<void> withScreen(
    WidgetTester tester,
    Future<void> Function() body,
  ) async {
    tester.view.physicalSize = const ui.Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await body();
  }

  testWidgets(
    'opens on the humanoid template with its default 17-bone preview',
    (WidgetTester tester) async {
      await withScreen(tester, () async {
        final renderer = _testRenderer();
        final cubit = _readyCubit(renderer, _projectWithFigure());
        addTearDown(cubit.close);

        await _open(
          tester,
          cubit: cubit,
          renderer: renderer,
          project: _projectWithFigure(),
        );

        expect(find.text('Humanoid'), findsOneWidget);
        expect(find.text('Bones'), findsOneWidget);
        expect(find.text('Deforming'), findsOneWidget);
        // The default `RigBuildOptions` humanoid is 17 joints, all of them
        // deforming — both rows of the summary card read the same number.
        expect(find.text('17'), findsNWidgets(2));
      });
    },
  );

  testWidgets('Cancel closes the dialog and changes nothing', (
    WidgetTester tester,
  ) async {
    await withScreen(tester, () async {
      final renderer = _testRenderer();
      final project = _projectWithFigure();
      final cubit = _readyCubit(renderer, project);
      addTearDown(cubit.close);

      await _open(tester, cubit: cubit, renderer: renderer, project: project);

      await tester.tap(find.text('Cancel'));
      await _settle(tester);

      expect(find.text('Auto-rig'), findsNothing);
      final ModelerReady state = cubit.state as ModelerReady;
      expect(state.history.canUndo, isFalse);
      expect(state.project.skeletons, isEmpty);
    });
  });

  testWidgets(
    'Create, with primary weights off, lands one SetRig step and closes',
    (WidgetTester tester) async {
      await withScreen(tester, () async {
        final renderer = _testRenderer();
        final project = _projectWithFigure();
        final cubit = _readyCubit(renderer, project);
        addTearDown(cubit.close);

        await _open(tester, cubit: cubit, renderer: renderer, project: project);

        await tester.tap(find.text('Assign primary weights'));
        await tester.pump();

        await tester.tap(find.text('Create'));
        await _settle(tester);

        expect(find.text('Auto-rig'), findsNothing);
        final ModelerReady state = cubit.state as ModelerReady;
        expect(state.history.canUndo, isTrue);
        expect(state.project.skeletons, hasLength(1));
        expect(state.project[1]!.skeletonIndex, 0);
        expect(state.history.undo(), isTrue);
        expect(state.history.canUndo, isFalse, reason: 'one journal step');
      });
    },
  );

  testWidgets('switching to Quadruped resets the composition card', (
    WidgetTester tester,
  ) async {
    await withScreen(tester, () async {
      final renderer = _testRenderer();
      final project = _projectWithFigure();
      final cubit = _readyCubit(renderer, project);
      addTearDown(cubit.close);

      await _open(tester, cubit: cubit, renderer: renderer, project: project);

      await tester.tap(find.text('Quadruped'));
      await tester.pump();

      // The quadruped template is 15 joints, none of the humanoid-only
      // composition switches (fingers, toes, spine count, face) shown.
      expect(find.text('15'), findsNWidgets(2));
      expect(find.text('Fingers'), findsNothing);

      await tester.tap(find.text('Cancel'));
      await _settle(tester);
    });
  });
}
