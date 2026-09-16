/// Reproduces a real framework assertion crash found driving the modeler
/// live over MCP on 2026-09-15: `addLathe`, `bakeToMesh`, `addMaterial`,
/// three `setMaterialField` calls, `assignMaterial`, then `select` —
/// deterministic, twice in a row, on two clean relaunches — threw
/// `'package:flutter/src/widgets/framework.dart': Failed assertion: line
/// 2170 pos 12: '_elements.contains(element)': is not true.` with a second,
/// stacked `RawTooltipState`/`SingleTickerProviderStateMixin` error behind
/// it, right as `select`'s own rebuild landed.
///
///     flutter test test/properties_panel_select_crash_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Outcome;
import 'package:flutter3d_model_mcp/flutter3d_model_mcp.dart';
import 'package:flutter3d_modeler/l10n/app_localizations.dart';
import 'package:flutter3d_modeler/src/display_modes.dart';
import 'package:flutter3d_modeler/src/staging.dart';
import 'package:flutter3d_modeler/src/ui/properties/properties_panel.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter3d_modeler/src/ui/tools.dart';
import 'package:flutter_test/flutter_test.dart';

ModelTool _toolNamed(String name) =>
    modelTools.firstWhere((ModelTool tool) => tool.name == name);

Future<void> _call(
  ModelSession session,
  String name,
  Map<String, Object?> arguments,
) async {
  final Answer answer = await _toolNamed(name).run(session, arguments);
  if (!answer.did) {
    throw StateError('$name refused: ${answer.says}');
  }
}

/// A minimal stand-in for `ready_parts.dart`'s own `PropertiesPanel(...)`
/// wiring — [history] read live the same way `ModelerReady.project`/
/// `.selection` and `ready_parts.dart`'s own `lastCommand:` already do,
/// rebuilt on every [refresh].
class _Harness extends StatefulWidget {
  const _Harness({super.key, required this.history, required this.stage});

  final ModelHistory history;
  final ModelerStage stage;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  void refresh() => setState(() {});

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: modelerTheme(),
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: PropertiesPanel(
        mode: ModelerMode.object,
        stage: widget.stage,
        project: widget.history.project,
        selection: widget.history.selection,
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
        retargetBoneMap: const BoneMap(<String, String>{}),
        onRetargetAutoMap: () {},
        onRetargetRootMotionChanged: (_) {},
        onRetargetLockFeetChanged: (_) {},
        onRetargetGroundYChanged: (_) {},
        onRetargetFootToleranceChanged: (_) {},
        onSelectJoint: (_) {},
        onSelectConstraint: (_) {},
        onWeightBrushModeChanged: (_) {},
        onWeightBrushRadiusChanged: (_) {},
        onWeightBrushStrengthChanged: (_) {},
        onWeightMirrorChanged: (_) {},
        onWeightNormalizeChanged: (_) {},
        onSetShapeWeight: (_, _, _) {},
        onKeyShape: (_) {},
        onSelectShape: (_) {},
        onAddShapeDriver: (_, _) {},
        onRemoveShapeDriver: (_, _) {},
        onSetShapeDriverField: (_, _, _, _) {},
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
        lastCommand: widget.history.journal.isEmpty
            ? null
            : widget.history.journal.last,
        onAmend: (_) {},
        shading: ShadingMode.material,
        onShading: (_) {},
        lens: ViewLens.perspective,
        onLens: (_) {},
        onView: (_) {},
      ),
    ),
  );
}

void main() {
  testWidgets('addLathe, bakeToMesh, addMaterial, three setMaterialField, '
      'assignMaterial, then select — the exact live sequence that crashed', (
    WidgetTester tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1440, 1600)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final it = cpuTestDevice(width: 8, height: 8);
    final history = ModelHistory(const ModelProject());
    final stage = ModelerStage.fromProject(
      device: it.device,
      project: history.project,
    );
    final session = ModelSession(history);

    final key = GlobalKey<_HarnessState>();
    await tester.pumpWidget(_Harness(key: key, history: history, stage: stage));
    await tester.pump();

    Future<void> step(String name, Map<String, Object?> arguments) async {
      await _call(session, name, arguments);
      key.currentState!.refresh();
      await tester.pump();
    }

    await step('addLathe', <String, Object?>{
      'profile': <List<double>>[
        [0.00, 0.00],
        [0.32, 0.00],
        [0.38, 0.12],
        [0.34, 0.32],
        [0.22, 0.50],
        [0.30, 0.72],
        [0.24, 0.92],
        [0.26, 1.00],
      ],
      'segments': 12,
      'label': 'vase',
    });
    final int objectId = history.project.objects.single.id;

    await step('bakeToMesh', <String, Object?>{'id': objectId});
    await step('addMaterial', <String, Object?>{'materialName': 'glazed clay'});
    await step('setMaterialField', <String, Object?>{
      'index': 0,
      'field': 'baseColor',
      'value': <double>[0.55, 0.35, 0.25, 1.0],
    });
    await step('setMaterialField', <String, Object?>{
      'index': 0,
      'field': 'metallic',
      'value': 0.0,
    });
    await step('setMaterialField', <String, Object?>{
      'index': 0,
      'field': 'roughness',
      'value': 0.55,
    });
    await step('assignMaterial', <String, Object?>{'id': objectId, 'to': 0});

    // The step that crashed live: selecting the object the material was
    // just assigned to.
    await _call(session, 'select', <String, Object?>{
      'objects': <int>[objectId],
    });
    key.currentState!.refresh();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
