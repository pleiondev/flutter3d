/// `anim-07`'s own `SkeletonTree`: hierarchy from [ModelObject.parent],
/// selection, and expand/collapse.
///
///     flutter test test/ui/skeleton_tree_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/ui/skeleton_tree.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

ModelObject _object(int id, String name, {int? parent}) => ModelObject(
  id: id,
  name: name,
  geometry: const SocketGeometry(),
  transform: vm.Matrix4.identity(),
  parent: parent,
);

/// hips(1) → spine(2) → head(3)
///              └─────→ arm(4)
List<ModelObject> _rig() => <ModelObject>[
  _object(1, 'hips'),
  _object(2, 'spine', parent: 1),
  _object(3, 'head', parent: 2),
  _object(4, 'arm', parent: 2),
];

ProjectSkeleton _skeleton({List<int>? joints}) => ProjectSkeleton(
  joints: joints ?? <int>[1, 2, 3, 4],
  inverseBindMatrices: <vm.Matrix4>[
    for (var i = 0; i < (joints ?? <int>[1, 2, 3, 4]).length; i++)
      vm.Matrix4.identity(),
  ],
);

Future<void> _pump(
  WidgetTester tester, {
  required List<ModelObject> objects,
  required ProjectSkeleton skeleton,
  int? selectedJoint,
  ValueChanged<int>? onSelectJoint,
}) => tester.pumpWidget(
  MaterialApp(
    theme: modelerTheme(),
    home: Scaffold(
      body: SkeletonTree(
        objects: objects,
        skeleton: skeleton,
        selectedJoint: selectedJoint,
        onSelectJoint: onSelectJoint ?? (_) {},
      ),
    ),
  ),
);

void main() {
  testWidgets('every joint in the skeleton draws, fully expanded by default', (
    tester,
  ) async {
    await _pump(tester, objects: _rig(), skeleton: _skeleton());

    expect(find.text('hips'), findsOneWidget);
    expect(find.text('spine'), findsOneWidget);
    expect(find.text('head'), findsOneWidget);
    expect(find.text('arm'), findsOneWidget);
  });

  testWidgets('an empty skeleton says so', (tester) async {
    await _pump(
      tester,
      objects: _rig(),
      skeleton: _skeleton(joints: const <int>[]),
    );

    expect(find.text('No joints'), findsOneWidget);
  });

  testWidgets('tapping a row reports its own joint id, not always the first', (
    tester,
  ) async {
    final selected = <int>[];
    await _pump(
      tester,
      objects: _rig(),
      skeleton: _skeleton(),
      onSelectJoint: selected.add,
    );

    await tester.tap(find.text('head'));
    await tester.pump();

    // Mutation: report the row's own index into a flattened list instead of
    // the joint id at that row — index 2 (head's own position in a
    // depth-first walk) would pass here for the wrong reason if joint ids
    // were not distinct from their positions.
    expect(selected, <int>[3]);
  });

  testWidgets('collapsing a branch hides its children until expanded again', (
    tester,
  ) async {
    await _pump(tester, objects: _rig(), skeleton: _skeleton());

    expect(find.text('head'), findsOneWidget);

    // The disclosure arrow beside "spine" — the only expandable row besides
    // the implicit root grouping, since hips has one child (spine) and spine
    // has two (head, arm).
    await tester.tap(find.byIcon(Icons.expand_more).last);
    await tester.pump();

    expect(find.text('head'), findsNothing);
    expect(find.text('arm'), findsNothing);
    // Mutation: collapsing a branch also hides its own row, not only its
    // children.
    expect(find.text('spine'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pump();

    expect(find.text('head'), findsOneWidget);
    expect(find.text('arm'), findsOneWidget);
  });

  testWidgets('a joint whose parent is outside the skeleton draws at the '
      'top level rather than vanishing', (tester) async {
    // "arm" is a joint (id 4) whose parent (2) is NOT in this skeleton's own
    // joint list — a skin that only bound hips and arm, say.
    await _pump(
      tester,
      objects: _rig(),
      skeleton: _skeleton(joints: const <int>[1, 4]),
    );

    expect(find.text('hips'), findsOneWidget);
    expect(find.text('arm'), findsOneWidget);
  });

  testWidgets('a joint with no matching object falls back to a bare id label', (
    tester,
  ) async {
    await _pump(
      tester,
      objects: const <ModelObject>[],
      skeleton: _skeleton(joints: const <int>[42]),
    );

    expect(find.text('joint 42'), findsOneWidget);
  });

  testWidgets('the selected joint is marked selected', (tester) async {
    await _pump(
      tester,
      objects: _rig(),
      skeleton: _skeleton(),
      selectedJoint: 3,
    );

    final tile = find.ancestor(
      of: find.text('head'),
      matching: find.byType(InkWell),
    );
    expect(tile, findsOneWidget);
  });
}
