/// `anim-18`'s own right panel: the bone-map table's unmapped rows, root
/// motion, the corrections, and the apply button's own gate.
///
///     flutter test test/retarget_panel_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart' show BoneMap;
import 'package:flutter3d_modeler/l10n/app_localizations.dart';
import 'package:flutter3d_modeler/src/ui/retarget_panel.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
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
  List<String> targetNames = const <String>[],
  void Function(String source, String? target)? onMapBone,
}) => tester.pumpWidget(
  MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
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
            targetNames: targetNames,
            onMapBone: onMapBone,
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

  group("ux-46: a bone map row a person can correct", () {
    testWidgets('with no target rig the table stays read-only', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        sourceNames: const <String>['hips', 'spine'],
        boneMap: const BoneMap(<String, String>{'hips': 'Hips'}),
      );

      // A picker of no bones is a control that can only be opened and shut
      // again. Mutation: draw it regardless, and every row of a panel with
      // nothing to retarget onto becomes a dropdown offering "unmapped".
      expect(find.byType(DropdownButton<String?>), findsNothing);
      expect(find.text('Hips'), findsOneWidget);
    });

    testWidgets('and with one, each row picks from the target\'s own joints', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        sourceNames: const <String>['hips', 'spine'],
        boneMap: const BoneMap(<String, String>{'hips': 'Hips'}),
        targetNames: const <String>['Hips', 'Spine', 'Head'],
        onMapBone: (String source, String? target) {},
      );

      expect(find.byType(DropdownButton<String?>), findsNWidgets(2));
    });

    testWidgets('changing a row reports the pair, and clearing it reports '
        'nothing', (WidgetTester tester) async {
      final changes = <String>[];
      await _pump(
        tester,
        sourceNames: const <String>['spine'],
        boneMap: const BoneMap(<String, String>{'spine': 'Spine'}),
        targetNames: const <String>['Hips', 'Spine', 'Head'],
        onMapBone: (String source, String? target) =>
            changes.add('$source -> ${target ?? 'nothing'}'),
      );

      // **Automatic mapping gets most of a humanoid and misses the two that
      // matter.** Mutation: leave the table read-only, which is what it
      // was — "the left hand went to the right elbow" is then a thing to
      // fix by renaming bones in another application.
      await tester.tap(find.byKey(const ValueKey<String>('bone-map-spine')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Head').last);
      await tester.pumpAndSettle();
      expect(changes.single, 'spine -> Head');

      // And "unmapped" is a real choice rather than only a state: a bone
      // the guess got wrong is one somebody wants to take off as often as
      // move.
      await tester.tap(find.byKey(const ValueKey<String>('bone-map-spine')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('unmapped').last);
      await tester.pumpAndSettle();
      expect(changes.last, 'spine -> nothing');
    });
  });
}
