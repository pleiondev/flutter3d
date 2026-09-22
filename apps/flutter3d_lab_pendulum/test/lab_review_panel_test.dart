/// `LabReviewPanel` — `ls-e-01`'s teacher screen, proven on its own inputs
/// rather than through the full app (which opens a real `GraphicsDevice`
/// `pendulum_lab_panel_test.dart` avoids for the same reason).
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_lab/flutter3d_lab.dart';
import 'package:flutter3d_lab_pendulum/src/lab_review_panel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('no divergence reads as the assignment held the whole way', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LabReviewPanel(
          assignedLength: 1.2,
          divergence: null,
          stepsPerSecond: 60,
        ),
      ),
    );

    expect(find.textContaining('No divergence'), findsOneWidget);
    expect(find.textContaining('1.20 m'), findsOneWidget);
  });

  testWidgets('a divergence names the step, the time, and both lengths', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LabReviewPanel(
          assignedLength: 1.2,
          divergence: const LabDivergence(
            step: 120,
            assigned: 1.2,
            actual: 1.5,
          ),
          stepsPerSecond: 60,
        ),
      ),
    );

    expect(find.textContaining('step 120'), findsOneWidget);
    // 120 steps at 60 steps/second is exactly two seconds.
    expect(find.textContaining('t = 2.0 s'), findsOneWidget);
    expect(find.textContaining('1.20 m'), findsOneWidget);
    expect(find.textContaining('1.50 m'), findsOneWidget);
  });

  testWidgets('the close button dismisses the dialog', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => const LabReviewPanel(
                assignedLength: 1.2,
                divergence: null,
                stepsPerSecond: 60,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(LabReviewPanel), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(LabReviewPanel), findsNothing);
  });
}
