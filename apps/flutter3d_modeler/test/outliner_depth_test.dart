/// The outliner on a deep hierarchy — a rig, which is what made the indent a
/// problem.
///
///     flutter test test/outliner_depth_test.dart
library;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/ui/properties/outliner.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm show Matrix4;

/// A chain [deep] objects long, each hanging under the one before it — the
/// shape a humanoid rig has: hips, spine, chest, shoulder, arm, hand, finger,
/// and past it.
List<ModelObject> _chain(int deep) => <ModelObject>[
  for (var i = 0; i < deep; i++)
    ModelObject(
      id: i + 1,
      name: 'joint ${i + 1} with a long enough name to matter',
      geometry: EditedGeometry(EditMesh.cuboid()),
      transform: vm.Matrix4.identity(),
      parent: i == 0 ? null : i,
    ),
];

void main() {
  test('rows come back one per object, each a level deeper', () {
    final List<OutlinerRow> rows = outlinerRows(_chain(12));
    expect(rows, hasLength(12));
    expect(rows.last.depth, 11);
  });

  testWidgets('a twelve-deep rig fits a panel without overflowing', (
    WidgetTester tester,
  ) async {
    // The width the properties panel opens at, which is the width the
    // tutorial's own screenshots are taken at.
    await tester.pumpWidget(
      MaterialApp(
        theme: modelerTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 250,
            child: SingleChildScrollView(
              child: Outliner(
                objects: _chain(12),
                selected: const <int>[],
                onPick: (_, _) {},
                onVisible: (_, _) {},
                onLocked: (_, _) {},
                onRename: (_, _) {},
                onReparent: (_, _) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Mutation: indent by `depth × 12` with no cap. Twelve levels is a
    // hundred and forty-four pixels taken off the front of a two-hundred-
    // and-fifty-pixel panel, and the eye and the lock — fixed widths, at the
    // end of the row — go off the edge. `tutorial_case_screenshots_test.dart`
    // caught it as a `RenderFlex` overflow on every screenshot of a
    // character, which is the only place this repository had a hierarchy
    // that deep.
    expect(tester.takeException(), isNull);

    // And the buttons are still there to press, which is the thing the
    // overflow was taking away.
    expect(find.byTooltip('Hide'), findsNWidgets(12));
    expect(find.byTooltip('Lock'), findsNWidgets(12));
  });
}
