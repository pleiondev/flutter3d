/// The document and the stack of changes behind it.
///
///     dart test test/project_test.dart
///
/// No Flutter anywhere, which is the whole reason this package exists: a
/// command-line exporter, a service that checks an uploaded asset and the tool
/// an agent speaks to all need to know what a change means, and none of them
/// has a window.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart' hide EnumHint;
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

  group('ProjectProfile.profileHints', () {
    test('a hint exists for every field a profile editor would show', () {
      const profile = ProjectProfile();
      expect(
        profile.profileHints.keys,
        unorderedEquals(<String>[
          'target',
          'maxTriangles',
          'maxJoints',
          'maxInfluences',
          'maxTextureSize',
          'maxTextureBytes',
          'requireTriangles',
          'requireManifold',
          'texelsPerMeter',
          'fps',
          'frameSnap',
          // `pro-sc-09`: a browser's own sculpt ceiling is a number a
          // project states, not one this build decides for it.
          'sculptTriangleLimitWeb',
        ]),
      );
    });

    test('maxJoints never advertises more than the shader can hold', () {
      // Mutation: raise the hint's `max` past 64 (say, to 128, the profile's
      // own old default before it was tightened to match `Skeleton.maxJoints`)
      // — a UI honouring this hint would then let someone dial up a profile
      // no skinning shader in the engine could actually keep.
      final hint = const ProjectProfile().profileHints['maxJoints'];
      expect(hint, isA<IntHint>());
      expect((hint! as IntHint).max, 64);
    });

    test('target is an enum hint naming every ProfileTarget by its name', () {
      final hint = const ProjectProfile().profileHints['target'];
      expect(hint, isA<EnumHint>());
      expect((hint! as EnumHint).values, ['desktop', 'mobile', 'web']);
    });

    test('the two require* flags are flags, not ranges', () {
      const profile = ProjectProfile();
      expect(profile.profileHints['requireTriangles'], isA<BoolHint>());
      expect(profile.profileHints['requireManifold'], isA<BoolHint>());
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

    test('a duplicate of a parametric object shares the geometry', () {
      final project = const ModelProject().added(
        (int id) => ModelObject(
          id: id,
          name: 'a',
          geometry: ParametricGeometry(ParametricCuboid()),
          transform: Matrix4.identity(),
        ),
      );
      final made = const DuplicateObjects()
          .apply(project, allOf(project))
          .project!;

      // Safe here, and only here: `SetParametric` replaces the shape whole
      // rather than editing it in place, so two objects naming the same one
      // cannot see each other's edits. `commands_test.dart`'s `duplicating`
      // group holds the mesh case, where sharing is not safe — an `EditMesh`
      // is a journal mutated in place, and duplicating one now copies it.
      expect(
        identical(made.objects[0].geometry, made.objects[1].geometry),
        isTrue,
      );
    });

    // The round trip over every command name moved to `commands_test.dart`
    // when the commands themselves did: the sample list there carries the
    // pivot and the space that `RotateBy` and `ScaleBy` now take, and two
    // lists of samples for one `modelCommandNames` is two lists to forget to
    // add to.

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

  group('the material table', () {
    /// A project of [count] cubes painted from a table of one steel.
    ModelProject painted(int count) {
      var project = ModelProject(
        materials: <ProjectMaterial>[
          ProjectMaterial(surface: SurfaceMaterial(name: 'steel')),
        ],
        images: <EncodedImage>[
          EncodedImage(bytes: Uint8List.fromList(<int>[9]), name: 'atlas'),
        ],
      );
      for (var i = 0; i < count; i++) {
        project = project.added(
          (int id) => ModelObject(
            id: id,
            name: 'bolt $id',
            geometry: EditedGeometry(EditMesh.cuboid()),
            transform: Matrix4.identity(),
            materialSlots: const <int>[0],
          ),
        );
      }
      return project;
    }

    test('adding an object keeps the tables', () {
      // Every one of these builds a whole new `ModelProject`, and a field left
      // off one of those constructor calls is a table that silently empties on
      // the next edit. The mutation is dropping `materials:` from `added` — the
      // model turns grey the moment somebody adds a cube, and nothing else in
      // the suite notices.
      expect(painted(2).materials, hasLength(1));
      expect(painted(2).images, hasLength(1));
    });

    test('replacing an object keeps the tables', () {
      final project = painted(1);
      final moved = project.withObject(
        project.objects.single.copyWith(
          transform: Matrix4.translation(Vector3(1, 0, 0)),
        ),
      );

      // Mutation: drop `materials:` from `withObject`. Dragging an object is
      // what a person does most, so the paint would come off the whole model on
      // the first nudge.
      expect(moved.materials, hasLength(1));
      expect(moved.images, hasLength(1));
    });

    test('deleting the last object that used a material keeps it', () {
      final project = painted(1);
      final empty = project.removed(project.objects.single.id);

      // Not a leak and not tidiness either: a material is shared, and undo has
      // to be able to put the object back onto the steel it was painted with. A
      // delete that swept the table would make undo a different document from
      // the one before the delete.
      expect(empty.objects, isEmpty);
      expect(empty.materials, hasLength(1));
    });

    test('a changed material moves its version', () {
      final before = ProjectMaterial(surface: SurfaceMaterial(name: 'steel'));
      final after = before.withSurface(SurfaceMaterial(name: 'brass'));

      // The version is what a pool of uploaded textures reads to know it has to
      // build the material again. Mutation: keep the version — the model keeps
      // drawing the old paint until something else forces a rebuild.
      expect(after.version, before.version + 1);
      expect(after.surface.name, 'brass');
    });
  });

  group('vertexCount', () {
    // `mat-33d`'s own status-line line: `triangleCount`'s twin, summed the
    // same way.
    test("sums each object's own geometry.vertexCount", () {
      final one = cubes(1);
      final int singleCubeVertices = one.objects.single.geometry.vertexCount;

      expect(one.vertexCount, singleCubeVertices);
      expect(cubes(2).vertexCount, singleCubeVertices * 2);
    });

    test('a socket contributes nothing — it has no geometry to count', () {
      final project = const ModelProject().added(
        (int id) => ModelObject(
          id: id,
          name: 'socket',
          geometry: const SocketGeometry(),
          transform: Matrix4.identity(),
        ),
      );

      expect(project.vertexCount, 0);
    });
  });
}
