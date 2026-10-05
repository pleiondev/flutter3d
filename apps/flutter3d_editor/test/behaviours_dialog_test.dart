/// The level's behaviour trees in the editor: written as documents, refused
/// with where they are wrong, and each write one step of undo.
library;

import 'dart:convert';

import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d_editor/src/behaviours_dialog.dart';
import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter_test/flutter_test.dart';

Editing _level() => Editing.parse(
  jsonEncode(<String, Object?>{
    'version': 1,
    'materials': <String, Object?>{
      'stone': <String, Object?>{
        'baseColor': <double>[0.5, 0.5, 0.5, 1.0],
      },
    },
    'brushes': <Object?>[
      <String, Object?>{
        'at': <double>[0.0, -0.5, 0.0],
        'size': <double>[10.0, 1.0, 10.0],
        'material': 'stone',
      },
    ],
  }),
  path: '/levels/room.json',
);

/// Opens the dialog over [editing], and calls [closed] with what it said
/// when it is closed.
Future<void> _open(
  WidgetTester tester,
  Editing editing, {
  void Function(bool changed)? closed,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (BuildContext context) => TextButton(
          onPressed: () async {
            // Two statements: `closed?.call(await …)` skips its argument,
            // dialog and all, when there is nobody to tell.
            final changed = await showBehaviours(context, editing);
            closed?.call(changed);
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _write(WidgetTester tester, String document) async {
  await tester.enterText(
    find.byKey(const ValueKey<String>('behaviour:document')),
    document,
  );
  await tester.tap(find.byKey(const ValueKey<String>('behaviour:save')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a new tree is written, and is one step of undo', (
    WidgetTester tester,
  ) async {
    final editing = _level();
    await _open(tester, editing);
    await tester.enterText(
      find.byKey(const ValueKey<String>('behaviour:new-name')),
      'guard',
    );
    await tester.tap(find.byKey(const ValueKey<String>('behaviour:new')));
    await tester.pumpAndSettle();
    await _write(
      tester,
      '{"kind": "sequence", "children": ['
      '{"kind": "goTo", "key": "post"}, {"kind": "wait", "seconds": 1}]}',
    );
    expect(editing.level.behaviours['guard']?['kind'], 'sequence');
    expect(find.byKey(const ValueKey<String>('behaviour:guard')), findsOne);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    editing.undo();
    expect(editing.level.behaviours, isEmpty);
  });

  testWidgets('a tree that does not read says where, and is not written', (
    WidgetTester tester,
  ) async {
    final editing = _level();
    await _open(tester, editing);
    await tester.enterText(
      find.byKey(const ValueKey<String>('behaviour:new-name')),
      'guard',
    );
    await tester.tap(find.byKey(const ValueKey<String>('behaviour:new')));
    await tester.pumpAndSettle();
    await _write(
      tester,
      '{"kind": "sequence", "children": [{"kind": "teleport"}]}',
    );
    expect(find.textContaining('children[0]'), findsOne);
    expect(editing.level.behaviours, isEmpty);
    expect(editing.canUndo, isFalse);

    await _write(tester, '{"kind": ');
    expect(find.textContaining('not JSON'), findsOne);
  });

  testWidgets('a tree is removed, and the dialog says something changed', (
    WidgetTester tester,
  ) async {
    final editing = _level()
      ..setBehaviour('guard', <String, Object?>{'kind': 'wait', 'seconds': 1});
    bool? changed;
    await _open(tester, editing, closed: (bool it) => changed = it);
    await tester.tap(find.byKey(const ValueKey<String>('behaviour:guard')));
    await tester.pumpAndSettle();
    expect(find.textContaining('"seconds": 1'), findsOne);
    await tester.tap(find.byKey(const ValueKey<String>('behaviour:remove')));
    await tester.pumpAndSettle();
    expect(editing.level.behaviours, isEmpty);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(changed, isTrue);
  });
}
