/// A journal that can put a project back together from nothing but the
/// commands that made it.
///
///     dart test test/command_journal_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_mesh/flutter3d_mesh.dart'
    show ParametricCuboid, ParametricShape;
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

  group('tut-03: amend overwrites rather than appending', () {
    test('a plain step: one line replaced by one line, not two', () {
      final journal = CommandJournal()
        ..record(const AddPrimitive(kind: 'box', size: 1.0));

      journal.amend(const AddPrimitive(kind: 'box', size: 2.0));

      expect(journal.length, 1);
      final replay = CommandJournal.replay(
        journal.toBytes(),
        const ModelProject(),
      );
      expect(replay.ok, isTrue, reason: replay.refused);
      // Mutation: append instead of overwriting, and this project would
      // hold two boxes — a 1.0 m one nothing amended away, and a second,
      // 2.0 m one beside it — rather than one box at the adjusted size,
      // the same document `ModelHistory.amend` itself reaches live.
      expect(replay.history!.project.objects, hasLength(1));
      final ParametricShape shape =
          (replay.history!.project.objects.single.geometry
                  as ParametricGeometry)
              .shape;
      expect((shape as ParametricCuboid).size, Vector3.all(2.0));
    });

    test('a step recorded as a whole transaction loses the whole bracket, '
        'not only its own last line', () {
      final journal = CommandJournal()..record(const AddPrimitive(kind: 'box'));
      journal.transaction(() {
        journal.record(Rename(id: 1, to: 'one'));
        journal.record(Rename(id: 1, to: 'two'));
        journal.record(Rename(id: 1, to: 'three'));
      });
      expect(journal.length, 6); // add, begin, 3 renames, end

      journal.amend(Rename(id: 1, to: 'amended'));

      // The add survives (it came before the bracket); the whole bracket
      // is gone, replaced by one plain line — not a `begin`/`end` pair
      // around it, since `ModelHistory.amend` replaced the transaction
      // with a single command, not a transaction of one.
      expect(journal.length, 2);
      final replay = CommandJournal.replay(
        journal.toBytes(),
        const ModelProject(),
      );
      expect(replay.ok, isTrue, reason: replay.refused);
      expect(replay.history!.project.objects.single.name, 'amended');
      // One undo step for the add, one for the amended rename — not the
      // three the original transaction would have collapsed to on its
      // own, and not a fourth, stray step for a leftover empty bracket.
      expect(replay.history!.steps, hasLength(2));
    });

    test('an empty journal amends into a single fresh line', () {
      final journal = CommandJournal();
      journal.amend(const AddPrimitive(kind: 'box'));
      expect(journal.length, 1);
    });

    test('the recorded author is the one amend is given, not the original '
        "line's own", () {
      // Recorded with no author at all — the plain `StepAuthor.person`
      // default — so the agent author below can only have come from
      // `amend`'s own argument, not from a line this overwrote.
      final journal = CommandJournal()..record(const AddPrimitive(kind: 'box'));
      journal.amend(
        const AddPrimitive(kind: 'box', size: 2.0),
        author: StepAuthor.agent,
      );
      final replay = CommandJournal.replay(
        journal.toBytes(),
        const ModelProject(),
      );
      expect(replay.ok, isTrue, reason: replay.refused);
      expect(replay.history!.topStepAuthor, StepAuthor.agent);
    });
  });

  group('mcp-12n: the author rides along', () {
    test('an agent\'s own line reads back as StepAuthor.agent', () {
      final history = ModelHistory(const ModelProject());
      final journal = CommandJournal();
      const command = AddPrimitive(kind: 'box');
      history.run(command, author: StepAuthor.agent);
      journal.record(command, author: StepAuthor.agent);

      final replay = CommandJournal.replay(
        journal.toBytes(),
        const ModelProject(),
      );
      expect(replay.ok, isTrue);
      // Mutation: `replay` ignoring the line's own `author` key and always
      // calling `history.run(command)` with no author — every step would
      // read back `StepAuthor.person`, and an agent's own `undo`
      // (`mcp-10n`) would refuse to take back work it did itself.
      expect(replay.history!.topStepAuthor, StepAuthor.agent);
    });

    test('a line recorded with no author reads back as StepAuthor.person, '
        'the same as a journal written before this row existed', () {
      final journal = CommandJournal()..record(const AddPrimitive(kind: 'box'));
      final replay = CommandJournal.replay(
        journal.toBytes(),
        const ModelProject(),
      );
      expect(replay.ok, isTrue);
      expect(replay.history!.topStepAuthor, StepAuthor.person);
    });

    test('a transaction of several agent commands replays as one step, '
        'still authored by the agent', () {
      final history = ModelHistory(const ModelProject());
      final journal = CommandJournal();
      history.run(const AddPrimitive(kind: 'box'), author: StepAuthor.agent);
      journal.record(const AddPrimitive(kind: 'box'), author: StepAuthor.agent);

      journal.transaction(() {
        history.transaction(() {
          for (var i = 1; i <= 3; i++) {
            final step = SetTransform(
              id: 1,
              to: Matrix4.translation(Vector3(i.toDouble(), 0, 0)),
            );
            history.run(step, author: StepAuthor.agent);
            journal.record(step, author: StepAuthor.agent);
          }
        });
      });

      final replay = CommandJournal.replay(
        journal.toBytes(),
        const ModelProject(),
      );
      expect(replay.ok, isTrue);
      expect(replay.history!.steps, hasLength(2)); // the add, then the drag
      expect(replay.history!.topStepAuthor, StepAuthor.agent);
    });

    test('mcp-12n\'s own acceptance: session, journal, replay in a clean '
        'process, writeProject matches byte for byte', () {
      final history = ModelHistory(const ModelProject());
      final journal = CommandJournal();
      void act(ModelCommand command, {StepAuthor author = StepAuthor.person}) {
        final refused = history.run(command, author: author);
        expect(refused, isNull, reason: refused);
        journal.record(command, author: author);
      }

      act(const AddPrimitive(kind: 'box'), author: StepAuthor.agent);
      act(Rename(id: 1, to: 'crate'), author: StepAuthor.agent);
      act(const AddMaterial(materialName: 'oak'));
      act(const AssignMaterial(id: 1, to: 0));

      // "A clean process" — nothing here is the `history` or `journal`
      // above, only the bytes either one could be handed on disk.
      final replay = CommandJournal.replay(
        journal.toBytes(),
        const ModelProject(),
      );
      expect(replay.ok, isTrue);

      // Mutation: read the author back but never pass it into
      // `ModelHistory.run`, or record it but forget to thread it through
      // `ModelSession.run` — either leaves the bytes matching (this line
      // does not need the author to be right) while `topStepAuthor` above
      // would have already caught it; this line is the row's own literal
      // acceptance, kept as its own assertion rather than folded into one
      // that also happens to prove something else.
      expect(
        writeProject(replay.history!.project),
        writeProject(history.project),
      );
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
