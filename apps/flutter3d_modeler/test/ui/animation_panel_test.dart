/// `anim-07`'s own `AnimationPanel`, stateless as of `S2`: which clip is
/// open, which joint and constraint are highlighted are all read from props
/// now, since `ModelerShell.bottom`'s own timeline needs the same selection
/// this panel used to keep to itself.
///
///     flutter test test/ui/animation_panel_test.dart
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Key;
import 'package:flutter3d_modeler/l10n/app_localizations.dart';
import 'package:flutter3d_modeler/src/ui/animation_panel.dart';
import 'package:flutter3d_modeler/src/ui/constraints_list.dart';
import 'package:flutter3d_modeler/src/ui/skeleton_tree.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

ProjectClip _clip(String name) => ProjectClip(
  name: name,
  tracks: <ProjectTrack>[
    ProjectTrack(
      objectId: 1,
      track: AnimationTrack(
        nodeIndex: 0,
        path: AnimationPath.translation,
        interpolation: AnimationInterpolation.linear,
        times: Float32List.fromList(<double>[0.0, 1.0]),
        values: Float32List.fromList(<double>[0, 0, 0, 1, 0, 0]),
        componentCount: 3,
      ),
    ),
  ],
);

Future<void> _pump(
  WidgetTester tester, {
  required List<ProjectClip> clips,
  int? selectedClip,
  ValueChanged<int>? onSelectClip,
  ProjectSkeleton? skeleton,
  List<ModelObject> objects = const <ModelObject>[],
  int? selectedJoint,
  ValueChanged<int>? onSelectJoint,
  int? selectedConstraint,
  ValueChanged<int>? onSelectConstraint,
}) => tester.pumpWidget(
  MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: AnimationPanel(
        clips: clips,
        objects: objects,
        skeleton: skeleton,
        onAddClip: () {},
        selectedClip: selectedClip,
        onSelectClip: onSelectClip ?? (_) {},
        selectedJoint: selectedJoint,
        onSelectJoint: onSelectJoint ?? (_) {},
        selectedConstraint: selectedConstraint,
        onSelectConstraint: onSelectConstraint ?? (_) {},
      ),
    ),
  ),
);

void main() {
  testWidgets('picking a clip in the action list reports its index', (
    WidgetTester tester,
  ) async {
    final selected = <int>[];
    await _pump(
      tester,
      clips: <ProjectClip>[_clip('walk'), _clip('run')],
      onSelectClip: selected.add,
    );

    await tester.tap(find.text('run'));
    await tester.pump();

    expect(selected, <int>[1]);
  });

  testWidgets('the caller\'s own selectedClip is what highlights the row', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      clips: <ProjectClip>[_clip('walk'), _clip('run')],
      selectedClip: 1,
    );

    expect(find.text('run'), findsOneWidget);
  });

  testWidgets('no skeleton means no tree and no constraint list', (
    WidgetTester tester,
  ) async {
    await _pump(tester, clips: <ProjectClip>[_clip('walk')]);

    expect(find.byType(SkeletonTree), findsNothing);
    expect(find.byType(ConstraintsList), findsNothing);
  });

  testWidgets('a skeleton draws the tree and the constraint list', (
    WidgetTester tester,
  ) async {
    final skeleton = ProjectSkeleton(
      joints: const <int>[1],
      inverseBindMatrices: <vm.Matrix4>[vm.Matrix4.identity()],
    );

    await _pump(
      tester,
      clips: <ProjectClip>[_clip('walk')],
      skeleton: skeleton,
      objects: <ModelObject>[
        ModelObject(
          id: 1,
          name: 'root',
          geometry: const SocketGeometry(),
          transform: vm.Matrix4.identity(),
        ),
      ],
    );

    expect(find.byType(SkeletonTree), findsOneWidget);
    expect(find.byType(ConstraintsList), findsOneWidget);
  });

  testWidgets('selecting a joint reports its id', (WidgetTester tester) async {
    final selected = <int>[];
    final skeleton = ProjectSkeleton(
      joints: const <int>[1],
      inverseBindMatrices: <vm.Matrix4>[vm.Matrix4.identity()],
    );

    await _pump(
      tester,
      clips: <ProjectClip>[_clip('walk')],
      skeleton: skeleton,
      objects: <ModelObject>[
        ModelObject(
          id: 1,
          name: 'root',
          geometry: const SocketGeometry(),
          transform: vm.Matrix4.identity(),
        ),
      ],
      onSelectJoint: selected.add,
    );

    await tester.tap(find.text('root'));
    await tester.pump();

    expect(selected, <int>[1]);
  });
}
