/// [RestoreAutosaveDialog]: `ui-18`'s own "предложение восстановить", now
/// naming how much it would bring back through the ARB's own pluralized
/// `restoreUnsavedChangesBody` rather than a hand-rolled `countLabel`.
///
///     flutter test test/restore_autosave_dialog_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_modeler/l10n/app_localizations.dart';
import 'package:flutter3d_modeler/src/ui/restore_autosave_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _harness(
  Locale locale,
  int objectCount,
  void Function(bool?) onAnswered,
) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Builder(
      builder: (BuildContext context) => ElevatedButton(
        onPressed: () async {
          onAnswered(
            await RestoreAutosaveDialog.show(context, objectCount: objectCount),
          );
        },
        child: const Text('open'),
      ),
    ),
  ),
);

void main() {
  testWidgets('shows the English strings, singular count, under the default '
      'locale', (WidgetTester tester) async {
    await tester.pumpWidget(_harness(const Locale('en'), 1, (_) {}));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Restore unsaved changes?'), findsOneWidget);
    expect(
      find.text(
        'An autosave from a session that did not close cleanly was found '
        '(1 object).',
      ),
      findsOneWidget,
    );
    expect(find.text('Discard'), findsOneWidget);
    expect(find.text('Restore'), findsOneWidget);
  });

  testWidgets('shows the Russian strings, plural count, under Locale(ru)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_harness(const Locale('ru'), 5, (_) {}));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Восстановить несохранённые изменения?'), findsOneWidget);
    expect(
      find.text(
        'Найден автосохранённый файл сессии, которая закрылась некорректно '
        '(5 объектов).',
      ),
      findsOneWidget,
    );
    expect(find.text('Не сохранять'), findsOneWidget);
    expect(find.text('Восстановить'), findsOneWidget);
  });

  testWidgets('choosing to restore answers true', (WidgetTester tester) async {
    bool? answer;
    await tester.pumpWidget(
      _harness(const Locale('en'), 2, (bool? it) => answer = it),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();

    expect(answer, isTrue);
  });
}
