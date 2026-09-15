/// `anim-18`'s own right panel: the bone-map table's unmapped rows, root
/// motion, the corrections, and the apply button's own gate.
///
///     flutter test test/retarget_panel_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_modeler/src/ui/retarget_panel.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter3d_rig/flutter3d_rig.dart' show BoneMap;
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester, {
  List<String> sourceNames = const <String>[],
  BoneMap boneMap = const BoneMap(<String, String>{}),
  VoidCallback? onAutoMap,
  RetargetRootMotion rootMotion = RetargetRootMotion.inAnimation,
  ValueChanged<RetargetRootMotion>? onRootMotionChanged,
  bool lockFeet = true,
  ValueChanged<bool>? onLockFeetChanged,
  double groundY = 0.0,
  ValueChanged<double>? onGroundYChanged,
  double footTolerance = 1e-3,
  ValueChanged<double>? onFootToleranceChanged,
  bool canApply = false,
  VoidCallback? onApply,
}) => tester.pumpWidget(
  MaterialApp(
    theme: modelerTheme(),
    home: Scaffold(
      body: SizedBox(
        width: 300,
        child: SingleChildScrollView(
          child: RetargetPanel(
            sourceNames: sourceNames,
            boneMap: boneMap,
            onAutoMap: onAutoMap ?? () {},
            rootMotion: rootMotion,
            onRootMotionChanged: onRootMotionChanged ?? (_) {},
            lockFeet: lockFeet,
            onLockFeetChanged: onLockFeetChanged ?? (_) {},
            groundY: groundY,
            onGroundYChanged: onGroundYChanged ?? (_) {},
            footTolerance: footTolerance,
            onFootToleranceChanged: onFootToleranceChanged ?? (_) {},
            canApply: canApply,
            onApply: onApply,
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('an unmapped bone reads in the tertiary warning colour', (
    tester,
  ) async {
    await _pump(
      tester,
      sourceNames: const <String>['hips', 'leftElbow'],
      boneMap: const BoneMap(<String, String>{'hips': 'root'}),
    );

    final Text mapped = tester.widget(find.text('hips'));
    expect(mapped.style?.color, isNot(kModelerScheme.tertiary));

    final Text unmapped = tester.widget(find.text('leftElbow'));
    expect(unmapped.style?.color, kModelerScheme.tertiary);
    expect(find.text('unmapped'), findsOneWidget);
  });

  testWidgets('"Map automatically" is disabled with nothing imported yet', (
    tester,
  ) async {
    var mapped = 0;
    await _pump(tester, onAutoMap: () => mapped++);

    final TextButton button = tester.widget(
      find.widgetWithText(TextButton, 'Map automatically'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('"Map automatically" runs once a source is imported', (
    tester,
  ) async {
    var mapped = 0;
    await _pump(
      tester,
      sourceNames: const <String>['hips'],
      onAutoMap: () => mapped++,
    );

    await tester.tap(find.text('Map automatically'));

    expect(mapped, 1);
  });

  testWidgets('the root motion switch reports the picked segment', (
    tester,
  ) async {
    final picked = <RetargetRootMotion>[];
    await _pump(tester, onRootMotionChanged: picked.add);

    await tester.tap(find.text('In code'));

    expect(picked, <RetargetRootMotion>[RetargetRootMotion.inCode]);
  });

  testWidgets('lock feet off disables the ground/tolerance fields', (
    tester,
  ) async {
    await _pump(tester, lockFeet: false);

    final fields = tester.widgetList<TextField>(find.byType(TextField));
    for (final field in fields) {
      expect(field.enabled, isFalse);
    }
  });

  testWidgets('apply is enabled only when canApply says so', (tester) async {
    await _pump(tester);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );

    var applied = 0;
    await _pump(tester, canApply: true, onApply: () => applied++);
    await tester.tap(find.text('Apply the retarget'));
    expect(applied, 1);
  });
}
