/// The object's name, editable — a box that commits on Enter, not on every
/// keystroke.
///
///     flutter test test/name_field_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_modeler/l10n/app_localizations.dart';
import 'package:flutter3d_modeler/src/ui/properties/name_field.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> show(
  WidgetTester tester, {
  required String name,
  required ValueChanged<String> onRenamed,
}) => tester.pumpWidget(
  MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: NameField(name: name, onRenamed: onRenamed),
    ),
  ),
);

void main() {
  testWidgets('the object\'s own name starts in the box', (
    WidgetTester tester,
  ) async {
    await show(tester, name: 'Left Arm', onRenamed: (_) {});

    expect(find.text('Left Arm'), findsOneWidget);
  });

  testWidgets('typing a name and pressing enter calls onRenamed', (
    WidgetTester tester,
  ) async {
    String? renamedTo;
    await show(tester, name: 'Arm', onRenamed: (String to) => renamedTo = to);

    await tester.enterText(find.byType(TextField), 'Right Arm');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    // Mutation: call onRenamed on every keystroke instead of on commit,
    // which is what would turn one rename into a move to every prefix of it.
    expect(renamedTo, 'Right Arm');
  });

  testWidgets('clearing the box and committing leaves the name unchanged', (
    WidgetTester tester,
  ) async {
    var calls = 0;
    await show(tester, name: 'Arm', onRenamed: (_) => calls++);

    await tester.enterText(find.byType(TextField), '');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    // An empty name is refused rather than sent onward — `_commit`'s own
    // doc says so. Mutation: send it anyway, which would leave the object
    // with no name at all the moment somebody clears the box by accident.
    expect(calls, 0);
    expect(find.text('Arm'), findsOneWidget);
  });
}
