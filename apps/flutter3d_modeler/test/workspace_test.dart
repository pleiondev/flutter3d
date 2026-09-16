/// `ux-37`: Essential and Full — which modes the switcher offers, and what a
/// key for a mode the workspace does not have says.
///
///     flutter test test/workspace_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/modeler_cubit.dart';
import 'package:flutter3d_modeler/src/settings.dart';
import 'package:flutter3d_modeler/src/staging.dart';
import 'package:flutter3d_modeler/src/ui/shell.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter3d_modeler/src/ui/tools.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm show Matrix4;

ModelerCubit _opened() {
  final it = cpuTestDevice(width: 8, height: 8);
  final project = const ModelProject().added(
    (int id) => ModelObject(
      id: id,
      name: 'a',
      geometry: EditedGeometry(EditMesh.cuboid()),
      transform: vm.Matrix4.identity(),
    ),
  );
  final history = ModelHistory(project);
  return ModelerCubit()..opened(
    history,
    renderer: Renderer.create(device: it.device),
    stage: ModelerStage.fromProject(
      device: it.device,
      project: history.project,
    ),
  );
}

ModelerReady _ready(ModelerCubit cubit) => cubit.state as ModelerReady;

void main() {
  group('ux-37: which modes a workspace offers', () {
    test('Essential is Object, Material and Scene', () {
      // Mutation: offer everything and let a person turn things off. A
      // switcher of five icons asks somebody who came to open a model, paint
      // it and export it to first decide what Mesh mode and Animation mode
      // are.
      expect(modesFor(Workspace.essential), <ModelerMode>[
        ModelerMode.object,
        ModelerMode.material,
        ModelerMode.scene,
      ]);
    });

    test('Full is every mode this build has made', () {
      expect(modesFor(Workspace.full), <ModelerMode>[
        ModelerMode.object,
        ModelerMode.mesh,
        ModelerMode.material,
        ModelerMode.animation,
        ModelerMode.scene,
      ]);
    });

    test('and neither offers a mode nobody has built — ux-07', () {
      for (final Workspace workspace in Workspace.values) {
        for (final ModelerMode mode in modesFor(workspace)) {
          expect(mode.ready, isTrue, reason: '${mode.name} in $workspace');
        }
      }
    });
  });

  group('ux-37: the document follows the workspace', () {
    test('an empty settings store opens in Essential', () {
      // What `ModelerReady` starts as, which is what a first launch sees.
      expect(_ready(_opened()).workspace, Workspace.essential);
      expect(const ModelerSettings().workspace, Workspace.essential);
    });

    test('a mode the workspace does not offer refuses, and names it', () {
      final cubit = _opened();
      cubit.mode(ModelerMode.mesh);

      // Mutation: change the mode anyway, or do nothing silently. A key that
      // appears to have missed is the failure `ux-07` already found in the
      // switcher, reached a different way.
      expect(_ready(cubit).mode, ModelerMode.object);
      expect(_ready(cubit).said, contains('Full workspace'));
      expect(_ready(cubit).said, contains('Essential'));
      expect(_ready(cubit).saidIsRefusal, isTrue);
    });

    test('switching to Full makes it reachable, with no restart', () {
      final cubit = _opened()..workspace(Workspace.full);
      cubit.mode(ModelerMode.mesh);
      expect(_ready(cubit).mode, ModelerMode.mesh);
    });

    test('switching back moves off a mode that is going away', () {
      final cubit = _opened()..workspace(Workspace.full);
      cubit.mode(ModelerMode.mesh);

      cubit.workspace(Workspace.essential);
      // Mutation: leave them standing in Mesh. The segment is gone, so there
      // is nothing lit and no way back to it.
      expect(_ready(cubit).mode, ModelerMode.object);
      expect(_ready(cubit).workspace, Workspace.essential);
    });

    test('and a mode the workspace keeps is left alone', () {
      final cubit = _opened()..workspace(Workspace.full);
      cubit.mode(ModelerMode.material);
      cubit.workspace(Workspace.essential);
      expect(_ready(cubit).mode, ModelerMode.material);
    });
  });

  group('ux-37: the switcher', () {
    Future<void> pump(WidgetTester tester, Workspace workspace) =>
        tester.pumpWidget(
          MaterialApp(
            theme: modelerTheme(),
            home: Scaffold(
              body: ModelerModeSwitcher(
                workspace: workspace,
                mode: ModelerMode.object,
                onMode: (_) {},
                submode: MeshSubmode.vertex,
                onSubmode: (_) {},
              ),
            ),
          ),
        );

    testWidgets('Essential draws three segments, Full five', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pump(tester, Workspace.essential);
      expect(find.byType(ButtonSegment<ModelerMode>), findsNothing);
      expect(find.bySemanticsLabel('Mesh'), findsNothing);
      expect(find.bySemanticsLabel('Object'), findsOneWidget);
      expect(find.bySemanticsLabel('Scene'), findsOneWidget);

      await pump(tester, Workspace.full);
      expect(find.bySemanticsLabel('Mesh'), findsOneWidget);
      expect(find.bySemanticsLabel('Animation'), findsOneWidget);
    });
  });
}
