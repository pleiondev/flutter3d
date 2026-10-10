/// More than one thing selected, and what the commands do to all of them.
///
///     dart test test/selection_test.dart
///
/// The selection was one index on `Editing`, which an outliner that can
/// command-click rows outgrew. The primary is still `kind` and `selected` —
/// the inspector, the marker and every command that reads one thing read it
/// — and what is beside it is a list that moving and deleting reach too.
library;

import 'dart:convert';

import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

Editing _open() => Editing.parse(
  jsonEncode(<String, Object?>{
    'version': 1,
    'name': 'test',
    'materials': <String, Object?>{
      'stone': <String, Object?>{
        'baseColor': <double>[0.5, 0.5, 0.5, 1.0],
      },
    },
    'brushes': <Object?>[
      for (var i = 0; i < 4; i++)
        <String, Object?>{
          'at': <double>[i * 4.0, 0.0, 0.0],
          'size': <double>[2.0, 2.0, 2.0],
          'material': 'stone',
        },
    ],
    'lights': <Object?>[
      <String, Object?>{
        'type': 'point',
        'at': <double>[0.0, 3.0, 0.0],
        'intensity': 2.0,
        'range': 6.0,
      },
    ],
  }),
  path: '/levels/test.json',
);

void main() {
  test('a toggle adds beside the primary and keeps it primary', () {
    // Mutation: make `toggle` call `select` for a thing not yet selected.
    // The selection is then the one row clicked last, and the first is lost.
    final editing = _open()
      ..select(Piece.brush, 0)
      ..toggle(Piece.light, 0);

    expect(editing.selection, <Picked>[
      (kind: Piece.brush, index: 0),
      (kind: Piece.light, index: 0),
    ]);
    expect(editing.kind, Piece.brush);
    expect(editing.selected, 0);
  });

  test('and a second toggle takes it out again', () {
    final editing = _open()
      ..select(Piece.brush, 0)
      ..toggle(Piece.brush, 2)
      ..toggle(Piece.brush, 2);

    expect(editing.selection, <Picked>[(kind: Piece.brush, index: 0)]);
  });

  test('taking out the primary promotes the next one', () {
    // What the inspector shows is the primary; one deselected must not leave
    // the inspector on something no longer selected.
    //
    // Mutation: clear the selection instead of promoting the rest. The
    // second brush stops being selected along with the first.
    final editing = _open()
      ..select(Piece.brush, 0)
      ..toggle(Piece.brush, 1)
      ..toggle(Piece.brush, 0);

    expect(editing.selection, <Picked>[(kind: Piece.brush, index: 1)]);
    expect(editing.brush, same(editing.level.brushes[1]));
  });

  test('selecting one thing outright forgets the others', () {
    // A click in the viewport means "this one", and so does a new brush.
    //
    // Mutation: stop the `kind` and `selected` setters clearing the others
    // (either one alone is still caught by the other). The old third brush
    // stays selected beside the new one.
    final editing = _open()
      ..select(Piece.brush, 0)
      ..toggle(Piece.brush, 2)
      ..select(Piece.brush, 1);
    expect(editing.selection, <Picked>[(kind: Piece.brush, index: 1)]);

    editing
      ..toggle(Piece.brush, 2)
      ..add(Vector3(10.0, 0.0, 0.0));
    expect(editing.selection, <Picked>[(kind: Piece.brush, index: 4)]);
  });

  test('a move moves everything selected, as one step of undo', () {
    // Mutation: have `MoveSelectionBy` call `nudge` again. The light stays where it
    // was and only the brush moves.
    final editing = _open()
      ..select(Piece.brush, 1)
      ..toggle(Piece.light, 0);

    editing.history.run(MoveSelectionBy(Vector3(0.0, 1.0, 0.0)));

    expect(editing.level.brushes[1].center, Vector3(4.0, 1.0, 0.0));
    expect(editing.level.lights[0].position, Vector3(0.0, 4.0, 0.0));
    expect(editing.level.brushes[0].center, Vector3(0.0, 0.0, 0.0));

    editing.history.undo();
    expect(editing.level.brushes[1].center, Vector3(4.0, 0.0, 0.0));
    expect(editing.level.lights[0].position, Vector3(0.0, 3.0, 0.0));
  });

  test('a delete takes all of them, and the right ones', () {
    // Highest index first: removing brush 1 before brush 3 would make the
    // old brush 3 number 2, and the delete would take brush 2 instead.
    //
    // Mutation: drop the sort in `removeAll`. Brush 2 is deleted rather
    // than brush 3, so the survivors are at 0 and 12.
    final editing = _open()
      ..select(Piece.brush, 1)
      ..toggle(Piece.brush, 3);

    expect(editing.history.run(const Delete()), isTrue);

    expect(
      <double>[for (final b in editing.level.brushes) b.center.x],
      <double>[0.0, 8.0],
    );
    expect(editing.selection, isEmpty);
  });

  test('an undo that shortens a list drops what pointed past its end', () {
    final editing = _open()..add(Vector3(20.0, 0.0, 0.0));
    editing
      ..select(Piece.brush, 0)
      ..toggle(Piece.brush, 4);

    editing.history.undo();

    expect(editing.selection, <Picked>[(kind: Piece.brush, index: 0)]);
  });

  test('the selection follows its row by id when a row before it goes', () {
    // Mutation: hold the selection as an index again. Taking out brush 0
    // then moves the selection onto the brush that was number 3.
    final editing = _open()..select(Piece.brush, 2);
    final id = editing.selectedId;
    expect(id, isNotNull);

    editing.level.brushes.removeAt(0);

    expect(editing.selected, 1);
    expect(editing.selectedId, id);
    expect(editing.brush!.center.x, 8.0);
  });

  test('a copy gets an id of its own', () {
    final editing = _open()
      ..select(Piece.light, 0)
      ..duplicate();
    expect(editing.level.lights, hasLength(2));
    expect(editing.level.lights[0].id, isNot(editing.level.lights[1].id));
    expect(editing.selected, 1);
  });
}
