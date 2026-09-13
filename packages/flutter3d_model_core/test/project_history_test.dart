/// `doc-31d`: a project's own undo history, written into the `.f3dproj`
/// file beside it.
///
///     dart test test/project_history_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_formats/flutter3d_formats.dart' show EncodedImage;
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/src/command.dart';
import 'package:flutter3d_model_core/src/history.dart';
import 'package:flutter3d_model_core/src/project.dart';
import 'package:flutter3d_model_core/src/project_format.dart';
import 'package:flutter3d_model_core/src/selection.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// One cuboid, id 1, at the origin — the same starting point every test in
/// this file undoes back to.
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
  group('ModelHistory.steps and .withSteps, in memory', () {
    test('steps is empty on a fresh history and grows one entry a '
        'command', () {
      final history = freshHistory();
      expect(history.steps, isEmpty);
      history.run(MoveBy(Vector3(1, 0, 0)));
      expect(history.steps, hasLength(1));
      expect(history.steps.single.command, isA<MoveBy>());
    });

    test('withSteps starts with those steps already undoable', () {
      final history = freshHistory();
      history.run(MoveBy(Vector3(5, 0, 0)));
      final moved = history.project;

      // A fresh ModelHistory built directly from the steps, the same shape
      // reading a file back gives — not `history` itself, so this proves
      // the constructor does the work rather than borrowing `history`'s
      // own stack.
      final rebuilt = ModelHistory.withSteps(moved, history.steps);
      expect(rebuilt.canUndo, isTrue);
      expect(rebuilt.undo(), isTrue);
      expect(
        rebuilt.project.objects.single.transform.getTranslation(),
        Vector3.zero(),
      );
    });
  });

  group('round trip', () {
    test('three commands, saved with history, opened, undone three times, '
        'is the project before any of them', () {
      final history = freshHistory();
      final original = history.project;

      history.run(MoveBy(Vector3(1, 0, 0)));
      history.run(MoveBy(Vector3(0, 2, 0)));
      history.run(MoveBy(Vector3(0, 0, 3)));
      expect(
        history.project.objects.single.transform.getTranslation(),
        Vector3(1, 2, 3),
      );

      final bytes = writeProject(history.project, history: history);
      final read = readProject(bytes);
      expect(read, isA<ProjectOpened>());
      final opened = read as ProjectOpened;
      // Mutation: write `stepJson` for the current project's own state
      // instead of each step's `before` — every step would then hold the
      // same, final transform, and undoing would move nowhere.
      expect(opened.history, hasLength(3));

      final reopened = ModelHistory.withSteps(
        opened.project,
        opened.history,
        selection: history.selection,
      );
      expect(reopened.undo(), isTrue);
      expect(reopened.undo(), isTrue);
      expect(reopened.undo(), isTrue);
      expect(reopened.undo(), isFalse); // nothing further back

      expect(
        reopened.project.objects.single.transform,
        original.objects.single.transform,
      );
    });

    test('the untouched mesh chunk is identical across every step and the '
        'current project — not four copies of the same cube', () {
      // Mutation: drop `meshAt`'s own dedup and go back to writing every
      // object's mesh unconditionally — this test is the one built
      // specifically to notice: `MoveBy` never touches the mesh, so every
      // one of the four object lists below (three historical, one live)
      // names the exact same chunk if the writer is deduplicating by
      // identity, four different ones if it is not.
      final history = freshHistory();
      history.run(MoveBy(Vector3(1, 0, 0)));
      history.run(MoveBy(Vector3(0, 1, 0)));
      history.run(MoveBy(Vector3(0, 0, 1)));

      final bytes = writeProject(history.project, history: history);
      final opened = readProject(bytes) as ProjectOpened;

      final currentMesh =
          (opened.project.objects.single.geometry as EditedGeometry).mesh;
      for (final step in opened.history) {
        final stepMesh =
            (step.before.objects.single.geometry as EditedGeometry).mesh;
        expect(identical(stepMesh, currentMesh), isTrue);
      }
    });

    test('a file with no history section opens with an empty one', () {
      final history = freshHistory();
      history.run(MoveBy(Vector3(1, 0, 0)));

      final bytes = writeProject(history.project); // no `history:` at all
      final opened = readProject(bytes) as ProjectOpened;
      expect(opened.history, isEmpty);
    });
  });

  group('file size', () {
    test('a file with history is no larger than one without it plus the '
        'JSON steps — the shared mesh chunk is not paid for twice', () {
      final history = freshHistory();
      history.run(MoveBy(Vector3(1, 0, 0)));
      history.run(MoveBy(Vector3(0, 1, 0)));
      history.run(MoveBy(Vector3(0, 0, 1)));

      final withoutHistory = writeProject(history.project);
      final withHistory = writeProject(history.project, history: history);

      // The cuboid's own chunk, the one thing worth *not* paying for three
      // extra times: with `meshAt`'s own dedup working, `MoveBy` — which
      // never touches the mesh — should leave the history section costing
      // only its own JSON, nowhere near three more copies of this.
      final oneMeshChunk = EditMesh.cuboid().toBytes().lengthInBytes;

      // Mutation: drop the `meshAt` dedup (write every step's mesh as its
      // own new chunk) — three redundant copies of the cuboid's own chunk,
      // on top of the JSON three steps cost regardless, blow straight
      // through a bound sized for those three copies alone.
      expect(
        withHistory.length,
        lessThan(withoutHistory.length + 3 * oneMeshChunk),
      );
    });
  });

  group("Г5's own byte limit", () {
    test('trims the oldest steps first when the history would not fit', () {
      final history = freshHistory();
      for (var i = 0; i < 20; i++) {
        history.run(MoveBy(Vector3(i.toDouble(), 0, 0)));
      }
      expect(history.steps, hasLength(20));

      // A budget too small for all twenty steps but large enough for a few
      // — found by trying a fresh write and halving the observed size,
      // not guessed.
      final full = writeProject(history.project, history: history);
      final tightBudget = (full.length * 0.3).round();

      final trimmed = writeProject(
        history.project,
        history: history,
        maxHistoryBytes: tightBudget,
      );
      final opened = readProject(trimmed) as ProjectOpened;

      // Mutation: trim the *newest* steps instead (`kept.sublist(0,
      // kept.length - 1)`) — the count assertion alone would not catch
      // this, since the same number of steps survives either way; the
      // command check does, since dropping from the front keeps the
      // largest offsets and dropping from the back keeps the smallest.
      expect(opened.history.length, lessThan(20));
      expect(opened.history, isNotEmpty);
      final firstKeptOffset =
          (opened.history.first.command as MoveBy).by.x;
      expect(firstKeptOffset, greaterThan(0));
    });

    test('a budget too small for even one step leaves history empty, not '
        'a refusal', () {
      final history = freshHistory();
      history.run(MoveBy(Vector3(1, 0, 0)));
      final bytes = writeProject(
        history.project,
        history: history,
        maxHistoryBytes: 1,
      );
      final opened = readProject(bytes) as ProjectOpened;
      expect(opened.history, isEmpty);
    });
  });

  group('what a step changed besides a transform', () {
    test('an extrusion saved with history reopens undoable, and the save '
        'leaves the live mesh where it was', () {
      final history = freshHistory();
      history.selection = const ProjectSelection(
        mode: SelectionMode.mesh,
        objects: <int>[1],
        level: ElementLevel.face,
        elements: <int>[0],
      );
      EditMesh live() =>
          (history.project.objects.single.geometry as EditedGeometry).mesh;
      final facesBefore = live().faceCount;
      expect(history.run(const Extrude(0.5)), isNull);

      final bytes = writeProject(history.project, history: history);

      // Mutation: roll the journal back to write the step and forget to roll
      // it forward. The picture on screen loses the extrusion the moment the
      // person presses save.
      expect(live().faceCount, facesBefore + 4);

      final opened = readProject(bytes) as ProjectOpened;
      final reopened = ModelHistory.withSteps(opened.project, opened.history);
      EditMesh reopenedMesh() =>
          (reopened.project.objects.single.geometry as EditedGeometry).mesh;
      expect(reopenedMesh().faceCount, facesBefore + 4);

      // Mutation: deduplicate mesh chunks by identity alone. The step before
      // the extrusion holds the very instance the live project does, so both
      // name one chunk — the extruded one — and this undo moves nothing.
      expect(reopened.undo(), isTrue);
      expect(reopenedMesh().faceCount, facesBefore);

      // And the live history's own undo still has its journal to roll.
      expect(history.undo(), isTrue);
      expect(live().faceCount, facesBefore);
    });

    test('a material added inside the kept steps is gone again after the '
        'reopened undo', () {
      final history = freshHistory();
      expect(history.run(const AddMaterial(materialName: 'steel')), isNull);

      final opened =
          readProject(writeProject(history.project, history: history))
              as ProjectOpened;
      final reopened = ModelHistory.withSteps(opened.project, opened.history);
      expect(reopened.project.materials, hasLength(1));

      // Mutation: build every `before` with the live project's tables. The
      // undo puts the objects back and leaves the steel in the table.
      expect(reopened.undo(), isTrue);
      expect(reopened.project.materials, isEmpty);
    });

    test('an image only a kept step still samples is written for that step '
        'and comes back when it is undone', () {
      final image = EncodedImage(
        bytes: Uint8List.fromList(<int>[137, 80, 78, 71, 1, 2, 3, 4]),
        name: 'old',
        mimeType: 'image/png',
      );
      final live = freshHistory().project;
      final history = ModelHistory.withSteps(live, <HistoryStep>[
        HistoryStep(
          command: MoveBy(Vector3(1, 0, 0)),
          before: live.copyWith(images: <EncodedImage>[image]),
          selectionBefore: ProjectSelection.none,
        ),
      ]);

      final opened =
          readProject(writeProject(history.project, history: history))
              as ProjectOpened;
      // Mutation: append history's image to the live image table. An older
      // reader holds that table to the manifest's count, and this one would
      // open a project with an image it does not have.
      expect(opened.project.images, isEmpty);

      final reopened = ModelHistory.withSteps(opened.project, opened.history);
      expect(reopened.undo(), isTrue);
      expect(reopened.project.images.single.bytes, image.bytes);
      expect(reopened.project.images.single.name, 'old');
    });
  });
}
