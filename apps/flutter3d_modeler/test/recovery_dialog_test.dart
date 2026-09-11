/// [RecoveryDialog]: the choice between an autosave and the last saved file,
/// asked rather than assumed.
///
///     flutter test test/recovery_dialog_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_modeler/src/ui/recovery_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _harness(void Function(bool) onAnswered) => MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (BuildContext context) => ElevatedButton(
        onPressed: () async {
          onAnswered(await RecoveryDialog.show(context));
        },
        child: const Text('open'),
      ),
    ),
  ),
);

void main() {
  testWidgets('shows both choices once asked', (WidgetTester tester) async {
    await tester.pumpWidget(_harness((bool _) {}));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Restore autosave'), findsOneWidget);
    expect(find.text('Open saved file'), findsOneWidget);
  });

  testWidgets('choosing to restore answers true', (WidgetTester tester) async {
    bool? answer;
    await tester.pumpWidget(_harness((bool it) => answer = it));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Restore autosave'));
    await tester.pumpAndSettle();

    expect(answer, isTrue);
  });

  testWidgets('choosing the saved file answers false', (
    WidgetTester tester,
  ) async {
    bool? answer;
    await tester.pumpWidget(_harness((bool it) => answer = it));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open saved file'));
    await tester.pumpAndSettle();

    expect(answer, isFalse);
  });

  testWidgets('tapping outside the dialog does not answer it', (
    WidgetTester tester,
  ) async {
    // Mutation: barrierDismissible true. This taps the barrier and expects
    // the dialog still open, so a dismiss that snuck an answer through
    // (null coerced to false by RecoveryDialog.show, indistinguishable from
    // an actual choice) would fail here instead of silently discarding the
    // newer document.
    bool? answer;
    await tester.pumpWidget(_harness((bool it) => answer = it));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // A point far from the dialog's own content, inside the modal barrier.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(find.text('Restore autosave'), findsOneWidget);
    expect(answer, isNull);
  });
}
