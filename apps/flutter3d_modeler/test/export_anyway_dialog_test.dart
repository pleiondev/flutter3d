/// [ExportAnywayDialog]: the export-readiness question, still hard-coded
/// English — there is no ARB entry for it yet, and this file exists to prove
/// that stays true under `Locale('ru')` too, not only under the default.
///
///     flutter test test/export_anyway_dialog_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/l10n/app_localizations.dart';
import 'package:flutter3d_modeler/src/ui/export_anyway_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

final _blocked = ExportBlocked(<ExportIssue>[
  const ExportIssue(ExportSeverity.error, 'Object "arm" has an empty mesh.'),
  const ExportIssue(
    ExportSeverity.error,
    'Object "leg" has a face with no area.',
  ),
]);

Widget _harness(
  Locale locale,
  List<ExportIssue> issues,
  void Function(bool) onAnswered,
) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Builder(
      builder: (BuildContext context) => ElevatedButton(
        onPressed: () async {
          onAnswered(
            await ExportAnywayDialog.show(
              context,
              blocked: _blocked,
              issues: issues,
            ),
          );
        },
        child: const Text('open'),
      ),
    ),
  ),
);

void main() {
  testWidgets('shows the English strings under the default locale', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _harness(const Locale('en'), _blocked.issues, (_) {}),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Export anyway?'), findsOneWidget);
    expect(find.text(_blocked.says), findsOneWidget);
    expect(find.text('Object "arm" has an empty mesh.'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Export anyway'), findsOneWidget);
  });

  testWidgets('and reads Russian under Locale(ru) — ux-22', (
    WidgetTester tester,
  ) async {
    // **This test used to assert the opposite**, and said so in its own
    // name: there was no ARB entry for this dialog, so it stayed English
    // whatever the interface was set to. `ux-22` gave it one, and a test
    // that still expected English would have been the thing keeping the
    // dialog untranslated.
    await tester.pumpWidget(
      _harness(const Locale('ru'), _blocked.issues, (_) {}),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Всё равно экспортировать?'), findsOneWidget);
    expect(find.text('Отмена'), findsOneWidget);
    expect(find.text('Всё равно экспортировать'), findsOneWidget);
  });

  testWidgets('truncates past five issues with a count of the rest', (
    WidgetTester tester,
  ) async {
    final issues = <ExportIssue>[
      for (int i = 0; i < 7; i++)
        ExportIssue(ExportSeverity.error, 'Issue number $i.'),
    ];
    await tester.pumpWidget(_harness(const Locale('en'), issues, (_) {}));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Issue number 4.'), findsOneWidget);
    expect(find.text('Issue number 5.'), findsNothing);
    expect(find.text('and 2 more'), findsOneWidget);
  });

  testWidgets('choosing cancel answers false', (WidgetTester tester) async {
    bool? answer;
    await tester.pumpWidget(
      _harness(const Locale('en'), _blocked.issues, (bool it) => answer = it),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(answer, isFalse);
  });
}
