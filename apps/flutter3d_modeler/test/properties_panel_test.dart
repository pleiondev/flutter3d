/// `mat-34d`'s own row: scene mode wired to its four already-built panels —
/// nothing else in this suite pumps `PropertiesPanel` as a whole, so this is
/// also where "switching modes replaces the panel wholesale" gets checked
/// end to end rather than only through `properties_sections_test.dart`'s own
/// pure table.
///
///     flutter test test/properties_panel_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Outcome;
import 'package:flutter3d_modeler/l10n/app_localizations.dart';
import 'package:flutter3d_modeler/l10n/app_localizations_en.dart';
import 'package:flutter3d_modeler/src/display_modes.dart';
import 'package:flutter3d_modeler/src/lighting_sync.dart';
import 'package:flutter3d_modeler/src/scene_mode.dart';
import 'package:flutter3d_modeler/src/staging.dart';
import 'package:flutter3d_modeler/src/ui/properties/properties_panel.dart';
import 'package:flutter3d_modeler/src/ui/scene_environment_panel.dart';
import 'package:flutter3d_modeler/src/ui/scene_post_panel.dart';
import 'package:flutter3d_modeler/src/ui/scene_shadows_panel.dart';
import 'package:flutter3d_modeler/src/ui/scene_source_panel.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter3d_modeler/src/ui/tools.dart';
import 'package:flutter_test/flutter_test.dart';

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
  ModelProject? project,
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
  await tester.pumpWidget(
    MaterialApp(
      theme: modelerTheme(),
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: PropertiesPanel(
          mode: mode,
          stage: stage,
          project: held,
          selection: ProjectSelection.none,
          onSelect: (_) {},
          onTransform: (_, _) {},
          pivot: PivotChip.median,
          onPivot: (_) {},
          space: TransformSpace.global,
          onSpace: (_) {},
          onRename: (_, _) {},
          onToggleModifier: (_, _) {},
          onReorderModifier: (_, _, _) {},
          onAddModifier: (_) {},
          onAssignMaterial: (_, _) {},
          onAddMaterial: () {},
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
}
