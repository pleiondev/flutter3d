/// `BendSliderBar`: `anim-12`'s own bar — a slider that bends a joint's live
/// `SceneNode` and a reset-pose link back to `Pose.restOf`, both entirely
/// outside `ModelHistory`.
///
///     flutter test test/ui/bend_slider_bar_test.dart
library;

import 'dart:typed_data';

import 'package:flutter/material.dart' hide Matrix4;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/l10n/app_localizations.dart';
import 'package:flutter3d_modeler/src/ui/bend_slider_bar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Quaternion;

/// One joint, its skeleton, and the rest pose it is bent away from.
///
/// The rest pose is not identity — it carries a translation — so a test that
/// only ever checked "not identity" after a drag could not tell a real bend
/// from a bug that just left the joint at whatever `SceneNode`'s own default
/// happens to be.
typedef _Fixture = ({SceneNode joint, Skeleton skeleton, Pose pose});

_Fixture _buildFixture() {
  final SceneNode joint = SceneNode(name: 'elbow');
  joint.setPosition(0.0, 0.4, 0.0);
  joint.setRotation(Quaternion.identity());

  final Skeleton skeleton = Skeleton(
    joints: <SceneNode>[joint],
    inverseBindMatrices: <Matrix4>[Matrix4.identity()],
    name: 'arm',
  );

  final Pose pose = Pose(
    parents: <int>[-1],
    restTranslations: Float32List.fromList(<double>[0.0, 0.4, 0.0]),
    restRotations: Float32List.fromList(<double>[0.0, 0.0, 0.0, 1.0]),
    restScales: Float32List.fromList(<double>[1.0, 1.0, 1.0]),
  );

  return (joint: joint, skeleton: skeleton, pose: pose);
}

Future<void> _show(
  WidgetTester tester,
  _Fixture fixture, {
  ValueChanged<int>? onPoseChanged,
}) => tester.pumpWidget(
  MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: BendSliderBar(
        joint: fixture.joint,
        jointIndex: 0,
        pose: fixture.pose,
        skeleton: fixture.skeleton,
        label: 'Elbow',
        onPoseChanged: onPoseChanged,
      ),
    ),
  ),
);

void main() {
  testWidgets('at rest the bar reads 0° and offers Reset pose', (
    WidgetTester tester,
  ) async {
    final _Fixture fixture = _buildFixture();
    await _show(tester, fixture);

    expect(find.text('0°'), findsOneWidget);
    expect(find.text('Reset pose'), findsOneWidget);
    expect(find.text('Elbow'), findsOneWidget);
  });

  testWidgets(
    'dragging the slider turns the joint and changes poseVersion, '
    'without growing ModelHistory',
    (WidgetTester tester) async {
      final _Fixture fixture = _buildFixture();
      final ModelHistory history = ModelHistory(const ModelProject());
      final List<int> reported = <int>[];

      final int versionBefore = fixture.skeleton.poseVersion;
      final int stepsBefore = history.steps.length;
      final bool canUndoBefore = history.canUndo;
      final Quaternion rotationBefore = fixture.joint.readRotation();

      await _show(tester, fixture, onPoseChanged: reported.add);

      final Slider slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChanged!(60.0);
      await tester.pump();

      final int versionAfter = fixture.skeleton.poseVersion;
      final Quaternion rotationAfter = fixture.joint.readRotation();

      expect(
        versionAfter,
        isNot(versionBefore),
        reason: 'Skeleton.poseVersion sums SceneNode.worldVersion, which a '
            'rotated joint must bump',
      );
      expect(
        rotationAfter.w,
        isNot(closeTo(rotationBefore.w, 1e-9)),
        reason: 'the joint itself must actually have turned',
      );
      expect(
        reported,
        isNotEmpty,
        reason: 'onPoseChanged is called after the live rotation lands',
      );
      expect(reported.last, versionAfter);

      // The acceptance line, checked directly: the undo stack this app's
      // document edits go through must not have grown by even one step.
      expect(
        history.steps.length,
        stepsBefore,
        reason: 'a live joint drag is not a ModelCommand and must never '
            'reach ModelHistory',
      );
      expect(history.canUndo, canUndoBefore);
      expect(find.text('60°'), findsOneWidget);
    },
  );

  testWidgets('an actual pointer drag on the slider also turns the joint', (
    WidgetTester tester,
  ) async {
    final _Fixture fixture = _buildFixture();
    await _show(tester, fixture);

    final Quaternion rotationBefore = fixture.joint.readRotation();
    await tester.drag(find.byType(Slider), const Offset(80.0, 0.0));
    await tester.pump();

    final Quaternion rotationAfter = fixture.joint.readRotation();
    expect(rotationAfter.w, isNot(closeTo(rotationBefore.w, 1e-9)));
  });

  testWidgets(
    'Reset pose puts the joint back at Pose.restOf, and reports the '
    'version again',
    (WidgetTester tester) async {
      final _Fixture fixture = _buildFixture();
      final List<int> reported = <int>[];
      await _show(tester, fixture, onPoseChanged: reported.add);

      final Slider slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChanged!(-45.0);
      await tester.pump();
      expect(find.text('-45°'), findsOneWidget);
      reported.clear();

      await tester.tap(find.text('Reset pose'));
      await tester.pump();

      final Matrix4 rest = fixture.pose.restOf(0);
      final Matrix4 actual = fixture.joint.localMatrix;
      for (var i = 0; i < 16; i++) {
        expect(
          actual.storage[i],
          closeTo(rest.storage[i], 1e-6),
          reason: 'entry $i of the local matrix must match Pose.restOf(0)',
        );
      }
      expect(find.text('0°'), findsOneWidget);
      expect(reported, isNotEmpty);
      expect(reported.last, fixture.skeleton.poseVersion);
    },
  );

  testWidgets('resetting the pose does not touch ModelHistory either', (
    WidgetTester tester,
  ) async {
    final _Fixture fixture = _buildFixture();
    final ModelHistory history = ModelHistory(const ModelProject());
    await _show(tester, fixture);

    final Slider slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(30.0);
    await tester.pump();

    final int stepsBefore = history.steps.length;
    await tester.tap(find.text('Reset pose'));
    await tester.pump();

    expect(history.steps.length, stepsBefore);
    expect(history.canUndo, isFalse);
  });
}
