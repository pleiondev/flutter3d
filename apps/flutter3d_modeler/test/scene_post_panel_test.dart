/// `mat-24`'s own post panel: bloom and exposure.
///
///     flutter test test/scene_post_panel_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/ui/scene_post_panel.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester, {
  ScenePostSettings post = const ScenePostSettings(),
  double exposure = 1.6,
  ValueChanged<bool>? onBloomChanged,
  ValueChanged<double>? onExposureChanged,
}) => tester.pumpWidget(
  MaterialApp(
    theme: modelerTheme(),
    home: Scaffold(
      body: ScenePostPanel(
        post: post,
        exposure: exposure,
        onBloomChanged: onBloomChanged ?? (_) {},
        onExposureChanged: onExposureChanged ?? (_) {},
      ),
    ),
  ),
);

void main() {
  testWidgets('shows the current bloom flag and exposure', (tester) async {
    await _pump(
      tester,
      post: const ScenePostSettings(bloomEnabled: false),
      exposure: 2.0,
    );

    final Switch toggle = tester.widget(find.byType(Switch));
    expect(toggle.value, isFalse);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('toggling bloom reports the new value', (tester) async {
    final reported = <bool>[];
    await _pump(
      tester,
      post: const ScenePostSettings(),
      onBloomChanged: reported.add,
    );

    await tester.tap(find.byType(Switch));

    // Mutation: report the flag unflipped, or the widget's own starting
    // value regardless of which way the switch actually moved.
    expect(reported, <bool>[false]);
  });

  testWidgets('editing exposure reports the new number', (tester) async {
    final reported = <double>[];
    await _pump(tester, exposure: 1.6, onExposureChanged: reported.add);

    await tester.enterText(find.widgetWithText(TextField, '1.6'), '2.4');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(reported, <double>[2.4]);
  });
}
