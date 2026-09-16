/// `mat-34d`'s own row: scene mode wired to its four already-built panels —
/// nothing else in this suite pumps `PropertiesPanel` as a whole, so this is
/// also where "switching modes replaces the panel wholesale" gets checked
/// end to end rather than only through `properties_sections_test.dart`'s own
/// pure table.
///
///     flutter test test/properties_panel_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_core/formats.dart' show SurfaceMaterial;
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart' show EditMesh;
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Outcome;
import 'package:flutter3d_modeler/l10n/app_localizations.dart';
import 'package:flutter3d_modeler/l10n/app_localizations_en.dart';
import 'package:flutter3d_modeler/src/display_modes.dart';
import 'package:flutter3d_modeler/src/scene_mode.dart';
import 'package:flutter3d_modeler/src/staging.dart';
import 'package:flutter3d_modeler/src/ui/properties/label_value_row.dart';
import 'package:flutter3d_modeler/src/ui/properties/properties_panel.dart';
import 'package:flutter3d_modeler/src/ui/scene_environment_panel.dart';
import 'package:flutter3d_modeler/src/ui/scene_post_panel.dart';
import 'package:flutter3d_modeler/src/ui/scene_shadows_panel.dart';
import 'package:flutter3d_modeler/src/ui/scene_source_panel.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter3d_modeler/src/ui/tools.dart';
import 'package:flutter_test/flutter_test.dart';
// Prefixed for the same reason `main.dart`'s own import is: `material.dart`
// and `vector_math` disagree about which `Matrix4` a bare reference means.
import 'package:vector_math/vector_math.dart' as vm show Matrix4;

/// A project with [lightCount] identical directional lights and nothing
/// else — enough for `sceneStatus`/the four panels, and light on everything
/// a mesh, a material or an animation clip would otherwise need.
ModelProject _sceneProject(int lightCount) => const ModelProject().copyWith(
  lighting: SceneLighting(
    lights: List<ProjectLight>.generate(lightCount, (int i) => ProjectLight()),
  ),
);

Future<void> _pump(
  WidgetTester tester, {
  required ModelerMode mode,
  AnimationSubmode animationSubmode = AnimationSubmode.pose,
  ModelProject? project,

  /// What is held, for the sections that draw nothing without one.
  ProjectSelection? selection,
  List<String> retargetSourceNames = const <String>[],
  BoneMap retargetBoneMap = const BoneMap(<String, String>{}),
  bool canApplyRetarget = false,
  bool touch = false,

  /// What the platform's own text-size setting is turned up to — `ux-33`.
  double textScale = 1.0,

  /// `ux-48`: null is a platform with no filesystem, and the section goes.
  void Function(int id)? onReimport,
}) async {
  // Tall enough that the panel's own `ListView` never has to scroll to
  // reach the scene panels — nine light rows push the shadows panel well
  // past an ordinary window's height, and a sliver list never builds an
  // element for a child it has not laid out, `find.text` included.
  tester.view
    ..physicalSize = const Size(800, 2400)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final it = cpuTestDevice(width: 8, height: 8);
  final held = project ?? const ModelProject();
  final stage = ModelerStage.fromProject(device: it.device, project: held);
  // The platform is pinned for `ux-21`'s own sake: `ThemeData` derives
  // `materialTapTargetSize` from it, so a tap-target test that let it fall
  // back to the host would answer differently in CI and on a Mac.
  await tester.pumpWidget(
    MaterialApp(
      theme: modelerTheme().copyWith(platform: TargetPlatform.macOS),
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) {
            final Widget panel = PropertiesPanel(
              mode: mode,
              animationSubmode: animationSubmode,
              stage: stage,
              project: held,
              selection: selection ?? ProjectSelection.none,
              onSelect: (_) {},
              onTransform: (_, _) {},
              pivot: PivotChip.median,
              onPivot: (_) {},
              space: TransformSpace.global,
              onSpace: (_) {},
              onRename: (_, _) {},
              onToggleModifier: (_, _) {},
              onReorderModifier: (_, _, _) {},
              onAddModifier: (_, _) {},
              onAssignMaterial: (_, _) {},
              onAddMaterial: () {},
              onReimport: onReimport,
              onSetMaterialField: (_, _, _) {},
              onChooseTexture: (_, _) {},
              onClearTexture: (_, _) {},
              onAddTextureNode: (_, _, _, _) {},
              onLinkTextureNode: (_, _, _, _) {},
              onUnlinkTextureNode: (_, _, _) {},
              onSetTextureNodeField: (_, _, _, _) {},
              onMoveTextureNode: (_, _, _, _) {},
              onRemoveTextureNode: (_, _) {},
              onBakeTextureGraph: (_) {},
              onAddClip: () {},
              onSelectAnimationClip: (_) {},
              onSelectJoint: (_) {},
              onSelectConstraint: (_) {},
              onSetShapeWeight: (_, _, _) {},
              onKeyShape: (_) {},
              onSelectShape: (_) {},
              onAddShapeDriver: (_, _) {},
              onRemoveShapeDriver: (_, _) {},
              onSetShapeDriverField: (_, _, _, _) {},
              retargetSourceNames: retargetSourceNames,
              retargetBoneMap: retargetBoneMap,
              onRetargetAutoMap: () {},
              onRetargetRootMotionChanged: (_) {},
              onRetargetLockFeetChanged: (_) {},
              onRetargetGroundYChanged: (_) {},
              onRetargetFootToleranceChanged: (_) {},
              canApplyRetarget: canApplyRetarget,
              onWeightBrushModeChanged: (_) {},
              onWeightBrushRadiusChanged: (_) {},
              onWeightBrushStrengthChanged: (_) {},
              onWeightMirrorChanged: (_) {},
              onWeightNormalizeChanged: (_) {},
              onSelectLight: (_) {},
              onAddLight: () {},
              onRemoveLight: (_) {},
              onLightTypeChanged: (_, _) {},
              onLightIntensityChanged: (_, _) {},
              onLightRangeChanged: (_, _) {},
              onLightShadowChanged: (_, _) {},
              onLightConeChanged: (_, _) {},
              onSceneShadowsChanged: (_) {},
              onEnvironmentChanged: (_) {},
              onAmbientChanged: (_) {},
              onBloomChanged: (_) {},
              onExposureChanged: (_) {},
              lastCommand: null,
              onAmend: (_) {},
              shading: ShadingMode.material,
              onShading: (_) {},
              lens: ViewLens.perspective,
              onLens: (_) {},
              onView: (_) {},
            );
            return touch ? withTouchTargets(context, panel) : panel;
          },
        ),
      ),
    ),
  );
}

