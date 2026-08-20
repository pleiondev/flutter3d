/// A document being changed, and the ways that can lose somebody's work.
///
///     flutter test test/editing_test.dart
///
/// Everything here runs without a window, which is the whole reason the editor
/// is split this way: what a level editor is *for* is a picture, and what it
/// can get catastrophically wrong is a file.
library;

import 'dart:convert';

import 'package:editor/src/editing.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A small document, written the way a generator writes one.
String _document({String? generatedBy, int brushes = 2}) => jsonEncode(
      <String, Object?>{
        'version': 1,
        'name': 'test',
        'generatedBy': ?generatedBy,
        'materials': <String, Object?>{
          'stone': <String, Object?>{'baseColor': <double>[0.5, 0.5, 0.5, 1.0]},
        },
        'brushes': <Object?>[
          for (var i = 0; i < brushes; i++)
            <String, Object?>{
              'at': <double>[i * 4.0, 0.0, 0.0],
              'size': <double>[2.0, 2.0, 2.0],
              'material': 'stone',
            },
        ],
      },
    );

Editing _open({String? generatedBy, int brushes = 2}) => Editing.parse(
      _document(generatedBy: generatedBy, brushes: brushes),
      path: '/levels/test.json',
    );

void main() {
  group('who owns the document', () {
    test('a generated one is not written back over', () {
      // **The rule the format was already carrying and nothing enforced.**
      // `generatedBy` is written by the Python that produced every level in
      // this repository, and `Level`'s own doc calls it "the question an editor
      // has to ask before it is allowed to save". Editing `crypt.json` by hand
      // and saving it produces a file that looks edited right up until somebody
      // runs `make_crypt.py`, at which point the afternoon is gone and nothing
      // ever said so.
      final editing = _open(generatedBy: 'tool/make_crypt.py');

      expect(editing.generatedBy, 'tool/make_crypt.py');
      expect(editing.mayOverwrite, isFalse);
    });

    test('and one nobody generated is', () {
      expect(_open().mayOverwrite, isTrue);
      expect(_open().generatedBy, isNull);
    });

    test('and a copy of a generated one takes ownership of itself', () {
      // The other half of the rule. A file saved beside `crypt.json` still
      // saying it was written by `make_crypt.py` invites somebody to run that
      // again — which is the very thing that throws the work away.
      final editing = _open(generatedBy: 'tool/make_crypt.py');

      final copy = jsonDecode(editing.write(claiming: 'apps/editor'))
          as Map<String, Object?>;

      expect(copy['generatedBy'], 'apps/editor');
    });
  });

  group('what a write keeps', () {
    test('everything the document said that this editor has never heard of', () {
      // Write-through is `Level`'s, not this editor's — but an editor is the
      // one program that will lose a key if it ever stops working, so the
      // guarantee is asserted where the risk is.
      final text = jsonEncode(<String, Object?>{
        'version': 1,
        'name': 'test',
        'somethingNewer': <String, Object?>{'weather': 'rain'},
        'brushes': <Object?>[],
      });

      final back = jsonDecode(Editing.parse(text, path: 'x').write())
          as Map<String, Object?>;

      expect(back['somethingNewer'], <String, Object?>{'weather': 'rain'});
    });

    test('and it is indented, because people read these files', () {
      // The generators write them indented and `git diff` compares them line by
      // line. An editor that collapsed one onto a single line would turn a
      // two-line change into a whole-file one.
      expect(_open().write(), contains('\n  '));
      expect(_open().write(), endsWith('\n'));
    });
  });

  group('moving a brush', () {
    test('moves it', () {
      final editing = _open()..select(1);

      editing.nudge(Vector3(0.0, 1.0, 0.0));

      expect(editing.brush!.centre.y, 1.0);
    });

    test('and nothing happens with nothing selected', () {
      final editing = _open();
      final where = editing.level.brushes[0].centre.clone();

      editing.nudge(Vector3(0.0, 1.0, 0.0));

      expect(editing.level.brushes[0].centre, where);
      expect(editing.isDirty, isFalse,
          reason: 'it recorded an edit that never happened');
    });

    test('and it lands on the grid', () {
      // **An editor without a grid writes documents full of 3.0000001.** Every
      // level here came out of a generator writing rounded numbers, and a brush
      // sitting a millionth of a metre off is a diff nobody can read and a seam
      // a player can see light through.
      final editing = _open()..select(0);
      editing.brush!.centre.setValues(0.31, 0.0, 0.0);

      editing.nudge(Vector3(0.0, 0.0, 0.0));

      expect(editing.brush!.centre.x, 0.25);
    });

    test('and the grid can be turned off for something that needs it', () {
      final editing = _open()..select(0);
      editing.grid = 0.0;

      editing.nudge(Vector3(0.31, 0.0, 0.0));

      // Close rather than equal, and the reason is a second argument for the
      // grid: a `Vector3` holds floats, so 0.31 comes back as 0.3100000023 —
      // a document full of numbers off the grid is a document full of that.
      // Quarters survive exactly, because a quarter is exact in binary.
      expect(editing.brush!.centre.x, closeTo(0.31, 1e-6));
    });
  });

  group('resizing one', () {
    test('grows and shrinks it about its own centre', () {
      final editing = _open()..select(0);
      final where = editing.brush!.centre.clone();

      editing.grow(Vector3(2.0, 0.0, 0.0));

      expect(editing.brush!.size.x, 4.0);
      expect(editing.brush!.centre, where);
    });

    test('and never past nothing', () {
      // A brush of zero is invisible, unclickable and impossible to get back.
      final editing = _open()..select(0);

      editing.grow(Vector3(-100.0, -100.0, -100.0));

      expect(editing.brush!.size.x, Editing.minimumSize);
      expect(editing.brush!.size.y, Editing.minimumSize);
    });
  });

  group('adding one', () {
    test('gives it the material the level is mostly made of', () {
      // A brush naming a material the level does not have draws as grey and
      // reads as a bug, and the validator says so. An editor whose first act is
      // a warning is an editor nobody trusts.
      final editing = _open();

      editing.add(Vector3(10.0, 0.0, 0.0));

      expect(editing.brush!.material, 'stone');
      expect(editing.level.materials.containsKey(editing.brush!.material),
          isTrue);
    });

    test('and selects it, because the next thing anybody does is move it', () {
      final editing = _open();

      editing.add(Vector3(10.0, 0.0, 0.0));

      expect(editing.selected, editing.level.brushes.length - 1);
    });

    test('and a duplicate lands beside the original, not inside it', () {
      // Two brushes in the same place are one brush as far as anybody can see,
      // and an editor whose duplicate is invisible appears not to have worked.
      final editing = _open()..select(0);
      final from = editing.level.brushes[0];

      editing.duplicate();

      expect(editing.level.brushes.length, 3);
      expect(editing.brush!.centre.x, from.centre.x + from.size.x);
      expect(editing.brush!.material, from.material);
    });
  });

  group('undo', () {
    test('puts a move back', () {
      final editing = _open()..select(0);
      final where = editing.brush!.centre.clone();

      editing.nudge(Vector3(4.0, 0.0, 0.0));
      editing.undo();

      expect(editing.brush!.centre, where);
    });

    test('and brings back a deleted brush', () {
      // The one an editor is judged on. Delete is the only key that can lose
      // work in a keystroke.
      final editing = _open()..select(1);

      editing.remove();
      expect(editing.level.brushes.length, 1);

      editing.undo();

      expect(editing.level.brushes.length, 2);
      expect(editing.level.brushes[1].centre.x, 4.0);
    });

    test('and goes back more than one step', () {
      final editing = _open()..select(0);

      editing.nudge(Vector3(1.0, 0.0, 0.0));
      editing.nudge(Vector3(1.0, 0.0, 0.0));
      editing.undo();
      editing.undo();

      expect(editing.brush!.centre.x, 0.0);
      expect(editing.canUndo, isFalse);
    });

    test('and does nothing at the start rather than throwing', () {
      final editing = _open();
      expect(editing.undo, returnsNormally);
      expect(editing.level.brushes.length, 2);
    });

    test('and drops a selection that undo has removed', () {
      // The reason the selection is an index and not a brush: a reference into
      // a list that has just been replaced is a reference to something that is
      // no longer in the document.
      final editing = _open()
        ..add(Vector3(20.0, 0.0, 0.0));
      expect(editing.selected, 2);

      editing.undo();

      expect(editing.selected, isNull);
      expect(editing.brush, isNull);
    });
  });

  test('and the document knows it has been changed', () {
    final editing = _open()..select(0);
    expect(editing.isDirty, isFalse);

    editing.nudge(Vector3(1.0, 0.0, 0.0));
    expect(editing.isDirty, isTrue);

    editing.saved();
    expect(editing.isDirty, isFalse);
  });

  test('and a level it changed still loads', () {
    // The round trip that matters: whatever the editor wrote has to be
    // something the game can open. A writer that produced a document its own
    // reader rejects would be found out by a player rather than by this.
    final editing = _open()..select(0);
    editing
      ..nudge(Vector3(1.0, 0.0, 0.0))
      ..add(Vector3(8.0, 2.0, 0.0));

    final reopened = Level.fromJson(
      jsonDecode(editing.write()) as Map<String, Object?>,
    );

    expect(reopened.brushes.length, 3);
    expect(reopened.brushes[0].centre.x, 1.0);
    expect(reopened.materials.keys, contains('stone'));
  });
}
