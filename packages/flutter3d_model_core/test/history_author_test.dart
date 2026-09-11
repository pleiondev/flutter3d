/// `mcp-10n`: authorship on history steps — `HistoryStep.author`, and an
/// agent's own `undo` refusing past a person's own step.
///
///     dart test test/history_author_test.dart
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

ModelHistory freshHistory() {
  var project = const ModelProject();
  project = project.added(
    (int id) => ModelObject(
      id: id,
      name: 'block',
      geometry: EditedGeometry(EditMesh.cuboid()),
      transform: Matrix4.identity(),
    ),
  );
  final history = ModelHistory(project);
  history.selection = ProjectSelection(
    mode: SelectionMode.object,
    objects: const <int>[1],
  );
  return history;
}

void main() {
  group('a step\'s own author', () {
    test('defaults to person when run names none', () {
      final history = freshHistory();
      history.run(MoveBy(Vector3(1, 0, 0)));
      expect(history.steps.single.author, StepAuthor.person);
    });

    test('is agent when run names one', () {
      final history = freshHistory();
      history.run(MoveBy(Vector3(1, 0, 0)), author: StepAuthor.agent);
      expect(history.steps.single.author, StepAuthor.agent);
    });

    test('a transaction takes the author of its own first command', () {
      final history = freshHistory();
      history.beginTransaction();
      history.run(MoveBy(Vector3(1, 0, 0)), author: StepAuthor.agent);
      history.run(MoveBy(Vector3(0, 1, 0)), author: StepAuthor.person);
      history.endTransaction();
      expect(history.steps, hasLength(1));
      expect(history.steps.single.author, StepAuthor.agent);
    });

    test('amend keeps the step\'s own original author', () {
      // Mutation: rebuild the amended step with the default author instead
      // of the original one — an agent's own step, adjusted through a
      // slider, would silently become a person's, and its own undo would
      // stop being refusable.
      final history = freshHistory();
      history.run(MoveBy(Vector3(1, 0, 0)), author: StepAuthor.agent);
      history.amend(MoveBy(Vector3(2, 0, 0)));
      expect(history.steps.single.author, StepAuthor.agent);
    });
  });

  group('the row\'s own acceptance: agent, then person, then undo', () {
    test('an agent\'s own undo refuses a person\'s step on top, with a '
        'name for whose it is', () {
      final history = freshHistory();
      history.run(MoveBy(Vector3(1, 0, 0)), author: StepAuthor.agent);
      history.run(MoveBy(Vector3(0, 1, 0)), author: StepAuthor.person);

      expect(history.topStepAuthor, StepAuthor.person);
      // Mutation: drop the `onlyIfAuthoredBy` check entirely — this would
      // still return true and take the person's own step back, which is
      // exactly the row's own rule against.
      expect(history.undo(onlyIfAuthoredBy: StepAuthor.agent), isFalse);
      expect(history.steps, hasLength(2)); // nothing was taken back
    });

    test('a person\'s own ⌘Z (no filter) undoes both, in order, regardless '
        'of who made them', () {
      final history = freshHistory();
      history.run(MoveBy(Vector3(1, 0, 0)), author: StepAuthor.agent);
      history.run(MoveBy(Vector3(0, 2, 0)), author: StepAuthor.person);

      expect(history.undo(), isTrue); // takes back the person's own step
      expect(history.topStepAuthor, StepAuthor.agent);
      expect(history.undo(), isTrue); // now the agent's
      expect(history.canUndo, isFalse);
      expect(
        history.project.objects.single.transform.getTranslation(),
        Vector3.zero(),
      );
    });

    test('once the top step is the agent\'s own, the agent\'s undo takes it '
        'back', () {
      final history = freshHistory();
      history.run(MoveBy(Vector3(1, 0, 0)), author: StepAuthor.agent);
      history.run(MoveBy(Vector3(0, 1, 0)), author: StepAuthor.agent);

      expect(history.undo(onlyIfAuthoredBy: StepAuthor.agent), isTrue);
      expect(
        history.project.objects.single.transform.getTranslation(),
        Vector3(1, 0, 0),
      );
    });
  });

  group('redo carries the author across, both ways', () {
    test('undo then redo answers the same author it started with', () {
      // Mutation: rebuild the undone/redone step with the default author —
      // an agent's own step would read as a person's after one round trip
      // through the redo stack, silently widening what a later agent
      // undo is allowed to reach.
      final history = freshHistory();
      history.run(MoveBy(Vector3(1, 0, 0)), author: StepAuthor.agent);
      history.undo();
      history.redo();
      expect(history.steps.single.author, StepAuthor.agent);
    });
  });
}
