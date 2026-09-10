/// The document and the stack of changes behind it.
///
///     dart test test/project_test.dart
///
/// No Flutter anywhere, which is the whole reason this package exists: a
/// command-line exporter, a service that checks an uploaded asset and the tool
/// an agent speaks to all need to know what a change means, and none of them
/// has a window.
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A project with [count] cubes in it, named `a`, `b`, …
ModelProject cubes(int count) {
  var project = const ModelProject();
  for (var i = 0; i < count; i++) {
    project = project.added(
      (int id) => ModelObject(
        id: id,
        name: String.fromCharCode(0x61 + i),
        geometry: EditedGeometry(EditMesh.cuboid()),
        transform: Matrix4.identity(),
      ),
    );
  }
  return project;
}

/// Everything selected, in object mode.
ProjectSelection allOf(ModelProject project) => ProjectSelection(
  objects: <int>[for (final ModelObject each in project.objects) each.id],
);

void main() {
  group('the document', () {
    test('an edit shares everything it did not touch', () {
      final before = cubes(3);
      final moved = before.withObject(
        before.objects[1].copyWith(name: 'moved'),
      );

      // Mutation: rebuild every object in `withObject` — copy them all, which
      // is the obvious way to write "a new project" — and these are false. A
      // step of history keeps a whole project, so an edit that copies
      // everything makes undo cost the document rather than a pointer, and a
      // hundred steps over a large scene is a hundred documents in memory.
      expect(identical(moved.objects[0], before.objects[0]), isTrue);
      expect(identical(moved.objects[2], before.objects[2]), isTrue);
      expect(identical(moved.objects[1], before.objects[1]), isFalse);
      expect(moved.objects[1].name, 'moved');
    });

    test('an edit moves the version and nothing else can', () {
      final object = cubes(1).objects.single;

      // Mutation: leave `version` alone in `copyWith` — a field that looks like
      // bookkeeping — and a viewport has no way to tell an object that moved
      // from one that did not, so it either uploads everything every frame or
      // compares meshes to find out.
      expect(object.copyWith(name: 'x').version, object.version + 1);
      expect(object.version, 1);
    });

    test('an id is never handed out twice', () {
      var project = cubes(2);
      final first = project.objects.first.id;
      project = project.removed(first);
      project = project.added(
        (int id) => ModelObject(
          id: id,
          name: 'new',
          geometry: EditedGeometry(EditMesh.cuboid()),
          transform: Matrix4.identity(),
        ),
      );

      // Mutation: put `nextId` back to the highest id in use after a delete,
      // which is what "tidy up the numbering" looks like — and a step of
      // history that names the deleted object starts naming the new one the
      // moment it is undone and redone.
      expect(project.objects.map((ModelObject o) => o.id), <int>[2, 3]);
      expect(project[first], isNull);
    });

    test('deleting takes the children with it', () {
      var project = cubes(3);
      final parent = project.objects[0].id;
      final child = project.objects[1].id;
      final grandchild = project.objects[2].id;
      project = project
          .withObject(project.objects[1].copyWith(parent: parent))
          .withObject(project.objects[2].copyWith(parent: child));

      final left = project.removed(parent);

      // Mutation: filter the list once by parent instead of walking to a fixed
      // point, and the grandchild survives with a parent that is gone — an arm
      // floating where the body used to be.
      expect(left.objects, isEmpty);
      expect(project.removed(child)[grandchild], isNull);
    });

    test('replacing something that is not there is a fault', () {
      final project = cubes(1);
      final stranger = ModelObject(
        id: 99,
        name: 'stranger',
        geometry: EditedGeometry(EditMesh.cuboid()),
        transform: Matrix4.identity(),
      );

      // Adding through the same door as replacing is how an object ends up in
      // the project twice under one id, and no lookup would say which.
      expect(() => project.withObject(stranger), throwsArgumentError);
    });
  });

  group('a command', () {
    test('refuses with a sentence rather than an exception', () {
      final project = cubes(1);
      final outcome = const DeleteObjects().apply(
        project,
        ProjectSelection.none,
      );

      expect(outcome.ok, isFalse);
      expect(outcome.refused, contains('nothing is selected'));
      expect(outcome.project, isNull);
    });

    test('a duplicate selects what it made', () {
      final project = cubes(1);
      final outcome = const DuplicateObjects().apply(project, allOf(project));

      // Mutation: leave the selection alone after a duplicate, and a person who
      // copies something and drags is dragging the original — which is the
      // commonest two-step in a modeller and the easiest to get wrong.
      expect(outcome.ok, isTrue);
      expect(outcome.project!.objects, hasLength(2));
      expect(outcome.selection!.objects, <int>[2]);
    });

    test('a duplicate shares the geometry until either is edited', () {
      final project = cubes(1);
      final made = const DuplicateObjects()
          .apply(project, allOf(project))
          .project!;

      // Mutation: deep-copy the `EditMesh` and duplicating a two hundred
      // thousand face model costs a whole mesh — for a copy the person may be
      // about to move and never touch.
      expect(
        identical(made.objects[0].geometry, made.objects[1].geometry),
        isTrue,
      );
    });

    test('every name round-trips through JSON', () {
      final samples = <ModelCommand>[
        const Rename(id: 1, to: 'body'),
        SetTransform(id: 1, to: Matrix4.identity()),
        MoveBy(Vector3(1, 0, -2)),
        RotateBy(axis: Vector3(0, 1, 0), radians: 0.5),
        const ScaleBy(2),
        const SetParent(id: 2, to: 1),
        const AddPrimitive(kind: 'cylinder', size: 2, segments: 12),
        const BakeToMesh(1),
        const DeleteObjects(),
        const DuplicateObjects(),
        const Extrude(0.25),
        const LoopCut(cuts: 2),
        const DeleteElements(),
        TransformElements(Matrix4.identity(), what: 'turn'),
        const MergeByDistance(distance: 0.01),
        const DissolveEdges(),
        const Triangulate(),
        const RecalculateNormals(flip: true),
      ];

      // Every name has a sample, which is what stops a command being added to
      // the sealed set and forgotten by the journal — the file would then read
      // back a project missing exactly the steps nobody wrote a case for.
      expect(
        samples.map((ModelCommand c) => c.name).toSet(),
        modelCommandNames.toSet(),
      );
      for (final ModelCommand sample in samples) {
        final back = modelCommandFromJson(sample.toJson());
        expect(back, isNotNull, reason: '${sample.name} did not read back');
        expect(back!.toJson(), sample.toJson());
      }
    });

    test('incomplete JSON is null rather than a throw', () {
      // A journal is replayed entry by entry, and an entry from a newer version
      // of the application is one to skip. Throwing would lose the whole file
      // over one line.
      expect(modelCommandFromJson(<String, Object?>{'name': 'rename'}), isNull);
      expect(modelCommandFromJson(<String, Object?>{'name': 'nope'}), isNull);
      expect(modelCommandFromJson('rename'), isNull);
      expect(
        modelCommandFromJson(<String, Object?>{
          'name': 'moveBy',
          'by': <Object?>[1, 'x', 3],
        }),
        isNull,
      );
    });

    test('a whole number reads back as a distance', () {
      // JSON has one number type and most encoders write a translation of
      // exactly zero as `0`. Refusing those would make a round trip fail on the
      // commonest value there is.
      final back = modelCommandFromJson(<String, Object?>{
        'name': 'moveBy',
        'by': <Object?>[0, 2, 0],
      });
      expect(back, isA<MoveBy>());
      expect((back! as MoveBy).by.y, 2.0);
    });
  });

  group('the history', () {
    test('undo puts back the document that was there', () {
      final history = ModelHistory(cubes(2))
        ..selection = ProjectSelection(objects: <int>[1]);
      final before = history.project;

      expect(history.run(const Rename(id: 1, to: 'body')), isNull);
      expect(history.project[1]!.name, 'body');

      expect(history.undo(), isTrue);
      // Mutation: have each command know how to reverse itself and apply that
      // instead. It is right for a rename and wrong the first time an operation
      // clamps, rounds or refuses part of its own input — and then it is
      // quietly wrong for ever, because nothing compares the two paths.
      expect(identical(history.project, before), isTrue);
      expect(history.redo(), isTrue);
      expect(history.project[1]!.name, 'body');
    });

    test('a hundred moves inside a transaction are one step', () {
      final history = ModelHistory(cubes(1))
        ..selection = ProjectSelection(objects: <int>[1]);

      history.transaction(() {
        for (var i = 0; i < 100; i++) {
          history.run(MoveBy(Vector3(0.01, 0, 0)));
        }
      });

      // Mutation: record each command instead, which is what a history without
      // transactions does — and getting back to where a drag began takes a
      // hundred presses of ⌘Z, which is the single most complained-about
      // behaviour a tool can have.
      expect(history.undoSays, 'move');
      expect(history.undo(), isTrue);
      expect(
        history.project[1]!.transform.getTranslation().x,
        closeTo(0, 1e-9),
      );
      expect(history.canUndo, isFalse);
    });

    test('a transaction that changed nothing leaves no step', () {
      final history = ModelHistory(cubes(1));

      history.transaction(() {
        // Nothing selected, so every one of these is refused.
        for (var i = 0; i < 5; i++) {
          history.run(MoveBy(Vector3(1, 0, 0)));
        }
      });

      expect(history.canUndo, isFalse);
    });

    test('a refusal is not a step', () {
      final history = ModelHistory(cubes(1));

      expect(history.run(const DeleteObjects()), isNotNull);

      expect(history.canUndo, isFalse);
      expect(history.undoSays, isNull);
    });

    test('the menu says what it would take back', () {
      final history = ModelHistory(cubes(1))
        ..selection = ProjectSelection(objects: <int>[1])
        ..run(const Rename(id: 1, to: 'body'));

      // Mutation: return a fixed 'undo' and the menu item stops being able to
      // tell a person which of the last six things they did is about to come
      // back.
      expect(history.undoSays, 'rename to "body"');
      history.undo();
      expect(history.redoSays, 'rename to "body"');
    });

    test('amend adjusts the last step instead of adding one', () {
      final history = ModelHistory(cubes(1))
        ..selection = ProjectSelection(objects: <int>[1])
        ..run(MoveBy(Vector3(1, 0, 0)));

      expect(history.amend(MoveBy(Vector3(3, 0, 0))), isNull);

      // Mutation: run the replacement as a new command, which is the obvious
      // way — and a person dragging the slider on the operation card makes one
      // step per frame, so the stack is full of sixty near-identical moves and
      // ⌘Z takes back a sixtieth of a millimetre.
      expect(history.project[1]!.transform.getTranslation().x, 3.0);
      expect(history.undo(), isTrue);
      expect(history.canUndo, isFalse);
      expect(history.project[1]!.transform.getTranslation().x, 0.0);
    });

    test('an amend that is refused leaves the model as it was', () {
      final history = ModelHistory(cubes(1))
        ..selection = ProjectSelection(objects: <int>[1])
        ..run(const Rename(id: 1, to: 'body'));

      expect(history.amend(const Rename(id: 1, to: '  ')), isNotNull);

      // The person asked to adjust an operation, not to undo it: reverting to
      // before the rename because the new name was blank would take away a step
      // nobody asked to lose.
      expect(history.project[1]!.name, 'body');
    });

    test('the stack stops at its depth', () {
      final history = ModelHistory(cubes(1), depth: 3)
        ..selection = ProjectSelection(objects: <int>[1]);
      for (var i = 0; i < 10; i++) {
        history.run(MoveBy(Vector3(1, 0, 0)));
      }

      var steps = 0;
      while (history.undo()) {
        steps++;
      }
      // Mutation: leave the stack unbounded. Each step holds a whole project,
      // and an edit that replaces a large mesh shares nothing — a session of a
      // few hundred of those is a gigabyte nobody asked to keep.
      expect(steps, 3);
      expect(history.journal, isEmpty);
    });

    test('a new step drops the redo stack and a redo does not', () {
      final history = ModelHistory(cubes(1))
        ..selection = const ProjectSelection(objects: <int>[1])
        ..run(const Rename(id: 1, to: 'body'))
        ..run(const Rename(id: 1, to: 'torso'))
        ..undo()
        ..undo();

      expect(history.canRedo, isTrue);
      history.redo();
      // Walking forward leaves the way back where it was, and the way forward
      // still holds the step that has not been redone yet.
      expect(history.canUndo, isTrue);
      expect(history.canRedo, isTrue);

      history.run(const Rename(id: 1, to: 'other'));
      // Mutation: drop the `_undone.clear()` from `run`. A person who undid two
      // steps, redid one, then did something different would still be offered
      // ⇧⌘Z — and it would hand back a step from a history that no longer
      // exists, applied to a document it was never made against.
      expect(history.canRedo, isFalse);
    });

    test('dirtiness is identity, and a save settles it', () {
      final history = ModelHistory(cubes(1))
        ..selection = ProjectSelection(objects: <int>[1]);

      expect(history.isDirty, isFalse);
      history.run(const Rename(id: 1, to: 'body'));
      expect(history.isDirty, isTrue);

      // Undone back to the document that was saved. Mutation: compare projects
      // field by field instead of by identity and this still passes, and costs
      // a walk over the document on every keystroke; compare a version counter
      // instead and it fails, because the counter has moved twice.
      history.undo();
      expect(history.isDirty, isFalse);

      history
        ..redo()
        ..markSaved();
      expect(history.isDirty, isFalse);
    });
  });

  group('the selection', () {
    test('survives an undo that brings its object back', () {
      final history = ModelHistory(cubes(2))
        ..selection = ProjectSelection(objects: <int>[1, 2])
        ..run(const DeleteObjects());

      expect(history.selection.objects, isEmpty);
      history.undo();

      // The step carries the selection it was made against, so undoing an
      // accidental delete gives the person their model back *and* what they had
      // selected — otherwise the next thing they do is select it all again.
      expect(history.selection.objects, <int>[1, 2]);
    });

    test('names of objects that are not there are filtered out, not kept', () {
      final history = ModelHistory(cubes(2))
        ..selection = const ProjectSelection(objects: <int>[1, 99]);

      // Mutation: hand `_selection` back as it is instead of through `within`,
      // and a command that walks the selection is handed an id with nothing
      // behind it. `MoveBy` skips those, `DeleteObjects` would not notice, and
      // the status line counts two objects where there is one.
      expect(history.selection.objects, <int>[1]);
      expect(history.selection.says, '1 object');
    });

    test('says what it holds', () {
      expect(ProjectSelection.none.says, 'nothing selected');
      expect(const ProjectSelection(objects: <int>[1]).says, '1 object');
      expect(const ProjectSelection(objects: <int>[1, 2]).says, '2 objects');
      expect(
        const ProjectSelection(
          mode: SelectionMode.mesh,
          level: ElementLevel.face,
          elements: <int>[1, 2, 3],
        ).says,
        '3 faces',
      );
    });

    test('round-trips through JSON', () {
      const selection = ProjectSelection(
        mode: SelectionMode.mesh,
        objects: <int>[3],
        level: ElementLevel.edge,
        elements: <int>[7, 9],
      );

      final back = ProjectSelection.fromJson(selection.toJson());
      expect(back, isNotNull);
      expect(back!.toJson(), selection.toJson());

      // And a broken one is null, not a throw, for the reason the commands give.
      expect(
        ProjectSelection.fromJson(<String, Object?>{'mode': 'no'}),
        isNull,
      );
      expect(ProjectSelection.fromJson(42), isNull);
    });
  });
}
