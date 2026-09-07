/// Edits as objects, and the stack that remembers them.
///
///     dart test test/editor_command_test.dart
///
/// **Two things nothing could do before.** A change to a document could be
/// performed and not named, so nothing could list what an editor is able to do
/// — and every change was one step whatever it was, so dragging a brush across
/// a room filled all sixty-four of them before the mouse button came up. A
/// command answers the first; a transaction answers the second.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A small document with one of each of the three kinds in it, because the
/// commands divide along exactly that line: a brush can be resized, a light can
/// be brightened, an entity can be turned, and none of the three can do the
/// other two.
String _document() => jsonEncode(<String, Object?>{
  'version': 1,
  'name': 'test',
  'materials': <String, Object?>{
    'stone': <String, Object?>{
      'baseColor': <double>[0.5, 0.5, 0.5, 1.0],
    },
  },
  'brushes': <Object?>[
    <String, Object?>{
      'at': <double>[0.0, 0.0, 0.0],
      'size': <double>[2.0, 2.0, 2.0],
      'material': 'stone',
    },
    <String, Object?>{
      'at': <double>[4.0, 0.0, 0.0],
      'size': <double>[2.0, 2.0, 2.0],
      'material': 'stone',
    },
  ],
  'lights': <Object?>[
    <String, Object?>{
      'type': 'point',
      'at': <double>[0.0, 3.0, 0.0],
      'intensity': 4.0,
      'range': 9.0,
    },
  ],
  'entities': <Object?>[
    <String, Object?>{
      'type': 'monster',
      'at': <double>[2.0, 0.0, 2.0],
      'yaw': 0.0,
    },
  ],
});

Editing _open() => Editing.parse(_document(), path: '/levels/test.json');

/// One of every command, in the order [editorCommandNames] lists them.
///
/// Built rather than const, because half of them carry a `Vector3` and a
/// `Vector3` is not a constant.
List<EditorCommand> _everyCommand() => <EditorCommand>[
  MoveBy(Vector3(0.25, 0.0, 0.0)),
  Resize(Vector3(1.0, 0.0, 0.0)),
  AddBrush(
    Vector3(2.0, 0.0, 0.0),
    size: Vector3(1.0, 2.0, 3.0),
    material: 'stone',
  ),
  AddLight(Vector3(0.0, 3.0, 0.0), intensity: 6.0, range: 12.0),
  Place(Piece.entity, 'monster', Vector3(1.0, 0.0, 1.0)),
  const Duplicate(),
  const Delete(),
  const SetField('solid', false),
  const Brighten(1.25),
  const Turn(0.5),
];

