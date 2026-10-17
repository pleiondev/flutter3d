/// An inspector edit is one step of undo, and undo takes it back.
///
///     dart test test/set_field_undo_test.dart
///
/// It did not. `Level.toJson` hands back the same row maps it read, call
/// after call, wherever nothing in them changed; the history's snapshot held
/// those maps, `setField` wrote into one of them, and the snapshot changed
/// with it. Undo then "restored" a document that already had the edit.
library;

import 'dart:convert';

import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:test/test.dart';

Editing _open() => Editing.parse(
  jsonEncode(<String, Object?>{
    'version': 1,
    'name': 'test',
    'brushes': <Object?>[
      <String, Object?>{
        'at': <double>[0.0, 0.0, 0.0],
        'size': <double>[2.0, 2.0, 2.0],
        'material': 'stone',
      },
    ],
    'entities': <Object?>[
      <String, Object?>{'type': 'monster', 'health': 30},
    ],
  }),
  path: '/levels/test.json',
);

void main() {
  test("a brush's field set and undone is the field it was", () {
    // Mutation: hand `setField` the document from `level.toJson()` as it
    // is, without `_detached`. The undo leaves the material at `brick`.
    final editing = _open()..select(Piece.brush, 0);

    expect(editing.history.run(const SetField('material', 'brick')), isTrue);
    editing.history.undo();

    expect(editing.brush!.material, 'stone');
    editing.history.redo();
    expect(editing.brush!.material, 'brick');
  });

  test("an entity's new property set and undone is gone again", () {
    final editing = _open()..select(Piece.entity, 0);

    editing.history.run(const SetField('speed', 2.5));
    editing.history.undo();

    expect(editing.entity!.properties.containsKey('speed'), isFalse);
    expect(editing.entity!.properties['health'], 30);
  });

  test('and a refused value leaves the document as it was', () {
    // Against the document as opened, not a literal: opening gives each
    // brush its `id`, and that is not what this test is about. Mutation:
    // `_remember` before the `try` in `setField`, and the refusal leaves an
    // undo step that undoes nothing.
    final editing = _open()..select(Piece.brush, 0);
    final before = jsonEncode(editing.level.toJson()['brushes']);

    expect(editing.setField('size', 'wide'), isFalse);

    expect(jsonEncode(editing.level.toJson()['brushes']), before);
    expect(before, contains('"size":[2.0,2.0,2.0]'));
    expect(editing.history.canUndo, isFalse);
  });
}
