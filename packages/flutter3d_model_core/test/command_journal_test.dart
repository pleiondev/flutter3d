/// A journal that can put a project back together from nothing but the
/// commands that made it.
///
///     dart test test/command_journal_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('recording and replaying', () {
    test('thirty commands replay to the same bytes ProjectWriter writes', () {
      final history = ModelHistory(const ModelProject());
      final journal = CommandJournal();

      String? run(ModelCommand command) {
        final String? refused = history.run(command);
        // Mutation: record even a refused command. Nothing here refuses, so
        // the mutation would be silent until somebody's journal held a line
        // that never happened and replay stopped on it.
        if (refused == null) journal.record(command);
        return refused;
      }

      for (var i = 0; i < 10; i++) {
        expect(run(const AddPrimitive(kind: 'box')), isNull);
      }
      for (var id = 1; id <= 10; id++) {
        expect(run(Rename(id: id, to: 'object $id')), isNull);
      }
      for (var id = 1; id <= 10; id++) {
        expect(
          run(
            SetTransform(
              id: id,
              to: Matrix4.translation(Vector3(id.toDouble(), 0, 0)),
            ),
          ),
          isNull,
        );
      }
      expect(journal.length, 30);

      final replay = CommandJournal.replay(
        journal.toBytes(),
        const ModelProject(),
      );

      expect(replay.ok, isTrue);
      // Mutation: run the replayed commands against selection state or in the
      // wrong order and this still has 10 objects with the right names — the
      // byte comparison is what catches a transform applied to the wrong id
      // or a project whose `nextId` came out different.
      expect(
        writeProject(replay.history!.project),
        writeProject(history.project),
      );
    });

    test('a transaction replays as one undo step', () {
      // `SetTransform` rather than `MoveBy`, and on purpose: it names its
      // object in its own arguments — `doc-06`'s rule — where `MoveBy` reads
      // `selection`, and object-level selection is picked with a mouse click
      // rather than through any `ModelCommand` in this build. A recorded
      // journal cannot replay a command whose meaning depends on a selection
      // nothing in the journal ever set; see the library comment.
      final history = ModelHistory(const ModelProject());
      final journal = CommandJournal();
      history.run(const AddPrimitive(kind: 'box'));
      journal.record(const AddPrimitive(kind: 'box'));

      journal.transaction(() {
        history.transaction(() {
          for (var i = 1; i <= 5; i++) {
            final step = SetTransform(
              id: 1,
              to: Matrix4.translation(Vector3(i.toDouble(), 0, 0)),
            );
            history.run(step);
            journal.record(step);
          }
        });
      });
      expect(
        history.project.objects.single.transform.getTranslation(),
        Vector3(5, 0, 0),
      );

      final replay = CommandJournal.replay(
        journal.toBytes(),
        const ModelProject(),
      );
      expect(replay.ok, isTrue);
      final ModelHistory replayed = replay.history!;
      expect(
        replayed.project.objects.single.transform.getTranslation(),
        Vector3(5, 0, 0),
      );

      // Mutation: drop `beginTransaction`/`endTransaction` from `replay` and
      // the undo stack it reaches has six entries instead of two — the add
      // and each of the five moves, none of them grouped — so one ⌘Z here
      // would take back one move instead of the whole drag.
      expect(replayed.undoSays, 'set the transform');
      replayed.undo();
      expect(
        replayed.project.objects.single.transform.getTranslation(),
        Vector3.zero(),
      );
      expect(replayed.undoSays, 'add a box');
    });

    test('a transaction left open at the end of the file still replays', () {
      // The shape a crash mid-drag leaves: a `begin` with no matching `end`.
      // Mutation: refuse an unclosed transaction instead of closing it. A
      // recovery journal exists exactly for the file that stops here, and
      // refusing it would throw away every edit the person made before the
      // crash rather than the ones after it — there are none of those.
      final journal = CommandJournal()
        ..beginTransaction()
        ..record(const AddPrimitive(kind: 'sphere'));

      final replay = CommandJournal.replay(
        journal.toBytes(),
        const ModelProject(),
      );

      expect(replay.ok, isTrue);
      expect(replay.history!.project.objects, hasLength(1));
    });
  });

  group('what it refuses, and where', () {
    test('a line that is not JSON names itself by number', () {
      final journal = CommandJournal()
        ..record(const AddPrimitive(kind: 'box'))
        ..record(const AddPrimitive(kind: 'box'));
      final bytes = journal.toBytes();
      final broken = <int>[...bytes, ...'not json\n'.codeUnits];

      final replay = CommandJournal.replay(
        Uint8List.fromList(broken),
        const ModelProject(),
      );

      expect(replay.ok, isFalse);
      expect(replay.refused, contains('line 3'));
    });

    test('a command this build does not know names itself by number', () {
      final journal = CommandJournal()..record(const AddPrimitive(kind: 'box'));
      final bytes = journal.toBytes();
      final broken = <int>[...bytes, ...'{"name":"phaseTwoOnly"}\n'.codeUnits];

      final replay = CommandJournal.replay(
        Uint8List.fromList(broken),
        const ModelProject(),
      );

      expect(replay.ok, isFalse);
      expect(replay.refused, contains('line 2'));
    });

    test('a command that refuses on replay names itself by number and by '
        'its own reason', () {
      final journal = CommandJournal()
        ..record(const AddPrimitive(kind: 'box'))
        // Refuses on an empty project: nothing at line 1 made two objects.
        ..record(const Rename(id: 99, to: 'ghost'));

      final replay = CommandJournal.replay(
        journal.toBytes(),
        const ModelProject(),
      );

      expect(replay.ok, isFalse);
      expect(replay.refused, contains('line 2'));
      expect(replay.refused, contains('there is no object 99'));
    });

    test('a blank line is not a line', () {
      final journal = CommandJournal()..record(const AddPrimitive(kind: 'box'));
      final bytes = journal.toBytes();
      final withBlank = <int>[...bytes, ...'\n'.codeUnits];

      final replay = CommandJournal.replay(
        Uint8List.fromList(withBlank),
        const ModelProject(),
      );

      expect(replay.ok, isTrue);
      expect(replay.history!.project.objects, hasLength(1));
    });
  });
}
