/// `anim-24`'s own measurement report, pinned to the viewport's corner.
///
///     flutter test test/measurement_report_overlay_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_modeler/src/ui/measurement_report_overlay.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the report text is shown', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Stack(
          children: <Widget>[MeasurementReportOverlay(said: 'opened in 12 ms')],
        ),
      ),
    );

    expect(find.text('opened in 12 ms'), findsOneWidget);
  });
}
