/// The commands themselves: what each one does, and what each one refuses.
///
///     dart test test/commands_test.dart
///
/// The mesh ones are the interesting half, because they are the ones that do
/// not keep a document — `p0-05` chose a journal over copy-on-write chunks, and
/// a journal has no old versions in it. What is asserted below is that the two
/// halves move together: a project put back to before a loop cut must not be
/// holding a mesh that still has the cut in it.
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A project holding one cube, edited rather than parametric.
ModelHistory edited() {
  final project = const ModelProject().added(
    (int id) => ModelObject(
      id: id,
      name: 'cube',
      geometry: EditedGeometry(EditMesh.cuboid()),
      transform: Matrix4.identity(),
    ),
  );
  return ModelHistory(project)
    ..selection = const ProjectSelection(
      mode: SelectionMode.mesh,
      objects: <int>[1],
    );
}

/// The mesh of object 1.
EditMesh meshOf(ModelHistory history) =>
    (history.project[1]!.geometry as EditedGeometry).mesh;

/// The faces of object 1, at face level.
ProjectSelection faces(ModelHistory history, List<int> ids) =>
    history.selection.copyWith(level: ElementLevel.face, elements: ids);

void main() {
  group('adding', () {
    test('a primitive arrives selected and parametric', () {
      final history = ModelHistory(const ModelProject());

      expect(history.run(const AddPrimitive(kind: 'cylinder')), isNull);

      final object = history.project.objects.single;
      expect(object.geometry, isA<ParametricGeometry>());
      // Mutation: leave the selection alone, and the next thing anybody does
      // after adding a box — move it — is done to nothing, so the person has
      // to click the thing they just made.
      expect(history.selection.objects, <int>[object.id]);
      expect(history.undoSays, 'add a cylinder');
    });

    test('a kind nobody builds is refused with the list', () {
      final history = ModelHistory(const ModelProject());

      final said = history.run(const AddPrimitive(kind: 'teapot'));

      expect(said, contains('teapot'));
      expect(said, contains('cylinder'));
      expect(history.project.objects, isEmpty);
    });

    test('a size of nothing is refused', () {
      final history = ModelHistory(const ModelProject());

      // A primitive of no size is a primitive nobody can see, select or scale
      // back up: every later scale multiplies by nothing.
      expect(history.run(const AddPrimitive(kind: 'box', size: 0)), isNotNull);
      expect(history.project.objects, isEmpty);
    });
  });

  group('baking', () {
    test('a shape becomes a mesh, and undo puts the shape back', () {
      final history = ModelHistory(const ModelProject())
        ..run(const AddPrimitive(kind: 'box'));

      expect(history.run(const BakeToMesh(1)), isNull);
      expect(history.project[1]!.geometry, isA<EditedGeometry>());

      // The history keeps documents, so the parametric object comes back whole
      // — the radius and the segment count with it. There is no command the
      // other way and there should not be one that pretends.
      history.undo();
      expect(history.project[1]!.geometry, isA<ParametricGeometry>());
    });

    test('a mesh is not baked twice', () {
      final history = edited();

      expect(history.run(const BakeToMesh(1)), contains('already a mesh'));
    });
  });

  group('parenting', () {
    test('a cycle is refused rather than made', () {
      var project = const ModelProject();
      for (var i = 0; i < 2; i++) {
        project = project.added(
          (int id) => ModelObject(
            id: id,
            name: 'o$id',
            geometry: EditedGeometry(EditMesh.cuboid()),
            transform: Matrix4.identity(),
          ),
        );
      }
      final history = ModelHistory(project)..run(const SetParent(id: 2, to: 1));

      // Mutation: drop the walk up the parents. The hierarchy becomes a ring,
      // and every traversal in the application — drawing, exporting, computing
      // a world matrix — runs until the stack does.
      expect(history.run(const SetParent(id: 1, to: 2)), contains('already'));
      expect(history.run(const SetParent(id: 1, to: 1)), contains('own'));
      expect(history.project[1]!.parent, isNull);
    });
  });

  group('turning and scaling', () {
    test('two objects turn about the middle of the pair, not their own', () {
      var project = const ModelProject();
      for (var i = 0; i < 2; i++) {
        project = project.added(
          (int id) => ModelObject(
            id: id,
            name: 'o$id',
            geometry: EditedGeometry(EditMesh.cuboid()),
            // At 1 and 3, so the middle of the pair is 2 and is nowhere near
            // the origin: a turn about the origin and a turn about the middle
            // are then different answers rather than the same one by accident.
            transform: Matrix4.translation(Vector3(id == 1 ? 1 : 3, 0, 0)),
          ),
        );
      }
      final history = ModelHistory(project)
        ..selection = const ProjectSelection(objects: <int>[1, 2]);

      // A half turn about Y, about the middle of the two, swaps them.
      expect(
        history.run(
          RotateBy(axis: Vector3(0, 1, 0), radians: 3.141592653589793),
        ),
        isNull,
      );

      // Mutation: turn each object about its own origin instead, which is the
      // simpler arithmetic — and two objects a person has selected and turned
      // stay exactly where they were, facing differently. Every modeller does
      // the other thing, and the gizmo sits at the middle to say so.
      expect(
        history.project[1]!.transform.getTranslation().x,
        closeTo(3, 1e-6),
      );
      expect(
        history.project[2]!.transform.getTranslation().x,
        closeTo(1, 1e-6),
      );
    });

    test('a scale of zero is refused', () {
      final history = ModelHistory(const ModelProject())
        ..run(const AddPrimitive(kind: 'box'));

      // Mutation: apply it. The object flattens into a plane no later scale can
      // bring back, because every one of them multiplies by nothing — and the
      // step that did it looks like any other scale in the history.
      expect(history.run(const ScaleBy(0)), contains('flatten'));
    });
  });

  group('a mesh command', () {
    test('extrudes, and undo takes the geometry back with the document', () {
      final history = edited();
      history.selection = faces(history, <int>[0]);
      final mesh = meshOf(history);
      final before = mesh.faceCount;

      expect(history.run(const Extrude(0.5)), isNull);
      expect(mesh.faceCount, before + 4);

      history.undo();
      // Mutation: leave `meshSteps` out of the step, so undo puts the document
      // back and leaves the mesh where it was. The project is then holding an
      // object whose version says "before the extrude" and a mesh that still
      // has the extrusion in it — a document that disagrees with itself and
      // draws geometry no step of the history describes.
      expect(mesh.faceCount, before);

      history.redo();
      expect(mesh.faceCount, before + 4);
    });

    test('the object gets a new version so a viewport uploads again', () {
      final history = edited();
      history.selection = faces(history, <int>[0]);
      final version = history.project[1]!.version;

      history.run(const Extrude(0.5));

      // Mutation: hand back the project unchanged because the mesh was edited
      // in place — which is true and is exactly the trap. Nothing in the
      // document moves, so a viewport watching versions never uploads and the
      // extrusion is invisible until something else happens to touch the
      // object.
      expect(history.project[1]!.version, version + 1);
    });

    test('refuses a shape that still knows its parameters, and says so', () {
      final history = ModelHistory(const ModelProject())
        ..run(const AddPrimitive(kind: 'cylinder'));
      history.selection = history.selection.copyWith(
        mode: SelectionMode.mesh,
        level: ElementLevel.face,
        elements: <int>[0],
      );

      final said = history.run(const Extrude(0.5));

      // Not a silent no-op and not a silent conversion: pulling a face out of a
      // cylinder is the thing that stops it being a cylinder, and doing it
      // quietly throws the radius and the segment count away with no step in
      // the history to say where they went.
      // Mutation: shorten the refusal to "cannot edit this object". It is
      // true, it is useless, and the person is left to guess that there is a
      // conversion and that it can be taken back.
      expect(said, contains('still a cylinder'));
      expect(said, contains('Convert'));
      expect(history.canUndo, isTrue);
      expect(history.undoSays, 'add a cylinder');
    });

    test('a refusal does not take back the edit before it', () {
      final history = edited();
      history.selection = faces(history, <int>[0]);
      history.run(const Extrude(0.5));
      final faceCount = meshOf(history).faceCount;

      history.selection = history.selection.copyWith(elements: const <int>[]);
      expect(history.run(const Extrude(0.5)), isNotNull);

      // Mutation: undo the mesh unconditionally after a refusal. `endStep`
      // already discards a step that wrote nothing, so the undo goes one
      // further back and the extrude before it silently comes out.
      expect(meshOf(history).faceCount, faceCount);
    });

    test('a hundred nudges in a transaction are one step on both sides', () {
      final history = edited();
      history.selection = history.selection.copyWith(
        level: ElementLevel.vertex,
        elements: <int>[0, 1, 2, 3],
      );
      final mesh = meshOf(history);
      final at = Vector3.zero();
      mesh.positionOf(0, at);
      final startY = at.y;

      history.transaction(() {
        for (var i = 0; i < 100; i++) {
          history.run(
            TransformElements(Matrix4.translation(Vector3(0, 0.001, 0))),
          );
        }
      });

      mesh.positionOf(0, at);
      // A hundred additions of a thousandth, in the single precision a position
      // buffer is stored at: the tolerance is the width of the storage over a
      // hundred steps rather than a hedge about the arithmetic.
      expect(at.y, closeTo(startY + 0.1, 1e-5));

      expect(history.undo(), isTrue);
      // Mutation: count one mesh step per transaction instead of one per
      // command, and a drag of a hundred frames is rolled back by one — the
      // vertex lands ninety-nine thousandths away from where it started, and
      // every later undo is off by the same amount again.
      mesh.positionOf(0, at);
      // Exact, and that is the point of a journal of previous values: it puts
      // back the numbers that were there rather than subtracting what was
      // added, so a hundred rounded steps undo to the position the vertex
      // actually had.
      expect(at.y, startY);
      expect(history.canUndo, isFalse);
    });
  });
}
