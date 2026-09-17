/// `ui-33d`'s own "Save without history" checkbox, asked ahead of the native
/// "Save as" panel.
///
///     flutter test test/save_as_dialog_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_modeler/l10n/app_localizations.dart';
import 'package:flutter3d_modeler/src/ui/save_as_dialog.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps a screen with one button that opens [showSaveAsScreen] and stashes
/// whatever it is eventually popped with into [into] — a plain return value
/// would freeze at whatever the dialog held the moment the button was
/// tapped, before a test has had the chance to touch the checkbox or press
/// anything in it.
Future<void> openOver(
  WidgetTester tester, {
  required void Function(SaveAsChoice?) into,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: modelerTheme(),
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => ElevatedButton(
            onPressed: () async {
              into(await showSaveAsScreen(context));
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('the save as dialog', () {
    testWidgets(
      'Save with the checkbox untouched answers includeHistory: true',
      (WidgetTester tester) async {
        SaveAsChoice? result;
        await openOver(tester, into: (SaveAsChoice? choice) => result = choice);

        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.pumpAndSettle();

        expect(result, isNotNull);
        expect(result!.includeHistory, isTrue);
      },
    );

    testWidgets(
      'ticking "Save without history" answers includeHistory: false',
      (WidgetTester tester) async {
        SaveAsChoice? result;
        await openOver(tester, into: (SaveAsChoice? choice) => result = choice);

        // Mutation: read `_withoutHistory` instead of its negation when
        // building the answer — this test would still pass on the default
        // (untouched) case above but fail here, since the checkbox has
        // actually been ticked.
        await tester.tap(find.text('Save without history'));
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.pumpAndSettle();

        expect(result, isNotNull);
        expect(result!.includeHistory, isFalse);
      },
    );

    testWidgets('Cancel answers null, the same as a dismissed native panel', (
      WidgetTester tester,
    ) async {
      // Mutation: drop the `Navigator.pop()` call inside Cancel's own
      // `onPressed` — the dialog would stay open and this tap would find
      // nothing further to press, rather than quietly leaving `result` at
      // whatever it already was.
      SaveAsChoice? result = const SaveAsChoice(includeHistory: false);
      await openOver(tester, into: (SaveAsChoice? choice) => result = choice);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(result, isNull);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });
}
