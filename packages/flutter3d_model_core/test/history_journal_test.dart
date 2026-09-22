/// `tut-05`/`tut-15`: `ModelHistory`'s own attached [CommandJournal] —
/// [ModelHistory.run]/[ModelHistory.amend]/transactions record to it now,
/// regardless of which caller's door they came in through, and a specific
/// pick (`SelectElements`) is itself a real, replayable command rather than
/// a bare `ModelHistory.selection =` assignment.
///
///     dart test test/history_journal_test.dart
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

ModelObject _cube(int id, {String name = 'cube'}) => ModelObject(
  id: id,
  name: name,
  geometry: EditedGeometry(EditMesh.cuboid()),
  transform: Matrix4.identity(),
);

void main() {
  group('a journal attached to ModelHistory hears every run, whoever calls '
      'it', () {
    test('a plain run() with no author named records as StepAuthor.person', () {
      final journal = CommandJournal();
      final history = ModelHistory(
        const ModelProject(),
        recoveryJournal: journal,
      );
      history.run(const AddPrimitive(kind: 'box'));
      expect(journal.length, 1);

      final replay = CommandJournal.replay(
        journal.toBytes(),
        const ModelProject(),
      );
      expect(replay.ok, isTrue, reason: replay.refused);
      // Mutation: record with no author, or always `StepAuthor.agent` —
      // this is `ModelerCubit.run`'s own shape, `now.history.run(command)`,
      // which is exactly how a person's edit reaches this method today.
      expect(replay.history!.topStepAuthor, StepAuthor.person);
    });

    test('a run() naming StepAuthor.agent records as the agent', () {
      final journal = CommandJournal();
      final history = ModelHistory(
        const ModelProject(),
        recoveryJournal: journal,
      );
      history.run(const AddPrimitive(kind: 'box'), author: StepAuthor.agent);

      final replay = CommandJournal.replay(
        journal.toBytes(),
        const ModelProject(),
      );
      expect(replay.ok, isTrue, reason: replay.refused);
      expect(replay.history!.topStepAuthor, StepAuthor.agent);
    });

    test('a journal attached after construction hears every run from then '
        'on, not the ones before it', () {
      final history = ModelHistory(const ModelProject());
      history.run(const AddPrimitive(kind: 'box'));
      expect(history.recoveryJournal, isNull);

      final journal = CommandJournal();
      history.recoveryJournal = journal;
      history.run(const Rename(id: 1, to: 'crate'));
      expect(journal.length, 1);
    });

    test('a transaction collapses to one bracket on the attached journal '
        'too, matching history\'s own one-step undo', () {
      final journal = CommandJournal();
      final history = ModelHistory(
        const ModelProject(),
        recoveryJournal: journal,
      )..run(const AddPrimitive(kind: 'box'));
      history.transaction(() {
        for (var i = 1; i <= 3; i++) {
          history.run(
            SetTransform(
              id: 1,
              to: Matrix4.translation(Vector3(i.toDouble(), 0, 0)),
            ),
          );
        }
      });

      final replay = CommandJournal.replay(
        journal.toBytes(),
        const ModelProject(),
      );
      expect(replay.ok, isTrue, reason: replay.refused);
      // Mutation: forget to bracket the attached journal the same way
      // `history`'s own undo stack is bracketed — this would replay as four
      // steps instead of two (the add, then the drag).
      expect(replay.history!.steps, hasLength(2));
      expect(
        replay.history!.project.objects.single.transform.getTranslation(),
        Vector3(3, 0, 0),
      );
    });

    test('amend records under whoever adjusted it, not a fixed one', () {
      final journal = CommandJournal();
      final history = ModelHistory(
        const ModelProject(),
        recoveryJournal: journal,
      );
      history.run(const AddPrimitive(kind: 'box'), author: StepAuthor.agent);
      history.amend(
        const AddPrimitive(kind: 'box', size: 2.0),
        by: StepAuthor.agent,
      );

      // One line: `amend` overwrote rather than appended.
      expect(journal.length, 1);
      final replay = CommandJournal.replay(
        journal.toBytes(),
        const ModelProject(),
      );
      expect(replay.ok, isTrue, reason: replay.refused);
      // Mutation: record the amend under a fixed author regardless of who
      // adjusted it — the live undo stack's own adjusted step is marked with
      // whoever made the adjustment (`ux-45`, `history_author_test.dart`),
      // and a journal that disagreed with it would leave a replayed
      // session's own later agent `undo` refusing, or not, for the wrong
      // reason.
      expect(replay.history!.topStepAuthor, StepAuthor.agent);
    });

    test('ReplaceDocument never reaches an attached journal, through '
        'either door', () {
      final journal = CommandJournal();
      final history = ModelHistory(
        const ModelProject(),
        recoveryJournal: journal,
      );
      history.run(const AddPrimitive(kind: 'box'));
      history.run(ReplaceDocument(const ModelProject(), 'wipe it'));
      // Mutation: journal every command regardless of `isJournaled` — a
      // `ReplaceDocument` line would read back as `{"name":
      // "replaceDocument"}` alone, which `modelCommandFromJson` cannot
      // resolve (deliberately: it is not in that table), so a cold replay
      // of a session that ever imported anything would refuse at the very
      // step that is meant to stay invisible to this format.
      expect(journal.length, 1);
    });
  });

  group('tut-05: SelectElements makes a specific pick itself replayable', () {
    test('object mode: which object, not a walk over the current selection, '
        'records and replays', () {
      final journal = CommandJournal();
      final project = const ModelProject()
          .added((int id) => _cube(id, name: 'first'))
          .added((int id) => _cube(id, name: 'second'));
      final history = ModelHistory(project, recoveryJournal: journal);
      history.run(const SelectElements(objects: <int>[2]));
      history.run(MoveBy(Vector3(1, 0, 0)));

      final replay = CommandJournal.replay(journal.toBytes(), project);
      expect(replay.ok, isTrue, reason: replay.refused);
      // Object 2 moved and object 1 did not — proof the pick itself
      // replayed, not only the move that read it.
      expect(
        replay.history!.project[2]!.transform.getTranslation(),
        Vector3(1, 0, 0),
      );
      expect(
        replay.history!.project[1]!.transform.getTranslation(),
        Vector3.zero(),
      );
    });

    test('mesh mode: one face of one object by id records and replays — '
        "the exact shape case 2's own rim extrude needs", () {
      final journal = CommandJournal();
      final project = const ModelProject().added((int id) => _cube(id));
      final history = ModelHistory(project, recoveryJournal: journal);
      history.run(
        const SelectElements(object: 1, level: 'face', elements: <int>[0]),
      );
      history.run(const Extrude(0.5));

      final replay = CommandJournal.replay(journal.toBytes(), project);
      // Mutation: have `ModelSession.select` assign `ModelHistory.selection
      // =` directly again instead of running this command — this would
      // refuse with "no faces are selected to extrude", the exact sentence
      // `tut-05` used to leave case 2's own cold replay stuck on.
      expect(replay.ok, isTrue, reason: replay.refused);
      final EditMesh mesh =
          (replay.history!.project[1]!.geometry as EditedGeometry).mesh;
      expect(mesh.faceCount, greaterThan(6));
    });

    test('a level nothing recognises refuses with a sentence, not a decode '
        'failure', () {
      final history = ModelHistory(const ModelProject());
      final refused = history.run(
        const SelectElements(object: 1, level: 'corner'),
      );
      expect(refused, contains('is not a level'));
    });
  });
}