void main() {
  group('a command is a value', () {
    test('and every one survives being written down and read back', () {
      // **The point of the whole hierarchy.** A method call cannot be sent over
      // a socket; this can. Through real JSON rather than through the map, so
      // the trip a tool call actually makes — numbers narrowed to what JSON has
      // — is the trip that is tested.
      //
      // Mutation: drop `'material'` from `AddBrush.arguments`. The brush comes
      // back naming no material and the comparison fails.
      for (final command in _everyCommand()) {
        final wire = jsonDecode(jsonEncode(command.toJson()));
        final back = EditorCommand.fromJson(wire as Map<String, Object?>);

        expect(back, isNotNull, reason: '${command.name} did not come back');
        expect(back!.toJson(), command.toJson(), reason: command.name);
        expect(back.says, command.says, reason: command.name);
      }
    });

    test('and one this build has never heard of is refused, not thrown', () {
      // What is being read here is JSON somebody else wrote. "I do not know
      // that command" is an answer a server hands its caller, not a crash.
      expect(
        EditorCommand.fromJson(<String, Object?>{'command': 'teleport'}),
        isNull,
      );
      expect(EditorCommand.fromJson(<String, Object?>{}), isNull);
      expect(
        EditorCommand.fromJson(<String, Object?>{
          'command': 'moveBy',
          'by': 'over there',
        }),
        isNull,
        reason: 'an unreadable argument moved nothing and said it had',
      );
    });

    test('and the list a tool server reads is the list that exists', () {
      // The list belongs to the core precisely so that a server cannot hold a
      // stale copy of it. This is what holds the two together: an eleventh
      // command that nobody adds to `editorCommandNames` fails here rather
      // than being quietly uncallable.
      expect(
        _everyCommand().map((EditorCommand it) => it.name).toList(),
        editorCommandNames,
      );
    });
  });

  group('what a command says', () {
    test('reads as a sentence, with the numbers in it', () {
      // The same job `Editing.says` does for the selection: something a bar can
      // print and a step can be labelled with. "move" and "move by 0.25, 0, 0"
      // answer different questions when somebody is hunting for the change they
      // want to get back past.
      expect(MoveBy(Vector3(0.25, 0.0, 0.0)).says, 'move by 0.25, 0, 0');
      expect(const Delete().says, 'delete the selection');
      expect(const SetField('solid', false).says, 'set solid to false');
      expect(const SetField('surface', null).says, 'clear surface');
      // Radians on the wire, because that is what the document holds; degrees
      // in the sentence, because that is what a person is thinking in.
      expect(Turn(math.pi / 8).says, 'turn by 22.5°');
    });
  });

  group('running one', () {
    test('changes the document and leaves one step behind', () {
      final editing = _open()..select(Piece.brush, 0);

      expect(editing.history.run(MoveBy(Vector3(0.0, 1.0, 0.0))), isTrue);

      expect(editing.brush!.centre.y, 1.0);
      expect(editing.history.undoSays, 'move by 0, 1, 0');

      editing.history.undo();

      expect(editing.brush!.centre.y, 0.0);
      expect(editing.history.canUndo, isFalse);
      expect(editing.history.redoSays, 'move by 0, 1, 0');
    });

    test('and one with nothing to work on answers false and does nothing', () {
      // False rather than a throw, the way `setField` already answers a value
      // the format cannot read: a command arrives from a keystroke or a socket,
      // and "nothing is selected" is a question with an answer.
      //
      // Mutation: drop the `editing.piece == null` guard from `Delete.apply`.
      // It answers true for a document it did not touch, and a caller that
      // believes it puts a step in the stack that undoes nothing.
      final editing = _open();
      final before = editing.write();

      expect(editing.history.run(MoveBy(Vector3(0.0, 1.0, 0.0))), isFalse);
      expect(editing.history.run(Resize(Vector3(1.0, 0.0, 0.0))), isFalse);
      expect(editing.history.run(const Duplicate()), isFalse);
      expect(editing.history.run(const Delete()), isFalse);
      expect(editing.history.run(const Brighten(2.0)), isFalse);
      expect(editing.history.run(const Turn(0.5)), isFalse);
      expect(editing.history.run(const SetField('solid', false)), isFalse);

      expect(editing.write(), before);
      expect(editing.history.canUndo, isFalse);
      expect(editing.isDirty, isFalse, reason: 'it recorded seven non-events');
    });

    test('and one aimed at the wrong kind answers false too', () {
      // A light has no size and an entity has no strength. The keys that mean
      // "more of this" are shared, so the command that cannot apply has to say
      // so rather than reaching into whichever list is nearest.
      final light = _open()..select(Piece.light, 0);
      expect(light.history.run(Resize(Vector3(1.0, 0.0, 0.0))), isFalse);
      expect(light.history.run(const Turn(0.5)), isFalse);

      final brush = _open()..select(Piece.brush, 0);
      expect(brush.history.run(const Brighten(2.0)), isFalse);

      final entity = _open()..select(Piece.entity, 0);
      expect(entity.history.run(const Turn(0.5)), isTrue);
      expect(entity.entity!.yaw, closeTo(0.5, 1e-6));
    });

    test('and a refused field leaves no half-edited document', () {
      // The tool whose job is producing documents that load must not produce
      // one that does not — and must not leave a step behind for an edit that
      // never happened.
      //
      // Mutation: have `SetField.apply` call `setField` and return true. The
      // document is unchanged, the assertion on `canUndo` still passes, and the
      // one on the answer fails — which is the point: the caller is the one
      // being lied to.
      final editing = _open()..select(Piece.brush, 0);

      expect(
        editing.history.run(const SetField('at', 'not a vector')),
        isFalse,
      );

      expect(editing.brush!.centre.x, 0.0);
      expect(editing.fields['at'], isA<List<Object?>>());
      expect(editing.history.canUndo, isFalse);
    });
  });

  group('a transaction', () {
    test('is one step however many changes are inside it', () {
      // **Without this a drag eats the stack.** Dragging a brush across a room
      // is one thing a person did and a hundred changes to the document, and
      // recorded singly they fill all sixty-four steps in about a second — so
      // the change before the drag, the one anybody would actually want back,
      // is gone before the mouse button comes up.
      //
      // Mutation: have `EditorHistory.remember` push a step even while a
      // transaction is open. Thirty steps go in, one undo moves the brush a
      // quarter of a metre, and the assertions on both the position and
      // `canUndo` fail.
      final editing = _open()..select(Piece.brush, 0);

      editing.history.transaction('drag the brush', () {
        for (var i = 0; i < 30; i++) {
          editing.nudge(Vector3(0.25, 0.0, 0.0));
        }
      });

      expect(editing.brush!.centre.x, closeTo(7.5, 1e-6));
      expect(editing.history.undoSays, 'drag the brush');

      editing.history.undo();

      expect(editing.brush!.centre.x, 0.0);
      expect(editing.history.canUndo, isFalse);
    });

    test('and one that changed nothing leaves no step at all', () {
      // At most one step, not exactly one. A drag that never left the grid
      // square it started in is not a change, and an undo that has to be
      // pressed twice because one press does nothing visible is an undo nobody
      // trusts.
      //
      // Mutation: push the snapshot unconditionally in `transaction`. The
      // document is still right and the stack is full of nothing.
      final editing = _open();

      editing.history.transaction('a drag that went nowhere', () {
        editing.nudge(Vector3(1.0, 0.0, 0.0));
      });

      expect(editing.history.canUndo, isFalse);
      expect(editing.isDirty, isFalse);
    });

    test('and a nested one belongs to the outermost', () {
      // The snapshot the outer one took is the state a person means when they
      // say "before all that".
      final editing = _open();

      editing.history.transaction('build a wall', () {
        editing.history.run(AddBrush(Vector3(8.0, 0.0, 0.0)));
        editing.history.run(AddBrush(Vector3(10.0, 0.0, 0.0)));
      });

      expect(editing.level.brushes.length, 4);
      expect(editing.history.undoSays, 'build a wall');

      editing.history.undo();

      expect(editing.level.brushes.length, 2);
      expect(editing.history.canUndo, isFalse);
    });
  });

  group('how far back it goes', () {
    test('sixty-four steps, and the oldest falls off the end', () {
      // The depth the stack has always had, kept where the stack now lives. The
      // oldest goes rather than the newest being refused: an editor that stops
      // recording after the sixty-fourth change is an editor whose undo quietly
      // stops working halfway through an afternoon.
      //
      // Mutation: drop the trim in `_push`. Undoing sixty-four times still
      // leaves six steps, `canUndo` is true and the brush is back at the start.
      final editing = _open()..select(Piece.brush, 0);
      const beyond = 6;

      for (var i = 0; i < EditorHistory.undoDepth + beyond; i++) {
        editing.history.run(MoveBy(Vector3(0.25, 0.0, 0.0)));
      }
      expect(
        editing.brush!.centre.x,
        closeTo((EditorHistory.undoDepth + beyond) * 0.25, 1e-6),
      );

      for (var i = 0; i < EditorHistory.undoDepth; i++) {
        editing.history.undo();
      }

      expect(editing.history.canUndo, isFalse);
      expect(
        editing.brush!.centre.x,
        closeTo(beyond * 0.25, 1e-6),
        reason: 'the six oldest steps were kept, or more than six were lost',
      );
    });
  });

  group('undo', () {
    test('keeps a selection that still points at something', () {
      // What makes undoing a nudge feel like undoing a nudge rather than like
      // losing the brush.
      //
      // Mutation: clear the selection unconditionally in `_restore`. Every undo
      // costs somebody the thing they were working on.
      final editing = _open()..select(Piece.brush, 1);

      editing.history.run(MoveBy(Vector3(0.0, 1.0, 0.0)));
      editing.history.undo();

      expect(editing.kind, Piece.brush);
      expect(editing.selected, 1);
      expect(editing.brush!.centre.y, 0.0);
    });

    test('and drops one it has taken away', () {
      // The reason the selection is an index and not a brush: a reference into
      // a list that has just been replaced is a reference to something that is
      // no longer in the document.
      final editing = _open();

      editing.history.run(AddBrush(Vector3(20.0, 0.0, 0.0)));
      expect(editing.selected, 2);

      editing.history.undo();

      expect(editing.selected, isNull);
      expect(editing.piece, isNull);
    });
  });
}