/// The words `sceneStatusLabel` builds for [status] under `Locale('en')` —
/// the same helper `scene_shadows_panel_test.dart` already keeps for the
/// panel's own tests.
String _statusText(SceneStatus status) => AppLocalizationsEn().sceneStatusLabel(
  status.lightCount,
  status.shadowedCount,
  status.shadowCap,
);

void main() {
  testWidgets('switching to Scene mode shows all four scene panels', (
    tester,
  ) async {
    await _pump(tester, mode: ModelerMode.scene, project: _sceneProject(2));

    expect(find.byType(SceneSourcePanel), findsOneWidget);
    expect(find.byType(SceneShadowsPanel), findsOneWidget);
    expect(find.byType(SceneEnvironmentPanel), findsOneWidget);
    expect(find.byType(ScenePostPanel), findsOneWidget);
  });

  testWidgets('object mode shows none of the four scene panels', (
    tester,
  ) async {
    // Mutation: draw the scene panels in every mode instead of gating them
    // on `sectionsFor` — `ui-04`'s own "wholesale, not piecemeal" would be
    // broken silently, since nothing else in this file's own two tests would
    // catch a panel that simply never goes away.
    await _pump(tester, mode: ModelerMode.object);

    expect(find.byType(SceneSourcePanel), findsNothing);
    expect(find.byType(SceneShadowsPanel), findsNothing);
    expect(find.byType(SceneEnvironmentPanel), findsNothing);
    expect(find.byType(ScenePostPanel), findsNothing);
  });

  testWidgets(
    "mat-24's own acceptance, wired: a ninth light source turns the scene "
    'status orange',
    (tester) async {
      final ModelProject nine = _sceneProject(9);
      await _pump(tester, mode: ModelerMode.scene, project: nine);

      final SceneStatus status = computeSceneStatus(
        lights: nine.lighting.lights,
        lightsDropped: lightOverflowOf(nine.lighting),
      );
      expect(status.warning, isTrue);

      final Text text = tester.widget(find.text(_statusText(status)));
      expect(text.style?.fontWeight, FontWeight.bold);
      expect(text.style?.color, kModelerScheme.tertiary);
    },
  );

  testWidgets('eight lights read a clean, unwarned status', (tester) async {
    final ModelProject eight = _sceneProject(8);
    await _pump(tester, mode: ModelerMode.scene, project: eight);

    final SceneStatus status = computeSceneStatus(
      lights: eight.lighting.lights,
      lightsDropped: lightOverflowOf(eight.lighting),
    );
    expect(status.warning, isFalse);

    final Text text = tester.widget(find.text(_statusText(status)));
    expect(text.style?.color, isNot(kModelerScheme.tertiary));
  });

  testWidgets("S7's own row: the animation mode's retarget sub-mode shows "
      "RetargetPanel's own content and none of the other three sub-modes'", (
    tester,
  ) async {
    await _pump(
      tester,
      mode: ModelerMode.animation,
      animationSubmode: AnimationSubmode.retarget,
      retargetSourceNames: const <String>['hips'],
      retargetBoneMap: const BoneMap(<String, String>{}),
    );

    // `SectionLabel` always upper-cases what it is given.
    expect(find.text('BONE MAP'), findsOneWidget);
    expect(find.text('Apply the retarget'), findsOneWidget);
    // The weight-paint sub-mode's own section label — proof this is
    // `sectionsFor`'s "wholesale, not piecemeal" holding for the fourth
    // sub-mode too, not only the three `S5`/`S6` already covered here.
    expect(find.text('BRUSH'), findsNothing);
  });

  testWidgets("ux-31: the morphs section has a heading of its own", (
    tester,
  ) async {
    final ModelProject project = const ModelProject().added(
      (int id) => ModelObject(
        id: id,
        name: 'head',
        geometry: EditedGeometry(EditMesh.cuboid()),
        transform: vm.Matrix4.identity(),
      ),
    );
    await _pump(
      tester,
      mode: ModelerMode.animation,
      animationSubmode: AnimationSubmode.morphs,
      project: project,
      selection: ProjectSelection(objects: <int>[project.objects.single.id]),
    );

    // **Without one, "No shape keys on this object" was the line directly
    // under whatever section came before it** — usually Display — and read
    // as something that section was saying about the view. `SectionLabel`
    // upper-cases what it is given.
    expect(find.text('MORPHS'), findsOneWidget);
    final double heading = tester.getTopLeft(find.text('MORPHS')).dy;
    final double said = tester
        .getTopLeft(find.text('No shape keys on this object'))
        .dy;
    expect(heading, lessThan(said));
  });

  group('ux-48: an object that remembers where it came from', () {
    ModelProject linked() => const ModelProject().added(
      (int id) => ModelObject(
        id: id,
        name: 'crate',
        geometry: EditedGeometry(EditMesh.cuboid()),
        transform: vm.Matrix4.identity(),
        source: (path: 'props/crate.obj', sha: 'abc'),
      ),
    );

    testWidgets('says so, and offers to read the file again', (
      WidgetTester tester,
    ) async {
      final ModelProject project = linked();
      var asked = 0;
      await _pump(
        tester,
        mode: ModelerMode.object,
        project: project,
        selection: ProjectSelection(objects: <int>[project.objects.single.id]),
        onReimport: (_) => asked++,
      );

      expect(find.text('SOURCE'), findsOneWidget);
      expect(find.text('props/crate.obj'), findsOneWidget);

      await tester.tap(find.text('Re-import'));
      await tester.pump();
      expect(asked, 1);
    });

    testWidgets('and an object built here shows no such section', (
      WidgetTester tester,
    ) async {
      final ModelProject project = const ModelProject().added(
        (int id) => ModelObject(
          id: id,
          name: 'box',
          geometry: EditedGeometry(EditMesh.cuboid()),
          transform: vm.Matrix4.identity(),
        ),
      );
      await _pump(
        tester,
        mode: ModelerMode.object,
        project: project,
        selection: ProjectSelection(objects: <int>[project.objects.single.id]),
        onReimport: (_) {},
      );

      // Mutation: draw the section for every object. A "Re-import" on a box
      // somebody built here is a button that can only refuse.
      expect(find.text('SOURCE'), findsNothing);
    });

    testWidgets('and a platform that cannot read a path shows none either', (
      WidgetTester tester,
    ) async {
      final ModelProject project = linked();
      await _pump(
        tester,
        mode: ModelerMode.object,
        project: project,
        selection: ProjectSelection(objects: <int>[project.objects.single.id]),
      );

      expect(find.text('SOURCE'), findsNothing);
    });
  });

  group('ux-33: the panel at twice the text size', () {
    testWidgets('a real panel does not overflow in any mode', (
      WidgetTester tester,
    ) async {
      // **A real panel, because the shell's own 1.3× test used an empty
      // one.** Nothing overflows when the thing being measured is a
      // `SizedBox.shrink`, and 2.0 is what a platform's own accessibility
      // slider actually reaches — the fixed 32/30/52-pixel rows the review
      // listed are the ones that would fail here first.
      for (final ModelerMode mode in <ModelerMode>[
        ModelerMode.object,
        ModelerMode.mesh,
        ModelerMode.material,
        ModelerMode.scene,
        ModelerMode.animation,
      ]) {
        await _pump(
          tester,
          mode: mode,
          project: mode == ModelerMode.scene ? _sceneProject(2) : null,
          textScale: 2.0,
        );
        expect(
          tester.takeException(),
          isNull,
          reason: '$mode overflows at a 2.0 text scale',
        );
      }
    });
  });

  group('ux-21: a finger can hit the panel', () {
    testWidgets('the guideline passes over the real panel, mode by mode', (
      WidgetTester tester,
    ) async {
      for (final ModelerMode mode in <ModelerMode>[
        ModelerMode.object,
        ModelerMode.mesh,
        ModelerMode.scene,
      ]) {
        final SemanticsHandle handle = tester.ensureSemantics();
        await _pump(
          tester,
          mode: mode,
          project: mode == ModelerMode.scene ? _sceneProject(2) : null,
          touch: true,
        );

        // Mutation: hand the panel to a touch shell untouched, as both of
        // them did. A 32-pixel row under a thumb is not a target, and the
        // buttons beside it are drawn with no padding at all on exactly the
        // platforms this row is about — a desktop build dragged narrow, and
        // a browser reporting itself as one.
        await expectLater(
          tester,
          meetsGuideline(androidTapTargetGuideline),
          reason: '$mode',
        );
        handle.dispose();
      }
    });

    testWidgets('and a row grows only where something asked it to', (
      WidgetTester tester,
    ) async {
      await _pump(tester, mode: ModelerMode.object);
      final double desk = tester
          .getSize(find.byType(LabelValueRow).first)
          .height;

      await _pump(tester, mode: ModelerMode.object, touch: true);
      final double thumb = tester
          .getSize(find.byType(LabelValueRow).first)
          .height;

      // Mutation: give every shell the taller row. A desktop panel then
      // shows two thirds as much of the document for no gain at all —
      // a cursor's hotspot is one pixel wide.
      expect(desk, ModelerMetrics.row);
      expect(thumb, kTouchTarget);
    });
  });

  group('ux-40: the Material workspace', () {
    ModelProject painted() {
      final ModelProject project =
          ModelProject(
            materials: <ProjectMaterial>[
              ProjectMaterial(surface: SurfaceMaterial(name: 'brass')),
            ],
          ).added(
            (int id) => ModelObject(
              id: id,
              name: 'box',
              geometry: EditedGeometry(EditMesh.cuboid()),
              transform: vm.Matrix4.identity(),
              materialSlots: const <int>[0],
            ),
          );
      return project;
    }

    testWidgets('material mode draws the slots and the graph, open', (
      WidgetTester tester,
    ) async {
      final ModelProject project = painted();
      await _pump(
        tester,
        mode: ModelerMode.material,
        project: project,
        selection: ProjectSelection(objects: <int>[project.objects.single.id]),
      );

      expect(find.text('Base colour texture'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('textureGraphPanel')),
        findsOneWidget,
      );
      // Open, not a strip to be clicked: switching to this mode is the
      // click. Mutation: leave `initiallyExpanded` false and the canvas
      // costs a second press in the one mode built around it.
      expect(
        find.byKey(const ValueKey<String>('textureGraphViewer')),
        findsOneWidget,
      );
    });

    testWidgets('and object mode keeps the compact row instead', (
      WidgetTester tester,
    ) async {
      final ModelProject project = painted();
      await _pump(
        tester,
        mode: ModelerMode.object,
        project: project,
        selection: ProjectSelection(objects: <int>[project.objects.single.id]),
      );

      // The list, the colour dot and the fields are still here — "clean a
      // mesh, fix its material, export to GLB" is one mode's work. What is
      // not is the texture half. **Mutation: draw the workspace in both.**
      // Five slot rows and a graph canvas then sit between the transform
      // grid and the modifier stack of the mode somebody moves objects in.
      expect(find.text('brass'), findsOneWidget);
      expect(find.text('Base colour texture'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('textureGraphPanel')),
        findsNothing,
      );
    });
  });
}
