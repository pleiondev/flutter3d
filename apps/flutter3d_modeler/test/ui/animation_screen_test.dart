/// `anim-07`'s own screen 07: composing `ActionsList`, `SkeletonTree`,
/// `ConstraintsList` and `TimelinePanel`.
///
///     flutter test test/ui/animation_screen_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/ui/actions_list.dart';
import 'package:flutter3d_modeler/src/ui/animation_screen.dart';
import 'package:flutter3d_modeler/src/ui/constraints_list.dart';
import 'package:flutter3d_modeler/src/ui/skeleton_tree.dart';
import 'package:flutter3d_modeler/src/ui/timeline_panel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

ModelObject _object(int id, String name, {int? parent}) => ModelObject(
  id: id,
  name: name,
  geometry: const SocketGeometry(),
  transform: vm.Matrix4.identity(),
  parent: parent,
);

/// hips(1) → spine(2) → arm(3)
List<ModelObject> _rig() => <ModelObject>[
  _object(1, 'hips'),
  _object(2, 'spine', parent: 1),
  _object(3, 'arm', parent: 2),
];

ProjectSkeleton _skeleton() => ProjectSkeleton(
  joints: const <int>[1, 2, 3],
  inverseBindMatrices: <vm.Matrix4>[
    vm.Matrix4.identity(),
    vm.Matrix4.identity(),
    vm.Matrix4.identity(),
  ],
);

IkConstraint _armConstraint() => IkConstraint(
  rootJointId: 1,
  midJointId: 2,
  effectorJointId: 3,
  target: vm.Vector3(1, 0, 0),
  pole: vm.Vector3(0, 1, 0),
);

Widget _screen({
  int? selectedClip,
  ValueChanged<int>? onSelectClip,
  int? selectedJoint,
  ValueChanged<int>? onSelectJoint,
  int? selectedConstraint,
  ValueChanged<int>? onSelectConstraint,
}) => MaterialApp(
  home: Material(
    child: AnimationScreen(
      viewport: const Placeholder(key: ValueKey<String>('viewport')),
      objects: _rig(),
      clips: const <ProjectClip>[
        ProjectClip(name: 'walk', tracks: <ProjectTrack>[]),
      ],
      selectedClip: selectedClip,
      onSelectClip: onSelectClip ?? (_) {},
      onAddClip: () {},
      skeleton: _skeleton(),
      selectedJoint: selectedJoint,
      onSelectJoint: onSelectJoint ?? (_) {},
      constraints: <IkConstraint>[_armConstraint()],
      selectedConstraint: selectedConstraint,
      onSelectConstraint: onSelectConstraint ?? (_) {},
      clipIndex: 0,
      clip: const ProjectClip(name: 'walk', tracks: <ProjectTrack>[]),
      time: 0.0,
    ),
  ),
);

void main() {
  testWidgets(
    'composes the viewport, the clip list, the skeleton, the constraints '
    'and the timeline',
    (WidgetTester tester) async {
      await tester.pumpWidget(_screen());

      expect(find.byKey(const ValueKey<String>('viewport')), findsOneWidget);
      expect(find.byType(ActionsList), findsOneWidget);
      expect(find.byType(SkeletonTree), findsOneWidget);
      expect(find.byType(ConstraintsList), findsOneWidget);
      expect(find.byType(TimelinePanel), findsOneWidget);
      expect(find.text('walk'), findsWidgets);
      expect(find.text('hips'), findsOneWidget);
    },
  );

  testWidgets('tapping a clip reports its own index', (
    WidgetTester tester,
  ) async {
    int? selected;
    await tester.pumpWidget(_screen(onSelectClip: (int i) => selected = i));

    await tester.tap(find.text('walk').first);
    await tester.pump();

    expect(selected, 0);
  });

  testWidgets('tapping a joint reports its own id, not always the first', (
    WidgetTester tester,
  ) async {
    int? selected;
    await tester.pumpWidget(
      _screen(onSelectJoint: (int id) => selected = id),
    );

    await tester.tap(find.text('arm'));
    await tester.pump();

    expect(selected, 3);
  });

  testWidgets(
    'the constraint list names the joint through the skeleton\'s own '
    'objects, not a bare id',
    (WidgetTester tester) async {
      await tester.pumpWidget(_screen());

      // `_armConstraint`'s own `rootJointId: 1` is `hips` in `_rig()` — the
      // row this proves is reading through `AnimationScreen`'s own
      // `_jointName`, not falling back to `joint 1`.
      expect(find.textContaining('hips'), findsWidgets);
      expect(find.textContaining('joint 1'), findsNothing);
    },
  );
}
