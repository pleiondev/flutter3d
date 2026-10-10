import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter3d_editor/src/disk/memory_disk.dart';
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

  testWidgets('P11: in a browser it says where the work goes, and the row '
      'opens what was picked into the page', (tester) async {
    // Broken by the browser build keeping the desktop sentence — "nothing at
    // /browser/… yet", a path on no disk anybody has — or by the row asking
    // the system panel for a path a page cannot read.
    final disk = MemoryDisk(
      deliver: (_, _) {},
      pick: (_) async => (name: 'crypt.json', bytes: Uint8List(0)),
    );
    String? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: EditorChooser(
          state: const EditorChoosing(<Template>[_template], said: ''),
          levelPath: '../flutter3d_demo_dungeon/assets/levels/crypt.json',
          recent: const <String>[],
          onCreate: (_, _) async {},
          onOpen: (String path) async => opened = path,
          disk: disk,
        ),
      ),
    );

    expect(find.textContaining('running in a browser'), findsOneWidget);
    expect(find.textContaining('There is nothing at'), findsNothing);

    await tester.tap(find.text('Choose a file…'));
    await tester.pumpAndSettle();

    expect(opened, '${MemoryDisk.opened}/crypt.json');
    expect(disk.exists(opened!), isTrue);
  });
}
