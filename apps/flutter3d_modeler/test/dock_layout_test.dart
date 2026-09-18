/// `ux-38`'s own layout: per workspace, saved, and two views of one
/// document.
///
///     flutter test test/dock_layout_test.dart
library;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Outcome;
import 'package:flutter3d_modeler/src/settings.dart';
import 'package:flutter3d_modeler/src/staging.dart';
import 'package:flutter3d_modeler/src/ui/dock_layout.dart';
import 'package:flutter3d_modeler/src/ui/split_viewports.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multi_split_view/multi_split_view.dart';
import 'package:vector_math/vector_math.dart' as vm show Matrix4;

import 'support/fake_graphics_backend.dart';

ModelProject _one() => const ModelProject().added(
  (int id) => ModelObject(
    id: id,
    name: 'box',
    geometry: EditedGeometry(EditMesh.cuboid()),
    transform: vm.Matrix4.identity(),
  ),
);

void main() {
  group('a layout per workspace', () {
    test('each workspace keeps its own, and an unset one falls back', () {
      const ModelerSettings fresh = ModelerSettings(propertiesWidth: 310);

      // **Mutation: one shared width.** Switching workspace then hands back
      // the width the other one was arranged to, so the layout is rebuilt by
      // hand on every switch — which is how people stop switching.
      final ModelerSettings settings = fresh.copyWith(
        layouts: withLayout(
          fresh.layouts,
          Workspace.full,
          const DockLayout(propertiesWidth: 420, splitViewport: true),
        ),
      );

      expect(settings.layoutOf(Workspace.full).propertiesWidth, 420);
      expect(settings.layoutOf(Workspace.full).splitViewport, isTrue);
      // Never arranged: the width every build before `ux-38` wrote, so a
      // settings file from one of them opens the way it always did.
      expect(settings.layoutOf(Workspace.essential).propertiesWidth, 310);
      expect(settings.layoutOf(Workspace.essential).splitViewport, isFalse);
    });

    test('and it comes back after a restart', () {
      const ModelerSettings fresh = ModelerSettings();
      final ModelerSettings settings = fresh.copyWith(
        layouts: withLayout(
          withLayout(
            fresh.layouts,
            Workspace.full,
            const DockLayout(
              propertiesWidth: 420,
              splitViewport: true,
              viewportSplit: 0.35,
            ),
          ),
          Workspace.essential,
          const DockLayout(propertiesWidth: 260),
        ),
      );

      // The row's own acceptance, without a window: what a restart does is
      // read the file back. Mutation: leave `layouts` out of `toJson` and
      // every arrangement is this session's only.
      final ModelerSettings back = ModelerSettings.fromJson(settings.toJson());
      expect(back.layoutOf(Workspace.full).viewportSplit, closeTo(0.35, 1e-9));
      expect(back.layoutOf(Workspace.full).splitViewport, isTrue);
      expect(back.layoutOf(Workspace.essential).propertiesWidth, 260);
      expect(back, settings);
    });

    test('a hand-edited split that leaves no viewport is clamped', () {
      final DockLayout read = DockLayout.fromJson(<String, Object?>{
        'viewportSplit': 0.99,
        'splitViewport': true,
      });

      // A settings file is a text file somebody can edit, and a view of two
      // pixels is not a layout anybody asked for.
      expect(read.viewportSplit, closeTo(0.85, 1e-9));
    });

    test('an entry a newer build wrote is carried through, not dropped', () {
      final ModelerSettings back = ModelerSettings.fromJson(<String, Object?>{
        'layouts': <String, Object?>{
          'full': <String, Object?>{'propertiesWidth': 400},
          // A workspace this build has never heard of.
          'sculpting': <String, Object?>{'propertiesWidth': 280},
        },
      });

      expect(back.layouts.keys, containsAll(<String>['full', 'sculpting']));
      expect(back.toJson()['layouts'], isA<Map<String, Object?>>());
    });
  });

  testWidgets('two viewports draw one document from two cameras', (
    WidgetTester tester,
  ) async {
    final it = fakeTestDevice(width: 32, height: 32);
    final Renderer renderer = Renderer.create(device: it.device);
    final ModelerStage stage = ModelerStage.fromProject(
      device: it.device,
      project: _one(),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: modelerTheme(),
        home: Scaffold(
          body: SplitViewports(
            renderer: renderer,
            stage: stage,
            primary: const ColoredBox(color: Colors.black),
            split: 0.5,
            onSplit: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(MultiSplitView), findsOneWidget);
    // **One scene, two cameras.** Mutation: build the second view its own
    // stage from the same project, and the two drift apart the moment
    // anybody edits either — a material changed in one would not be the
    // material in the other.
    final ModelerStage second = ModelerStage.secondViewOf(stage);
    expect(identical(second.scene, stage.scene), isTrue);
    expect(identical(second.sync, stage.sync), isTrue);
    expect(identical(second.materials, stage.materials), isTrue);
    expect(identical(second.camera, stage.camera), isFalse);
    // A quarter turn round, because two views from the same angle are one
    // view drawn twice.
    expect(second.orbit.yaw, isNot(closeTo(stage.orbit.yaw, 1e-6)));
  });
}
