/// A label and a value, on one properties-panel row.
///
///     flutter test test/label_value_row_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_modeler/src/ui/properties/label_value_row.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> show(WidgetTester tester, String label, String value) =>
    tester.pumpWidget(
      MaterialApp(
        theme: modelerTheme(),
        home: Scaffold(body: LabelValueRow(label, value)),
      ),
    );

void main() {
  testWidgets('both the label and the value are shown', (
    WidgetTester tester,
  ) async {
    await show(tester, 'Triangles', '1240');

    expect(find.text('Triangles'), findsOneWidget);
    expect(find.text('1240'), findsOneWidget);
  });

  testWidgets('the row is the height a properties-panel row is', (
    WidgetTester tester,
  ) async {
    await show(tester, 'Profile', 'game');

    // Mutation: a bare height literal that drifts from `ModelerMetrics.row`
    // the day the panel's own row height changes.
    expect(
      tester.getSize(find.byType(LabelValueRow)).height,
      ModelerMetrics.row,
    );
  });
}
