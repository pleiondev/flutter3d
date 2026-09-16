/// The outliner with a screen reader listening and more rows than fit — the
/// shape that stopped the framework building a semantics tree at all.
///
///     flutter test test/outliner_semantics_test.dart
library;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/ui/properties/outliner.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm show Matrix4;

List<ModelObject> _tree(int count) => <ModelObject>[
  for (var i = 0; i < count; i++)
    ModelObject(
      id: i + 1,
      name: 'node ${i + 1}',
      geometry: EditedGeometry(EditMesh.cuboid()),
      transform: vm.Matrix4.identity(),
      parent: i == 0 ? null : (i % 3 == 0 ? i : null),
    ),
];

void main() {
  testWidgets('thirty rows in a panel that scrolls, with semantics on', (
    WidgetTester tester,
  ) async {
    // The thing that makes this different from every other outliner test:
    // semantics are actually built. A screen reader, the accessibility
    // inspector and `flutter test`'s own `bySemanticsLabel` all turn this on,
    // and until they do a broken semantics tree costs nothing and says
    // nothing.
    final SemanticsHandle handle = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        theme: modelerTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 250,
            // Shorter than thirty rows: the rows past it are laid out and
            // hidden, which is the case that broke.
            height: 220,
            child: SingleChildScrollView(
              child: Outliner(
                objects: _tree(30),
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

    // Mutation: build a row whose semantics the framework cannot reconcile.
    // The outliner is the one list in this application long enough to scroll
    // — a rig is forty bones — and a semantics tree that throws throws every
    // frame after it, which is a screen reader finding the editor unusable
    // rather than merely unlabelled.
    //
    // **This is not the whole of the fault `ux-14` left behind.**
    // `tutorial_case_screenshots_test.dart`'s own imported robot still
    // crashes in `_RenderObjectSemantics._buildSemanticsSubtree` on a null
    // `geometry`, and thirty rows in a bare panel are not enough to
    // reproduce it — something further out in the real screen is part of the
    // shape. This holds the half that can be held here while that is found.
    expect(tester.takeException(), isNull);
    handle.dispose();
  });
}
