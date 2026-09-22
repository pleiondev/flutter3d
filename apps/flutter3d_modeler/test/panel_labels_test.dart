/// `ux-33`: the five panels the review found with unnamed buttons in them,
/// each held to `labeledTapTargetGuideline`.
///
///     flutter test test/panel_labels_test.dart
///
/// **One file for the five, rather than a test appended to each of their
/// own.** What is being checked is not a fact about any one panel — it is
/// that the `ui-23` pattern reaches all of them, and a list somebody can
/// read down is the only form in which "all of them" is checkable. The
/// panels' own behaviour stays in their own files.
///
/// `labeledTapTargetGuideline` reads `SemanticsNode.label`, which is why a
/// tooltip alone never satisfied it: `IconButton.tooltip` lands in
/// `.tooltip`, a field the guideline does not look at and most screen readers
/// announce after the control rather than as it.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter3d_core/formats.dart' show MaterialHint, TextureHint;
import 'package:flutter3d_mesh/flutter3d_mesh.dart' show ShapeKey;
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/l10n/app_localizations.dart';
import 'package:flutter3d_modeler/src/ui/constraints_list.dart';
import 'package:flutter3d_modeler/src/ui/morphs_panel.dart';
import 'package:flutter3d_modeler/src/ui/scene_source_panel.dart';
import 'package:flutter3d_modeler/src/ui/skeleton_tree.dart';
import 'package:flutter3d_modeler/src/ui/texture_graph_panel.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Pumps [panel] wide enough not to overflow, with semantics switched on,
/// and holds it to the guideline.
Future<void> named(WidgetTester tester, Widget panel) async {
  final SemanticsHandle handle = tester.ensureSemantics();
  tester.view
    ..physicalSize = const Size(700, 1400)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: modelerTheme(),
      // `SceneSourcePanel` reads `AppLocalizations.of(context)` for its own
      // light-type names, and pinned to English so a finder means the same
      // thing whatever locale the machine is in.
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: panel)),
    ),
  );
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  handle.dispose();
}

ModelObject _joint(int id, String name, {int? parent}) => ModelObject(
  id: id,
  name: name,
  geometry: const SocketGeometry(),
  transform: vm.Matrix4.identity(),
  parent: parent,
);

void main() {
  testWidgets('the skeleton tree names the branch each arrow folds', (
    WidgetTester tester,
  ) async {
    await named(
      tester,
      SkeletonTree(
        objects: <ModelObject>[
          _joint(1, 'hips'),
          _joint(2, 'spine', parent: 1),
          _joint(3, 'head', parent: 2),
        ],
        skeleton: ProjectSkeleton(
          joints: const <int>[1, 2, 3],
          inverseBindMatrices: <vm.Matrix4>[
            vm.Matrix4.identity(),
            vm.Matrix4.identity(),
            vm.Matrix4.identity(),
          ],
        ),
        onSelectJoint: (_) {},
      ),
    );
  });

  testWidgets('the constraints list names what its close button removes', (
    WidgetTester tester,
  ) async {
    await named(
      tester,
      ConstraintsList(
        constraints: <IkConstraint>[
          IkConstraint(
            rootJointId: 1,
            midJointId: 2,
            effectorJointId: 3,
            target: vm.Vector3(1, 0, 0),
            pole: vm.Vector3(0, 1, 0),
          ),
        ],
        onSelect: (_) {},
        onRemove: (_) {},
      ),
    );
  });

  testWidgets('the morphs panel names its key dot and its driver rows', (
    WidgetTester tester,
  ) async {
    final ModelObject head = ModelObject(
      id: 1,
      name: 'head',
      geometry: const SocketGeometry(),
      transform: vm.Matrix4.identity(),
      shapeSet: ShapeSet(
        keys: <ShapeKey>[ShapeKey('smile', Float32List(3))],
        weights: const <double>[0.0],
      ),
    );
    await named(
      tester,
      MorphsPanel(
        object: head,
        objects: <ModelObject>[head],
        skeleton: null,
        hasKeyAtCurrentFrame: true,
        onSetWeight: (_, _) {},
        onKeyShape: () {},
        onSelectShape: (_) {},
        onAddDriver: (_) {},
        onRemoveDriver: (_) {},
        onSetDriverField: (_, _, _) {},
      ),
    );
  });

  testWidgets('the scene source panel names which light it removes', (
    WidgetTester tester,
  ) async {
    await named(
      tester,
      SceneSourcePanel(
        lights: <ProjectLight>[ProjectLight(), ProjectLight()],
        selected: 0,
        onSelect: (_) {},
        onAdd: () {},
        onRemove: (_) {},
        onTypeChanged: (_, _) {},
        onIntensityChanged: (_, _) {},
        onRangeChanged: (_, _) {},
        onShadowChanged: (_, _) {},
        onConeChanged: (_, _) {},
      ),
    );
  });

  testWidgets("the texture graph's own hint rows name their stepper", (
    WidgetTester tester,
  ) async {
    await named(
      tester,
      const HintRow(
        field: 'imageId',
        hint: MaterialHint(TextureHint()),
        value: 0,
        onChanged: _ignore,
      ),
    );
  });
}

void _ignore(Object? value) {}
