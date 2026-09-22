/// [UnsavedChangesDialog]: the three answers to "close a dirty document",
/// read from the ARB rather than hard-coded — `ui-22` says the interface
/// language and the diagnostic language are not the same one.
///
///     flutter test test/unsaved_changes_dialog_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_modeler/l10n/app_localizations.dart';
import 'package:flutter3d_modeler/src/close_guard.dart';
import 'package:flutter3d_modeler/src/ui/unsaved_changes_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _harness(Locale locale, void Function(UnsavedChoice?) onAnswered) =>
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => ElevatedButton(
            onPressed: () async {
              onAnswered(await UnsavedChangesDialog.show(context));
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
    await tester.pumpWidget(_harness(const Locale('en'), (_) {}));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Unsaved changes'), findsOneWidget);
    expect(
      find.text('This model has changes that have not been saved.'),
      findsOneWidget,
    );
    expect(find.text('Keep editing'), findsOneWidget);
    expect(find.text('Discard'), findsOneWidget);
    expect(find.text('Save and close'), findsOneWidget);
  });

  testWidgets('shows the Russian strings under Locale(ru)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_harness(const Locale('ru'), (_) {}));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Несохранённые изменения'), findsOneWidget);
    expect(
      find.text('В этой модели есть изменения, которые не были сохранены.'),
      findsOneWidget,
    );
    expect(find.text('Продолжить редактирование'), findsOneWidget);
    expect(find.text('Не сохранять'), findsOneWidget);
    expect(find.text('Сохранить и закрыть'), findsOneWidget);
  });

  testWidgets('choosing discard answers UnsavedChoice.discard', (
    WidgetTester tester,
  ) async {
    UnsavedChoice? answer;
    await tester.pumpWidget(
      _harness(const Locale('en'), (UnsavedChoice? it) => answer = it),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(answer, UnsavedChoice.discard);
  });
}
