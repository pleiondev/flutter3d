/// The level's behaviour trees and cutscenes in the editor: written as
/// documents, refused with where they are wrong, and each write one step of
/// undo.
library;

import 'dart:convert';

import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d_editor/src/documents_dialog.dart';
import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show Sequence;
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
  Future<bool> Function(BuildContext context, Editing editing) show =
      showBehaviours,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (BuildContext context) => TextButton(
          onPressed: () async {
            // Two statements: `closed?.call(await …)` skips its argument,
            // dialog and all, when there is nobody to tell.
            final changed = await show(context, editing);
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

  testWidgets('a cutscene is written as a cutscene entity, and refused '
      'with where when it does not read', (WidgetTester tester) async {
    final editing = _level();
    var changed = false;
    await _open(
      tester,
      editing,
      show: showCutscenes,
      closed: (bool it) => changed = it,
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('cutscene:new-name')),
      'intro',
    );
    await tester.tap(find.byKey(const ValueKey<String>('cutscene:new')));
    await tester.pumpAndSettle();
    Future<void> write(String document) async {
      await tester.enterText(
        find.byKey(const ValueKey<String>('cutscene:document')),
        document,
      );
      await tester.tap(find.byKey(const ValueKey<String>('cutscene:save')));
      await tester.pumpAndSettle();
    }

    // Mutation: the dialog writing what it was given without reading it.
    await write('{"seconds": 2, "fade": [{"t": 9, "value": 1}]}');
    expect(find.textContaining('fade[0]'), findsOneWidget);
    expect(editing.cutscenes, isEmpty);
    await write(
      '{"seconds": 2, "subtitles": [{"from": 0, "to": 2, "text": "Hush."}]}',
    );
    expect(editing.cutscenes.keys, <String>['intro']);
    expect(editing.level.ofType('cutscene').single.name, 'intro');
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(changed, isTrue);
    editing.undo();
    expect(editing.cutscenes, isEmpty);
  });

  testWidgets('Preview hands the scene over unsaved, and refuses one '
      'with no camera', (WidgetTester tester) async {
    final editing = _level();
    Sequence? shown;
    await _open(
      tester,
      editing,
      show: (BuildContext context, Editing editing) => showCutscenes(
        context,
        editing,
        preview: (Sequence scene) => shown = scene,
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('cutscene:new-name')),
      'intro',
    );
    await tester.tap(find.byKey(const ValueKey<String>('cutscene:new')));
    await tester.pumpAndSettle();
    Future<void> preview(String document) async {
      await tester.enterText(
        find.byKey(const ValueKey<String>('cutscene:document')),
        document,
      );
      await tester.tap(find.byKey(const ValueKey<String>('cutscene:preview')));
      await tester.pumpAndSettle();
    }

    await preview('{"seconds": 2}');
    expect(find.textContaining('nothing to show'), findsOneWidget);
    expect(shown, isNull);
    await preview(
      '{"seconds": 2, "camera": {"keys": [{"t": 0, "at": [0, 2, 0], '
      '"look": [0, 2, -5]}]}}',
    );
    expect(shown?.steps, 120);
    // Shown, not written; and the dialog is out of the viewport's way.
    expect(editing.cutscenes, isEmpty);
    expect(find.text('Cutscenes'), findsNothing);
  });
}
