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

import 'dart:math' as math;

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

/// A project of [count] cubes, each one further along X than the last.
ModelProject cubes(int count) {
  var project = const ModelProject();
  for (var i = 0; i < count; i++) {
    project = project.added(
      (int id) => ModelObject(
        id: id,
        name: 'o$id',
        geometry: EditedGeometry(EditMesh.cuboid()),
        transform: Matrix4.translation(Vector3(id * 2 - 1, 0, 0)),
      ),
    );
  }
  return project;
}

/// One cube already turned a quarter of the way round Y.
///
/// **The one shape a space or a basis can be seen on.** Every conjugation this
/// file tests collapses to the identity on an object nobody has turned, so a
/// test built on an unturned cube passes whether the space is honoured or
/// thrown away.
ModelHistory turnedCube() => ModelHistory(
  const ModelProject().added(
    (int id) => ModelObject(
      id: id,
      name: 'turned',
      geometry: EditedGeometry(EditMesh.cuboid()),
      transform: Matrix4.rotationY(math.pi / 2),
    ),
  ),
)..selection = const ProjectSelection(objects: <int>[1]);

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

    test(
      'triangulating a cube leaves twelve triangles, and undo takes it back',
      () {
        final history = edited();
        history.selection = faces(history, <int>[
          for (var face = 0; face < meshOf(history).faceSlotCount; face++)
            if (meshOf(history).isFaceAlive(face)) face,
        ]);
        final mesh = meshOf(history);

        expect(history.run(const Triangulate()), isNull);
        expect(mesh.faceCount, 12);

        history.undo();
        expect(mesh.faceCount, 6);
      },
    );

    test(
      'dissolving an edge joins the two faces, and says so when it cannot',
      () {
        final history = edited();
        history.selection = history.selection.copyWith(
          level: ElementLevel.edge,
          elements: <int>[0],
        );
        final mesh = meshOf(history);

        expect(history.run(const DissolveEdges()), isNull);
        expect(mesh.faceCount, 5);

        // Nothing selected: refused with a sentence rather than a silent no-op.
        history.selection = history.selection.copyWith(elements: const <int>[]);
        expect(history.run(const DissolveEdges()), contains('no edges'));
      },
    );

    test('an edge with nothing on the other side is refused, not counted', () {
      // A single quad: every one of its four edges is a boundary, so every
      // dissolve refuses and the command has to notice that none of them took.
      final flat =
          ModelHistory(
              const ModelProject().added(
                (int id) => ModelObject(
                  id: id,
                  name: 'quad',
                  geometry: EditedGeometry(
                    EditMesh.fromFaces(
                      <Vector3>[
                        Vector3(0, 0, 0),
                        Vector3(1, 0, 0),
                        Vector3(1, 0, 1),
                        Vector3(0, 0, 1),
                      ],
                      <List<int>>[
                        <int>[0, 1, 2, 3],
                      ],
                    ),
                  ),
                  transform: Matrix4.identity(),
                ),
              ),
            )
            ..selection = const ProjectSelection(
              mode: SelectionMode.mesh,
              objects: <int>[1],
              level: ElementLevel.edge,
              elements: <int>[0],
            );

      // Mutation: drop the `dissolved == 0` check. Every edge refuses, nothing
      // changes, and the command reports success — so the history gains a step
      // that undoes to the same model and the person's ⌘Z appears to do
      // nothing.
      expect(flat.run(const DissolveEdges()), contains('boundary'));
      expect(flat.canUndo, isFalse);
    });

    test('a merge with nothing close enough is refused', () {
      final history = edited();

      // The cube's corners are half a unit apart, so a hair of a distance welds
      // nothing. Mutation: return the new mesh anyway. It has the same contents
      // and is still a new mesh — the object takes a version, the buffers are
      // uploaded again, and the mesh's journal is thrown away, all for a step
      // that changed nothing and that ⌘Z now has to walk past.
      expect(
        history.run(const MergeByDistance(distance: 1e-6)),
        contains('close enough'),
      );
      expect(history.canUndo, isFalse);
    });

    test('a merge replaces the mesh, and undo puts the old one back', () {
      final history = edited();
      history.selection = faces(history, <int>[0]);
      // An edit before the merge, so the mesh has a journal step behind it.
      history.run(const Extrude(0.5));
      final before = meshOf(history);
      final extruded = before.faceCount;

      // Wide enough to weld the whole cube into one point, which is the
      // extreme end of the same operation and is what makes the replacement
      // visible.
      expect(history.run(const MergeByDistance(distance: 10)), isNull);
      expect(identical(meshOf(history), before), isFalse);

      history.undo();
      // Mutation: name the mesh as touched, so the history also rolls its
      // journal back one step. A merge rebuilds rather than edits, so the step
      // it would roll is the *extrusion before it* — the old mesh comes back
      // with the extrusion silently undone as well, and the history says one
      // step was taken.
      expect(identical(meshOf(history), before), isTrue);
      expect(meshOf(history).faceCount, extruded);
    });

    test('normals are made to agree, and can be turned inside out', () {
      final history = edited();
      history.selection = faces(history, <int>[0]);

      // A cube built by `flutter3d_mesh` already agrees with itself, so asking
      // for consistency is refused — which is the honest answer and not a
      // failure.
      expect(
        history.run(const RecalculateNormals()),
        contains('already agrees'),
      );

      // Flipping is the other half of the menu item and always does something.
      expect(history.run(const RecalculateNormals(flip: true)), isNull);
      expect(history.undoSays, 'flip the normals');
    });

    test('a turn is about the middle of what is selected, once', () {
      final history = edited();
      // The four corners of one face of the cube, which sit at x = ±0.5 and
      // have a middle at x = 0 — so a turn about the middle is not the same
      // answer as a turn about the origin by accident. Move them first, so the
      // middle is somewhere the origin is not.
      history.selection = history.selection.copyWith(
        level: ElementLevel.vertex,
        elements: <int>[0, 1, 2, 3],
      );
      history.run(TransformElements(Matrix4.translation(Vector3(4, 0, 0))));
      final mesh = meshOf(history);
      final before = medianOf(mesh, history.selection.asMeshSelection);
      expect(before.x, closeTo(4, 1e-5));

      // A half turn about Y. About the median, the four corners swap sides and
      // the median stays put.
      expect(
        history.run(
          TransformElements(
            Matrix4.compose(
              Vector3.zero(),
              Quaternion.axisAngle(Vector3(0, 1, 0), 3.141592653589793),
              Vector3.all(1),
            ),
            what: 'turn',
          ),
        ),
        isNull,
      );

      // Mutation: zero the pivot — `final about = Vector3.zero()`. The
      // selection swings round the origin instead and lands at x = −4, eight
      // units from where it was. This is the mutation that survived the first
      // time round, and it is the same arithmetic the application was
      // duplicating: the modal transform wrapped the matrix in the median as
      // well, so a mesh-mode turn happened about twice it.
      final after = medianOf(mesh, history.selection.asMeshSelection);
      expect(after.x, closeTo(4, 1e-4));
      expect(after.z, closeTo(before.z, 1e-4));
    });

    test('a scale is about the middle too', () {
      final history = edited();
      history.selection = history.selection.copyWith(
        level: ElementLevel.vertex,
        elements: <int>[0, 1, 2, 3],
      );
      history.run(TransformElements(Matrix4.translation(Vector3(4, 0, 0))));
      final mesh = meshOf(history);

      history.run(
        TransformElements(Matrix4.diagonal3(Vector3.all(2)), what: 'scale'),
      );

      // Doubling about the median leaves the median where it is; doubling about
      // the origin would put it at x = 8.
      expect(
        medianOf(mesh, history.selection.asMeshSelection).x,
        closeTo(4, 1e-4),
      );
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

  group('selecting', () {
    test('is a step, so ⌘Z puts back the region that was there', () {
      final history = edited();
      history.selection = faces(history, <int>[0, 1]);

      expect(history.run(const SelectAll()), isNull);
      expect(history.selection.elements, hasLength(6));

      // Selecting used to be an assignment to `history.selection`, which put
      // nothing on the stack: ⌘Z took back whatever edit came before instead,
      // and a region picked out by hand was gone with no way back to it. This
      // is the assertion that it is now a step like any other. No mutation is
      // named against it: what makes it a step is `ModelHistory.run`, which
      // this file does not own.
      expect(history.undo(), isTrue);
      expect(history.selection.elements, <int>[0, 1]);
    });

    test('everything twice is refused rather than stacked', () {
      final history = edited();
      history.selection = faces(history, const <int>[]);

      expect(history.run(const SelectAll()), isNull);

      // Mutation: drop the "already selected" check in `_keep`. The second
      // press goes on the stack, and the ⌘Z after it appears to do nothing
      // because the step it takes back changed nothing.
      expect(history.run(const SelectAll()), contains('already'));
      expect(history.undo(), isTrue);
      expect(history.canUndo, isFalse);
    });

    test('object mode selects, inverts and clears whole objects', () {
      final history = ModelHistory(cubes(3))
        ..selection = const ProjectSelection(objects: <int>[2]);

      expect(history.run(const InvertSelection()), isNull);
      expect(history.selection.objects, <int>[1, 3]);

      expect(history.run(const SelectAll()), isNull);
      expect(history.selection.objects, <int>[1, 2, 3]);

      expect(history.run(const SelectNone()), isNull);
      expect(history.selection.objects, isEmpty);
      expect(history.run(const SelectNone()), contains('already'));
    });

    test('a walk over one mesh is refused in object mode, with somewhere to '
        'go', () {
      final history = ModelHistory(cubes(3))
        ..selection = const ProjectSelection(objects: <int>[1]);

      // Mutation: answer these in object mode by falling back to the active
      // object's mesh. "Grow" then quietly widens a region inside a mesh the
      // person is not looking at and cannot see change.
      expect(history.run(const GrowSelection()), contains('mesh mode'));
      expect(history.run(const ShrinkSelection()), contains('mesh mode'));
      expect(history.run(const SelectLinked()), contains('one mesh'));
      expect(history.run(const SelectEdgeLoop(0)), contains('object mode'));
      expect(history.run(const SelectEdgeRing(0)), contains('object mode'));
      expect(history.run(const SelectByMaterial(0)), contains('mesh mode'));
      expect(history.canUndo, isFalse);
    });

    test('growing and shrinking a face of a cube undo each other', () {
      final history = edited();
      history.selection = faces(history, <int>[0]);

      expect(history.run(const GrowSelection()), isNull);
      // Five: every face of a cube touches a corner of face 0 except the one
      // opposite it, which shares nothing with it at all.
      expect(history.selection.elements, hasLength(5));

      expect(history.run(const ShrinkSelection()), isNull);
      expect(history.selection.elements, <int>[0]);
    });

    test('nothing picked is refused by name rather than grown into nothing', () {
      final history = edited();
      history.selection = faces(history, const <int>[]);

      // Mutation: drop the empty check and call `grown` anyway. It hands back
      // an empty selection, `_keep` then says that is what is selected already,
      // and a person with nothing picked is told they pressed the wrong key.
      expect(
        history.run(const GrowSelection()),
        contains('nothing is selected'),
      );
      expect(
        history.run(const SelectLinked()),
        contains('nothing is selected'),
      );
    });

    test('an edge the mesh no longer has is refused by name', () {
      final history = edited();
      history.selection = faces(history, <int>[0, 1]);
      expect(history.run(const DeleteElements()), isNull);
      history.selection = history.selection.copyWith(
        level: ElementLevel.edge,
        elements: const <int>[],
      );

      // Half-edge 0 belonged to one of the two faces that have just gone. The
      // number is still well inside the arrays and the numbers behind it are
      // still readable; it is simply not an edge any more.
      // Mutation: bounds-check against `halfEdgeSlotCount` instead of asking
      // the mesh which edges it has. The stale number passes, and the walk
      // steps through `nextOf` and `twinOf` from a dead half-edge.
      final said = history.run(const SelectEdgeLoop(0));
      expect(said, contains('no edge 0'));
      expect(said, contains('cube'));

      // And a number that was never in range at all, which is what an argument
      // typed into a tool call looks like.
      expect(history.run(const SelectEdgeRing(999)), contains('no edge 999'));
    });

    test('a loop comes back at edge level whatever level it was asked at', () {
      final history = edited();
      history.selection = faces(history, <int>[0]);

      expect(history.run(const SelectEdgeLoop(0)), isNull);

      // Mutation: keep the level the selection already had. The elements are
      // then edge numbers filed under `ElementLevel.face`, so the overlay draws
      // faces that were never picked and a conversion reads nonsense.
      expect(history.selection.level, ElementLevel.edge);
      expect(history.selection.elements, contains(0));
    });

    test('faces on one material slot are picked out, and an empty slot says '
        'so', () {
      final history = edited();
      // Through a journal step because every write to a mesh takes one, and the
      // slots are as journalled as the positions.
      meshOf(history)
        ..beginStep()
        ..setMaterialSlot(2, 1)
        ..setMaterialSlot(4, 1)
        ..endStep();
      history.selection = faces(history, const <int>[]);

      expect(history.run(const SelectByMaterial(1)), isNull);
      expect(history.selection.level, ElementLevel.face);
      expect(history.selection.elements, <int>[2, 4]);

      // Mutation: hand the empty selection back as a success. Pressing the
      // button for a slot nothing is on throws away everything the person had
      // picked and says nothing about why.
      expect(
        history.run(const SelectByMaterial(7)),
        contains('material slot 7'),
      );
      expect(history.selection.elements, <int>[2, 4]);
    });

    test('selecting does not make the file dirty', () {
      final history = ModelHistory(cubes(2))..markSaved();

      expect(history.run(const SelectAll()), isNull);

      // Mutation: build a new `ModelProject` on the way out — a `copyWith` with
      // nothing changed would do it. `isDirty` is identity, so every click
      // would put a dot on the title bar and ask to save a document nobody
      // edited.
      expect(history.isDirty, isFalse);
    });
  });

  group('the pivot and the space', () {
    test('individual leaves the objects where they are, median swings them', () {
      final history = ModelHistory(cubes(2))
        ..selection = const ProjectSelection(objects: <int>[1, 2]);

      expect(
        history.run(
          RotateBy(
            axis: Vector3(0, 1, 0),
            radians: math.pi,
            pivot: TransformPivot.individual,
          ),
        ),
        isNull,
      );

      // Mutation: ignore the pivot and use the middle of the selection every
      // time. A row of chairs turned to face the same way instead swings round
      // the middle of the row and every chair ends up somewhere else.
      expect(
        history.project[1]!.transform.getTranslation().x,
        closeTo(1, 1e-6),
      );
      expect(
        history.project[2]!.transform.getTranslation().x,
        closeTo(3, 1e-6),
      );
    });

    test('local turns an object about its own axes', () {
      final history = turnedCube();

      expect(
        history.run(
          RotateBy(
            axis: Vector3(1, 0, 0),
            radians: math.pi / 2,
            pivot: TransformPivot.individual,
            space: TransformSpace.local,
          ),
        ),
        isNull,
      );

      // Where the object's own +Z now points, in world. A quarter turn about
      // the object's own X sends it to −Y; the same turn about the world's X
      // would have left it at +X.
      // Mutation: ignore the space and use the world's axes. "Turn this about
      // its own up" goes the wrong way on everything already facing sideways,
      // and it is invisible on the unturned cube a test usually builds.
      final Vector3 forward = history.project[1]!.transform.transform3(
        Vector3(0, 0, 1),
      );
      expect(forward.x, closeTo(0, 1e-6));
      expect(forward.y, closeTo(-1, 1e-6));
      expect(forward.z, closeTo(0, 1e-6));
    });

    test('a nudge in world axes lands along the object\'s axes', () {
      final history = turnedCube();
      history.selection = history.selection.copyWith(
        mode: SelectionMode.mesh,
        level: ElementLevel.vertex,
        elements: <int>[0],
      );
      final mesh = meshOf(history);
      final before = mesh.positionOf(0);

      expect(
        history.run(TransformElements(Matrix4.translation(Vector3(1, 0, 0)))),
        isNull,
      );

      // The vertices are stored in the object's own frame, so a metre along the
      // world's X is a metre along the object's −... whichever way a quarter
      // turn about Y sends it, which is +Z.
      // Mutation: apply `by` to the positions as it arrives. A drag along the
      // screen's X moves the vertices of a turned object sideways, and the
      // further the object is from square-on the further the geometry goes from
      // under the pointer.
      final Vector3 moved = mesh.positionOf(0) - before;
      expect(moved.x, closeTo(0, 1e-6));
      expect(moved.y, closeTo(0, 1e-6));
      expect(moved.z, closeTo(1, 1e-6));
    });

    test('local on elements is the frame they are already in', () {
      final history = turnedCube();
      history.selection = history.selection.copyWith(
        mode: SelectionMode.mesh,
        level: ElementLevel.vertex,
        elements: <int>[0],
      );
      final mesh = meshOf(history);
      final before = mesh.positionOf(0);

      expect(
        history.run(
          TransformElements(
            Matrix4.translation(Vector3(1, 0, 0)),
            space: TransformSpace.local,
          ),
        ),
        isNull,
      );

      final Vector3 moved = mesh.positionOf(0) - before;
      expect(moved.x, closeTo(1, 1e-6));
      expect(moved.z, closeTo(0, 1e-6));
    });

    test('each element about its own centre is refused, not faked', () {
      final history = edited();
      history.selection = faces(history, <int>[0]);

      // Mutation: accept it and apply the median transform anyway. Two faces
      // sharing a corner both claim it, `transformSelection` moves it once, and
      // the mesh comes apart in a way no step of the history describes.
      expect(
        history.run(
          TransformElements(
            Matrix4.identity(),
            pivot: TransformPivot.individual,
          ),
        ),
        contains('pulled apart'),
      );
      expect(history.canUndo, isFalse);
    });
  });

  group('the journal', () {
    test('every name has a sample and round-trips through JSON', () {
      final samples = <ModelCommand>[
        const Rename(id: 1, to: 'body'),
        SetTransform(id: 1, to: Matrix4.identity()),
        MoveBy(Vector3(1, 0, -2)),
        RotateBy(
          axis: Vector3(0, 1, 0),
          radians: 0.5,
          pivot: TransformPivot.individual,
          space: TransformSpace.local,
        ),
        const ScaleBy(2, pivot: TransformPivot.individual),
        const SetParent(id: 2, to: 1),
        const AddPrimitive(kind: 'cylinder', size: 2, segments: 12),
        const BakeToMesh(1),
        const DeleteObjects(),
        const DuplicateObjects(),
        const Extrude(0.25),
        const LoopCut(cuts: 2),
        const DeleteElements(),
        TransformElements(
          Matrix4.identity(),
          what: 'turn',
          space: TransformSpace.local,
        ),
        const MergeByDistance(distance: 0.01),
        const DissolveEdges(),
        const Triangulate(),
        const RecalculateNormals(flip: true),
        const SelectAll(),
        const SelectNone(),
        const InvertSelection(),
        const GrowSelection(),
        const ShrinkSelection(),
        const SelectLinked(),
        const SelectEdgeLoop(4),
        const SelectEdgeRing(4),
        const SelectByMaterial(2),
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

    test('the pivot and the space survive being written down', () {
      // **Matching JSON is not enough on its own.** A command that left an
      // argument out of `arguments` writes a map without it, reads back the
      // default, and writes the same map again — so the round trip above
      // agrees with itself while the pivot quietly goes missing. These read the
      // values back instead.
      // Mutation: drop 'pivot' and 'space' from `RotateBy.arguments`. Every
      // journalled turn about an object's own origin replays about the middle
      // of the selection, and a file that opens without complaint is a
      // different model from the one somebody saved.
      final RotateBy turned =
          modelCommandFromJson(
                RotateBy(
                  axis: Vector3(0, 1, 0),
                  radians: 0.5,
                  pivot: TransformPivot.individual,
                  space: TransformSpace.local,
                ).toJson(),
              )!
              as RotateBy;
      expect(turned.pivot, TransformPivot.individual);
      expect(turned.space, TransformSpace.local);

      final ScaleBy scaled =
          modelCommandFromJson(
                const ScaleBy(2, pivot: TransformPivot.individual).toJson(),
              )!
              as ScaleBy;
      expect(scaled.pivot, TransformPivot.individual);

      final TransformElements moved =
          modelCommandFromJson(
                TransformElements(
                  Matrix4.identity(),
                  space: TransformSpace.local,
                ).toJson(),
              )!
              as TransformElements;
      expect(moved.space, TransformSpace.local);
      expect(moved.pivot, TransformPivot.median);
    });

    test('a pivot from a newer version is skipped, a missing one is median', () {
      // Mutation: fall back to `median` for a word this version does not know,
      // the way a missing key does. A step written as "about the cursor" then
      // replays about the middle of the selection in silence, which is a file
      // that opens and is wrong rather than a file that says what it could not
      // read.
      expect(
        modelCommandFromJson(<String, Object?>{
          'name': 'scaleBy',
          'by': 2,
          'pivot': 'cursor',
        }),
        isNull,
      );

      // No pivot at all is a journal written before there were pivots, and
      // median is what those entries meant.
      final back = modelCommandFromJson(<String, Object?>{
        'name': 'scaleBy',
        'by': 2,
      });
      expect(back, isA<ScaleBy>());
      expect((back! as ScaleBy).pivot, TransformPivot.median);
    });
  });
}
