/// `ux-45`'s own half in core: a step remembers which client made it, an
/// amend changes whose the step is, and every one of an author's steps can be
/// taken back at once.
///
///     dart test test/authorship_test.dart
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

ModelProject _cube() => const ModelProject().added(
  (int id) => ModelObject(
    id: id,
    name: 'cube',
    geometry: EditedGeometry(EditMesh.cuboid()),
    transform: Matrix4.identity(),
  ),
);

void main() {
  group('ux-45: who made a step', () {
    test('two clients leave two authors, not one "agent"', () {
      final history = ModelHistory(_cube())
        ..selection = ProjectSelection(objects: <int>[1])
        ..run(
          const Rename(id: 1, to: 'by the assistant'),
          author: StepAuthor.agent,
          client: 'claude',
        )
        ..run(
          const Rename(id: 1, to: 'by the script'),
          author: StepAuthor.agent,
          client: 'a build script',
        )
        ..run(const Rename(id: 1, to: 'by hand'));

      // Mutation: one `StepAuthor.agent` for everybody, which is what this
      // was. A person with an assistant in the editor and a script running
      // beside it saw one stack and no way to tell which had done what.
      expect(history.authorship.map((it) => it.client), <String?>[
        'claude',
        'a build script',
        null,
      ]);
      expect(history.authorship.last.author, StepAuthor.person);
    });

    test('a person amending an agent step makes it theirs', () {
      final history = ModelHistory(_cube())
        ..selection = ProjectSelection(objects: <int>[1])
        ..run(
          const Rename(id: 1, to: 'the agent chose this'),
          author: StepAuthor.agent,
          client: 'claude',
        );
      expect(history.topStepAuthor, StepAuthor.agent);

      expect(history.amend(const Rename(id: 1, to: 'I chose this')), isNull);

      // Mutation: keep the step marked as the agent's. An agent's own undo
      // would then reach past a person's hand and take back the name they
      // had just typed over it.
      expect(history.topStepAuthor, StepAuthor.person);
      expect(history.authorship.single.client, isNull);
      expect(history.project[1]!.name, 'I chose this');
      expect(history.undo(onlyIfAuthoredBy: StepAuthor.agent), isFalse);
    });

    test('an agent amending its own step keeps its name on it', () {
      final history = ModelHistory(_cube())
        ..selection = ProjectSelection(objects: <int>[1])
        ..run(
          const Rename(id: 1, to: 'first try'),
          author: StepAuthor.agent,
          client: 'claude',
        );

      expect(
        history.amend(
          const Rename(id: 1, to: 'second try'),
          by: StepAuthor.agent,
          client: 'claude',
        ),
        isNull,
      );
      expect(history.topStepAuthor, StepAuthor.agent);
      expect(history.authorship.single.client, 'claude');
    });

    test('a transaction carries the client of whoever opened it', () {
      final history = ModelHistory(_cube())
        ..selection = ProjectSelection(objects: <int>[1]);
      history.transaction(() {
        history
          ..run(
            const Rename(id: 1, to: 'one'),
            author: StepAuthor.agent,
            client: 'claude',
          )
          ..run(
            const Rename(id: 1, to: 'two'),
            author: StepAuthor.agent,
            client: 'claude',
          );
      });

      expect(history.steps, hasLength(1));
      expect(history.authorship.single.client, 'claude');
    });
  });

  group('ux-45: undoing all of an author\'s steps', () {
    ModelHistory threeAgentSteps() {
      final history = ModelHistory(_cube())
        ..selection = ProjectSelection(objects: <int>[1]);
      for (final String name in <String>['a', 'b', 'c']) {
        history.run(
          Rename(id: 1, to: name),
          author: StepAuthor.agent,
          client: 'claude',
        );
      }
      return history;
    }

    test('takes the whole run back, and says how many', () {
      final ModelHistory history = threeAgentSteps();

      // Mutation: take one back and make the person press again. "Undo the
      // agent's work" is one thing a person wants in one moment, usually the
      // moment it has gone wrong.
      expect(history.undoAllBy(StepAuthor.agent), 3);
      expect(history.steps, isEmpty);
      expect(history.project[1]!.name, 'cube');
    });

    test('stops at the first step of somebody else', () {
      final ModelHistory history = threeAgentSteps()
        ..run(const Rename(id: 1, to: 'mine'));

      // Mutation: step over it. Taking back what is under a person's own
      // edit would mean re-running that edit against a document it was never
      // made against.
      expect(history.undoAllBy(StepAuthor.agent), 0);
      expect(history.project[1]!.name, 'mine');
    });

    test('and one client can be taken back without touching the other', () {
      final ModelHistory history = ModelHistory(_cube())
        ..selection = ProjectSelection(objects: <int>[1])
        ..run(
          const Rename(id: 1, to: 'the script'),
          author: StepAuthor.agent,
          client: 'a build script',
        )
        ..run(
          const Rename(id: 1, to: 'the assistant'),
          author: StepAuthor.agent,
          client: 'claude',
        );

      expect(history.undoAllBy(StepAuthor.agent, client: 'claude'), 1);
      expect(history.project[1]!.name, 'the script');
      expect(history.steps, hasLength(1));
    });

    test('nothing to take back is nothing taken back', () {
      expect(ModelHistory(_cube()).undoAllBy(StepAuthor.agent), 0);
    });
  });
}
