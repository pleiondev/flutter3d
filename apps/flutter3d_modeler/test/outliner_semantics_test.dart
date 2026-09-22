/// The outliner with a screen reader listening and more rows than fit — the
/// shape that stopped the framework building a semantics tree at all.
///
///     flutter test test/outliner_semantics_test.dart
library;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/l10n/app_localizations.dart';
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
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: modelerTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 250,
            // Shorter than the outliner's own region as well as than thirty
            // rows, so the panel clips it too: both halves of the shape that
            // broke are here.
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
    expect(tester.takeException(), isNull);

    // And the reason it holds: thirty objects are not thirty rows. A
    // `Column` of all of them is twenty-odd render objects the panel has
    // clipped away and twenty-odd semantics nodes with no geometry computed
    // for them, which is what `_RenderObjectSemantics._buildSemanticsSubtree`
    // walked into on `tutorial_case_screenshots_test.dart`'s imported robot
    // — a crash this test could not reproduce until the outliner was the
    // thing being counted rather than the thing being wrapped.
    expect(find.byTooltip('Hide'), findsNWidgets(10));
    handle.dispose();
  });
}
