/// The arrays that remember what an edit replaced.
///
/// Every check here was watched to fail, and the mutation is named beside it.
/// The ones worth reading twice are the two that are easy to get subtly wrong:
/// a step that writes one slot twice, and a redo stack that survives a new
/// edit — both pass a naive test and both corrupt a document in use.
library;

import 'dart:typed_data';

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:test/test.dart';

void main() {
  group('a step of floats', () {
    test('undo puts back what was there, redo puts back the edit', () {
      final floats = JournalledFloats(4)
        ..values.setAll(0, <double>[1, 2, 3, 4]);

      floats
        ..beginStep()
        ..write(1, 20)
        ..write(3, 40);
      expect(floats.endStep(), isTrue);
      expect(floats.values, <double>[1, 20, 3, 40]);

      expect(floats.undo(), isTrue);
      expect(floats.values, <double>[1, 2, 3, 4]);

      expect(floats.redo(), isTrue);
      expect(floats.values, <double>[1, 20, 3, 40]);
    });

    test('a slot written twice in one step comes back to what it began as', () {
      final floats = JournalledFloats(2)..values.setAll(0, <double>[1, 2]);

      floats
        ..beginStep()
        ..write(0, 10)
        ..write(0, 100)
        ..endStep();
      expect(floats.values[0], 100);

      // Mutation: walk the step forwards in `_apply` instead of backwards and
      // this comes back 10 — the second write's "before" is applied last and
      // wins. A drag that reports a position per pointer move writes the same
      // slot dozens of times a step, so this is the ordinary case rather than
      // an edge one.
      floats.undo();
      expect(floats.values[0], 1);

      floats.redo();
      expect(floats.values[0], 100);
    });

    test('a new step drops what was undone', () {
      final floats = JournalledFloats(2);

      floats
        ..beginStep()
        ..write(0, 5)
        ..endStep()
        ..undo();
      expect(floats.redoDepth, 1);

      floats
        ..beginStep()
        ..write(1, 7)
        ..endStep();

      // Mutation: leave `_redo.clear()` out of `endStep` and this is 1 — and
      // pressing redo then applies an edit from a future nobody is in any more,
      // writing 5 over a document that never had it.
      expect(floats.redoDepth, 0);
      expect(floats.values, <double>[0, 7]);
    });

    test('a step that wrote nothing is not a step', () {
      final floats = JournalledFloats(2)..beginStep();

      expect(floats.endStep(), isFalse);
      expect(floats.undoDepth, 0);
    });

    test('undo with nothing to undo says so rather than throwing', () {
      final floats = JournalledFloats(2);

      expect(floats.undo(), isFalse);
      expect(floats.redo(), isFalse);
    });
  });

  group('what it refuses', () {
    test('writing with no step open', () {
      final floats = JournalledFloats(2);

      expect(() => floats.write(0, 1), throwsStateError);
    });

    test('opening a step inside a step', () {
      final floats = JournalledFloats(2)..beginStep();

      expect(floats.beginStep, throwsStateError);
    });

    test('undoing while a step is open', () {
      final floats = JournalledFloats(2)
        ..beginStep()
        ..write(0, 1);

      expect(floats.undo, throwsStateError);
    });
  });

  group('the limits a history is held to', () {
    test('trim drops the oldest steps and reports how many', () {
      final floats = JournalledFloats(100);
      for (var i = 0; i < 10; i++) {
        floats
          ..beginStep()
          ..write(i, i.toDouble())
          ..endStep();
      }

      expect(floats.trim(maxSteps: 4), 6);
      expect(floats.undoDepth, 4);

      // The four that are left are the four most recent, so undoing them takes
      // the last four edits back. Mutation: drop from the end in `trim` and the
      // first undo restores a slot the document has since edited.
      for (var i = 9; i >= 6; i--) {
        expect(floats.values[i], i.toDouble());
        floats.undo();
        expect(floats.values[i], 0);
      }
    });

    test('trim by bytes leaves the journal under the bound', () {
      final floats = JournalledFloats(1000);
      for (var step = 0; step < 20; step++) {
        floats.beginStep();
        for (var i = 0; i < 50; i++) {
          floats.write(i, step.toDouble());
        }
        floats.endStep();
      }
      final full = floats.journalBytes;
      expect(full, greaterThan(0));

      floats.trim(maxBytes: full ~/ 4);
      expect(floats.journalBytes, lessThanOrEqualTo(full ~/ 4));
      expect(floats.undoDepth, greaterThan(0));
    });

    test('a step knows what it costs', () {
      final floats = JournalledFloats(10)
        ..beginStep()
        ..write(0, 1)
        ..write(1, 2)
        ..endStep();

      // Two slots: two int32 indices and two float32 values, eight bytes each
      // pair. What a history limit counts.
      expect(floats.journalBytes, 16);
    });
  });

  group('growth', () {
    test('keeps what was there and is not itself a step', () {
      final floats = JournalledFloats(2)..values.setAll(0, <double>[1, 2]);

      floats.grow(5);

      expect(floats.length, greaterThanOrEqualTo(5));
      expect(floats.values[0], 1);
      expect(floats.values[1], 2);
      expect(floats.undoDepth, 0);
    });

    test('writes after growth journal against the new array', () {
      final floats = JournalledFloats(2)..grow(8);

      floats
        ..beginStep()
        ..write(6, 42)
        ..endStep();
      expect(floats.values[6], 42);

      floats.undo();
      expect(floats.values[6], 0);
    });
  });

  group('the integer half', () {
    test('undo and redo behave the way the float half does', () {
      final ints = JournalledInts(3)..values.setAll(0, <int>[1, 2, 3]);

      ints
        ..beginStep()
        ..write(0, 10)
        ..write(2, 30)
        ..endStep();
      expect(ints.values, <int>[10, 2, 30]);

      ints.undo();
      expect(ints.values, <int>[1, 2, 3]);

      ints.redo();
      expect(ints.values, <int>[10, 2, 30]);
    });

    test('grow fills the new room with what a caller asked for', () {
      // −1 is what a half-edge array means by "no twin", so a topology growing
      // into fresh slots must not read them as half-edge zero.
      final ints = JournalledInts(2)
        ..values.setAll(0, <int>[7, 8])
        ..grow(6, fill: -1);

      expect(ints.values[0], 7);
      expect(ints.values[1], 8);
      expect(ints.values[4], -1);
    });

    test('a step carries the ints it replaced, as ints', () {
      final ints = JournalledInts(2)
        ..beginStep()
        ..write(0, 5)
        ..endStep();

      expect(ints.journalBytes, 8);
      expect(ints.values, isA<Int32List>());
    });
  });
}
