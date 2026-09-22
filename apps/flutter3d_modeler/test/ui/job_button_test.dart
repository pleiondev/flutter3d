/// `JobButton`: the visible half of a background bake — `ui-25`'s own row.
///
///     flutter test test/ui/job_button_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_modeler/l10n/app_localizations.dart';
import 'package:flutter3d_modeler/src/ui/job_button.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> show(
  WidgetTester tester, {
  double? progress,
  VoidCallback? onStart,
  VoidCallback? onCancel,
}) => tester.pumpWidget(
  MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: JobButton(
        label: 'Bake modifiers',
        progress: progress,
        onStart: onStart ?? () {},
        onCancel: onCancel ?? () {},
      ),
    ),
  ),
);

void main() {
  group('idle', () {
    testWidgets('shows the label and starts on a tap', (
      WidgetTester tester,
    ) async {
      var started = false;
      await show(tester, onStart: () => started = true);

      expect(find.text('Bake modifiers'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsNothing);

      await tester.tap(find.byType(ElevatedButton));
      expect(started, isTrue);
    });
  });

  group('running', () {
    testWidgets('shows progress instead of the label, and a cancel button', (
      WidgetTester tester,
    ) async {
      await show(tester, progress: 0.3);

      expect(find.text('Bake modifiers'), findsNothing);
      expect(find.text('30%'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('cancels on a tap, not starts', (WidgetTester tester) async {
      var started = false;
      var cancelled = false;
      await show(
        tester,
        progress: 0.5,
        onStart: () => started = true,
        onCancel: () => cancelled = true,
      );

      await tester.tap(find.byIcon(Icons.close));
      expect(cancelled, isTrue);
      expect(started, isFalse);
    });

    testWidgets('the indicator carries the exact progress value', (
      WidgetTester tester,
    ) async {
      await show(tester, progress: 0.7);
      final indicator = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(indicator.value, 0.7);
    });
  });
}
