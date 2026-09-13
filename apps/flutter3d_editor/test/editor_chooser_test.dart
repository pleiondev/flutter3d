import 'package:flutter/material.dart';
import 'package:flutter3d_editor/src/editor_chooser.dart';
import 'package:flutter3d_editor/src/editor_state.dart';
import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter_test/flutter_test.dart';

const _template = Template(
  id: 'platformer',
  name: 'Platformer',
  about: 'A runner who jumps twice.',
  files: <String, String>{'app.main.dart.txt': 'lib/main.dart'},
);

void main() {
  testWidgets('tpl-03: picking a template asks for a name before creating', (
    tester,
  ) async {
    (Template, String)? created;
    await tester.pumpWidget(
      MaterialApp(
        home: EditorChooser(
          state: const EditorChoosing(<Template>[_template], said: ''),
          levelPath: '/tmp/does-not-exist/assets/levels/first.json',
          recent: const <String>[],
          onCreate: (template, name) async => created = (template, name),
          onOpen: (_) async {},
        ),
      ),
    );

    await tester.tap(find.text('Platformer'));
    await tester.pumpAndSettle();

    // The dialog opens with the template's own id as a starting name, not
    // blank — a person overwrites it rather than typing from nothing.
    expect(find.text('New Platformer project'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'platformer'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'My Very First Game!');
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();

    expect(created, isNotNull);
    expect(created!.$1, _template);
    // `onCreate` hands over exactly what was typed — `packageName` is the
    // caller's job (see `main.dart`'s `_create`), not this dialog's.
    expect(created!.$2, 'My Very First Game!');
  });

  testWidgets('cancelling the name dialog creates nothing', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: EditorChooser(
          state: const EditorChoosing(<Template>[_template], said: ''),
          levelPath: '/tmp/does-not-exist/assets/levels/first.json',
          recent: const <String>[],
          onCreate: (_, _) async => calls++,
          onOpen: (_) async {},
        ),
      ),
    );

    await tester.tap(find.text('Platformer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(calls, 0);
  });

  testWidgets('clearing the name field and submitting creates nothing', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: EditorChooser(
          state: const EditorChoosing(<Template>[_template], said: ''),
          levelPath: '/tmp/does-not-exist/assets/levels/first.json',
          recent: const <String>[],
          onCreate: (_, _) async => calls++,
          onOpen: (_) async {},
        ),
      ),
    );

    await tester.tap(find.text('Platformer'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();

    expect(calls, 0);
  });
}
