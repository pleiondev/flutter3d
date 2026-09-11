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
import 'dart:typed_data';

import 'package:flutter3d_formats/flutter3d_formats.dart';
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

/// Six times the signed volume, which is positive while the faces wind
/// outward and negative once the surface has been turned inside out.
///
/// A count of faces pointing away from the middle would answer the same
/// question for a box and the wrong one for anything dented; the volume is the
/// same arithmetic an exporter does.
double windingVolume(EditMesh mesh) {
  var total = 0.0;
  final corners = <Vector3>[];
  for (var face = 0; face < mesh.faceSlotCount; face++) {
    if (!mesh.isFaceAlive(face)) continue;
    corners.clear();
    mesh.forEachHalfEdge(face, (int half) {
      corners.add(mesh.positionOf(mesh.originOf(half)));
    });
    for (var i = 1; i + 1 < corners.length; i++) {
      total += corners[0].dot(corners[i].cross(corners[i + 1]));
    }
  }
  return total;
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

  group('duplicating', () {
    test('editing the copy leaves the original mesh untouched', () {
      final history = edited();

      expect(history.run(const DuplicateObjects()), isNull);
      final int copyId = history.selection.objects.single;
      expect(copyId, isNot(1));

      history.selection = history.selection.copyWith(
        mode: SelectionMode.mesh,
        objects: <int>[copyId],
        level: ElementLevel.face,
        elements: <int>[0],
      );
      // Mutation: hand the copy the same `EditMesh` instance the original
      // holds. `EditMesh` is a journal mutated in place — see
      // `mesh_commands.dart` — so an extrude run against the copy would edit
      // the original's mesh as well, and the original would gain a face
      // nobody asked it to have.
      expect(history.run(const Extrude(1.0)), isNull);

      final EditMesh original =
          (history.project[1]!.geometry as EditedGeometry).mesh;
      final EditMesh copy =
          (history.project[copyId]!.geometry as EditedGeometry).mesh;
      expect(!identical(original, copy), isTrue);
      expect(original.vertexCount, EditMesh.cuboid().vertexCount);
      expect(copy.vertexCount, greaterThan(original.vertexCount));
    });

    test('a parametric or an imported geometry is shared, not copied', () {
      final history = ModelHistory(const ModelProject())
        ..run(const AddPrimitive(kind: 'box'));

      expect(history.run(const DuplicateObjects()), isNull);
      final int copyId = history.selection.objects.single;

      // Safe to share: a parametric shape is replaced whole by
      // `SetParametric`, never mutated in place, so two objects pointing at
      // the same one cannot see each other's edits.
      expect(
        identical(
          history.project[1]!.geometry,
          history.project[copyId]!.geometry,
        ),
        isTrue,
      );
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

  group('shapes that still know their parameters', () {
    /// A glass: a profile that starts on the axis, flares and comes back in.
    List<Vector2> glass() => <Vector2>[
      Vector2(0, 0),
      Vector2(0.4, 0),
      Vector2(0.35, 0.2),
      Vector2(0.45, 1),
    ];

    test('a lathe arrives parametric, selected and named', () {
      final history = ModelHistory(const ModelProject());

      expect(
        history.run(
          AddLathe(profile: glass(), segments: 16, shapeName: 'glass'),
        ),
        isNull,
      );

      final object = history.project.objects.single;
      expect(object.name, 'glass');
      expect(object.geometry, isA<ParametricGeometry>());
      expect(history.selection.objects, <int>[object.id]);
      expect(history.undoSays, 'add a glass');
    });

    test('a profile that cannot be turned is refused, with the reason', () {
      final history = ModelHistory(const ModelProject());

      // One point is a circle, not a surface. Mutation: accept it and the
      // lathe builds a mesh of no faces, which the readiness then calls an
      // error somewhere far away from the thing that caused it.
      expect(
        history.run(AddLathe(profile: <Vector2>[Vector2(1, 0)])),
        contains('at least two points'),
      );
      // A negative radius turns the surface through its own axis and gives a
      // shape that is inside out along half its sweep.
      expect(
        history.run(
          AddLathe(profile: <Vector2>[Vector2(-1, 0), Vector2(1, 1)]),
        ),
        contains('negative radius'),
      );
      expect(
        history.run(AddLathe(profile: glass(), segments: 2)),
        contains('three segments'),
      );
      expect(history.project.objects, isEmpty);
    });

    test(
      'the parameters can be set again, and undo puts the old ones back',
      () {
        final history = ModelHistory(const ModelProject())
          ..run(const AddPrimitive(kind: 'sphere', segments: 12));

        expect(
          history.run(
            const SetParametric(
              id: 1,
              to: ParametricSphere(radius: 1, segments: 48),
            ),
          ),
          isNull,
        );

        final shape =
            (history.project[1]!.geometry as ParametricGeometry).shape
                as ParametricSphere;
        expect(shape.segments, 48);

        history.undo();
        final back =
            (history.project[1]!.geometry as ParametricGeometry).shape
                as ParametricSphere;
        // The history keeps documents, so the old parameters come back whole.
        expect(back.segments, 12);
      },
    );

    test('a slider adjusts one step rather than leaving sixty', () {
      final history = ModelHistory(const ModelProject())
        ..run(const AddPrimitive(kind: 'sphere', segments: 12));
      history.run(
        const SetParametric(
          id: 1,
          to: ParametricSphere(radius: 1, segments: 16),
        ),
      );
      final int steps = history.journal.length;

      for (var segments = 17; segments <= 24; segments++) {
        expect(
          history.amend(
            SetParametric(
              id: 1,
              to: ParametricSphere(radius: 1, segments: segments),
            ),
          ),
          isNull,
        );
      }

      // This is what `amend` is for and what makes the operation card usable:
      // eight frames of a drag are eight re-runs against the document as it
      // was, not eight steps to press ⌘Z through.
      expect(history.journal.length, steps);
      final shape =
          (history.project[1]!.geometry as ParametricGeometry).shape
              as ParametricSphere;
      expect(shape.segments, 24);
    });

    test('a mesh is refused by name rather than quietly replaced', () {
      final history = edited();

      // Mutation: replace the geometry anyway. Somebody who converted a shape,
      // spent an hour editing it and then reached for the card would have that
      // hour replaced by a fresh primitive, with one step of history to say so.
      final String? said = history.run(
        const SetParametric(id: 1, to: ParametricSphere()),
      );
      expect(said, contains('"cube" is a mesh now'));
      expect(history.project[1]!.geometry, isA<EditedGeometry>());
    });

    test('the parameters survive being written down', () {
      final AddLathe made = AddLathe(
        profile: glass(),
        segments: 24,
        closedProfile: true,
        shapeName: 'vase',
      );

      final back = modelCommandFromJson(made.toJson());
      expect(back, isA<AddLathe>());
      final AddLathe read = back! as AddLathe;
      // Mutation: leave the profile out of `arguments`. The round trip agrees
      // with itself — a map without the profile reads back as a lathe with no
      // profile and writes the same map — while a journal replays every glass
      // in the file as nothing at all.
      expect(read.profile.length, glass().length);
      expect(read.profile.last.y, closeTo(1.0, 1e-9));
      expect(read.closedProfile, isTrue);
      expect(read.shapeName, 'vase');
    });

    test('a profile with a bad point reads back as null, not as a throw', () {
      expect(
        modelCommandFromJson(<String, Object?>{
          'name': 'addLathe',
          'profile': <Object?>[
            <Object?>[0, 0],
            <Object?>['x', 1],
          ],
          'segments': 12,
          'closedProfile': false,
          'label': 'glass',
        }),
        isNull,
      );
    });

    test('a command with optional fields reads back with their defaults '
        'when the JSON leaves them out', () {
      // A file or a hand-written tool call naming only what it cares about —
      // `addPrimitive` with just a `kind`, say — should read back the same
      // object the constructor's own defaults would build, not refuse for
      // want of a `size` nobody who wrote `AddPrimitive(kind: 'box')` in Dart
      // would ever have to give either. Mutation: require the field the way
      // the round trip above requires `profile`, and a tool call this
      // permissive schema promises to accept is refused instead.
      final addPrimitive =
          modelCommandFromJson(<String, Object?>{
                'name': 'addPrimitive',
                'kind': 'box',
              })!
              as AddPrimitive;
      expect(addPrimitive.size, 1.0);
      expect(addPrimitive.segments, 32);

      final addLathe =
          modelCommandFromJson(<String, Object?>{
                'name': 'addLathe',
                'profile': <Object?>[
                  <Object?>[0, 0],
                  <Object?>[1, 1],
                ],
              })!
              as AddLathe;
      expect(addLathe.segments, 32);
      expect(addLathe.closedProfile, isFalse);
      expect(addLathe.shapeName, 'lathe');

      final loopCut =
          modelCommandFromJson(<String, Object?>{'name': 'loopCut'})!
              as LoopCut;
      expect(loopCut.cuts, 1);
      expect(loopCut.factor, 0.5);

      final recalculateNormals =
          modelCommandFromJson(<String, Object?>{'name': 'recalculateNormals'})!
              as RecalculateNormals;
      expect(recalculateNormals.flip, isFalse);
    });
  });

  group('the material table', () {
    /// A project of one steel-named material and two bolts painted with it.
    ModelHistory painted() {
      final project =
          ModelProject(
            materials: <ProjectMaterial>[
              ProjectMaterial(surface: SurfaceMaterial(name: 'steel')),
            ],
          ).added(
            (int id) => ModelObject(
              id: id,
              name: 'bolt a',
              geometry: EditedGeometry(EditMesh.cuboid()),
              transform: Matrix4.identity(),
              materialSlots: const <int>[0],
            ),
          );
      return ModelHistory(
        project.added(
          (int id) => ModelObject(
            id: id,
            name: 'bolt b',
            geometry: EditedGeometry(EditMesh.cuboid()),
            transform: Matrix4.identity(),
          ),
        ),
      );
    }

    test('a material arrives named, or does not', () {
      final history = ModelHistory(const ModelProject());

      expect(history.run(const AddMaterial(materialName: 'brass')), isNull);
      expect(history.project.materials.single.surface.name, 'brass');
      expect(history.undoSays, 'add material "brass"');

      expect(history.run(const AddMaterial()), isNull);
      expect(history.project.materials.last.surface.name, isNull);
      expect(history.undoSays, 'add a material');
    });

    test('a material name and an image name still round-trip as the '
        'command they belong to', () {
      // Both arguments are called `name` in the sentence that describes them
      // and neither is called `name` in JSON — that key is the command's own,
      // and `toJson` spreads `arguments` over it. Mutation: put either one
      // back under `name` and the round trip below reads back an `AddMaterial`
      // that lost its material's name, or nothing at all for the image, since
      // `modelCommandFromJson` would see `{'name': 'atlas', ...}` and try to
      // build the command called "atlas".
      final AddMaterial material =
          modelCommandFromJson(
                const AddMaterial(materialName: 'brass').toJson(),
              )!
              as AddMaterial;
      expect(material.materialName, 'brass');

      final AddImage image =
          modelCommandFromJson(
                AddImage(
                  bytes: Uint8List.fromList(<int>[1, 2, 3]),
                  imageName: 'atlas',
                ).toJson(),
              )!
              as AddImage;
      expect(image.imageName, 'atlas');
    });

    test('removing a row reindexes what was above it, unpaints what wore '
        'it, and leaves what was below alone', () {
      var project = ModelProject(
        materials: <ProjectMaterial>[
          ProjectMaterial(surface: SurfaceMaterial(name: 'steel')),
          ProjectMaterial(surface: SurfaceMaterial(name: 'brass')),
          ProjectMaterial(surface: SurfaceMaterial(name: 'copper')),
        ],
      );
      for (final (String bolt, int slot) in <(String, int)>[
        ('a', 0),
        ('b', 1),
        ('c', 2),
      ]) {
        project = project.added(
          (int id) => ModelObject(
            id: id,
            name: 'bolt $bolt',
            geometry: EditedGeometry(EditMesh.cuboid()),
            transform: Matrix4.identity(),
            materialSlots: <int>[slot],
          ),
        );
      }
      final history = ModelHistory(project);
      final untouchedA = history.project.objects[0];

      // Mutation: rebuild every object regardless of whether its slot needs
      // to move. Bolt a's slot is 0, below the row being removed, so it must
      // come back `identical` — the same sharing the rest of `ModelProject`
      // promises for an edit that does not touch it.
      expect(history.run(const RemoveMaterial(1)), isNull);
      expect(
        history.project.materials.map((ProjectMaterial m) => m.surface.name),
        <String?>['steel', 'copper'],
      );
      expect(identical(history.project.objects[0], untouchedA), isTrue);
      // Bolt b wore row 1, the row removed, and comes back unpainted.
      expect(history.project.objects[1].materialSlots, isEmpty);
      // Bolt c wore row 2, now row 1.
      expect(history.project.objects[2].materialSlots, <int>[1]);
    });

    test('removing the material an object wears leaves it unpainted', () {
      final history = painted();

      expect(history.run(const RemoveMaterial(0)), isNull);
      expect(history.project.materials, isEmpty);
      expect(history.project.objects.first.materialSlots, isEmpty);
    });

    test('an out-of-range row is refused, both for removing and for '
        'duplicating', () {
      final history = painted();

      expect(history.run(const RemoveMaterial(4)), contains('material 4'));
      expect(history.run(const DuplicateMaterial(4)), contains('material 4'));
    });

    test('a duplicate is named after its source and stands on its own', () {
      final history = painted();

      expect(history.run(const DuplicateMaterial(0)), isNull);
      expect(history.project.materials, hasLength(2));
      expect(history.project.materials.last.surface.name, 'steel copy');

      // Mutation: hand the copy back the same `SurfaceMaterial` instance.
      // `SetMaterialField` on the copy would then be a field set on the
      // original as well, since there would be one object behind both rows.
      history.run(
        const SetMaterialField(index: 1, field: 'metallic', value: 1.0),
      );
      expect(history.project.materials.first.surface.metallic, 0.0);
    });

    test('a field is set by the name `writeFmat` writes it under', () {
      final history = painted();

      expect(
        history.run(
          const SetMaterialField(
            index: 0,
            field: 'baseColor',
            value: <double>[0.2, 0.4, 0.6, 1.0],
          ),
        ),
        isNull,
      );
      final surface = history.project.materials.single.surface;
      // `Vector4` is single-precision, so the tolerance is wider than a
      // `double` field like `roughness` below needs.
      expect(surface.baseColor.r, closeTo(0.2, 1e-6));
      expect(surface.baseColor.a, closeTo(1.0, 1e-6));

      expect(
        history.run(
          const SetMaterialField(index: 0, field: 'roughness', value: 0.1),
        ),
        isNull,
      );
      expect(
        history.project.materials.single.surface.roughness,
        closeTo(0.1, 1e-9),
      );
      // Mutation: forget `roughness` in the rebuild and the colour just set
      // would be thrown away by the very next field this command touches.
      expect(
        history.project.materials.single.surface.baseColor.r,
        closeTo(0.2, 1e-6),
      );

      expect(
        history.run(
          const SetMaterialField(index: 0, field: 'alphaMode', value: 'blend'),
        ),
        isNull,
      );
      expect(
        history.project.materials.single.surface.alphaMode,
        SurfaceAlphaMode.blend,
      );

      expect(
        history.run(
          const SetMaterialField(index: 0, field: 'unlit', value: true),
        ),
        isNull,
      );
      expect(history.project.materials.single.surface.unlit, isTrue);
    });

    test('an unknown field and a wrongly shaped value are both refused', () {
      final history = painted();

      expect(
        history.run(
          const SetMaterialField(index: 0, field: 'roughnesss', value: 1.0),
        ),
        contains('roughnesss'),
      );
      expect(
        history.run(
          const SetMaterialField(
            index: 0,
            field: 'baseColor',
            value: <double>[1.0, 0.0],
          ),
        ),
        isNotNull,
      );
      expect(history.project.materials.single.surface.roughness, 0.5);
    });

    test('an image is interned by its bytes', () {
      final history = ModelHistory(const ModelProject());
      final bytes = Uint8List.fromList(<int>[1, 2, 3]);

      expect(history.run(AddImage(bytes: bytes, imageName: 'a')), isNull);
      expect(history.project.images, hasLength(1));

      // The same bytes again, under a different name: the row does not grow.
      // Mutation: compare by identity rather than by content, or skip the
      // scan, and two imports of the same PNG upload it twice.
      expect(
        history.run(AddImage(bytes: Uint8List.fromList(<int>[1, 2, 3]))),
        isNull,
      );
      expect(history.project.images, hasLength(1));

      expect(
        history.run(AddImage(bytes: Uint8List.fromList(<int>[9]))),
        isNull,
      );
      expect(history.project.images, hasLength(2));
    });

    test('a texture slot takes an image and can be cleared again', () {
      final history = painted();
      history.run(AddImage(bytes: Uint8List.fromList(<int>[1, 2, 3])));

      expect(
        history.run(
          const SetTexture(materialIndex: 0, slot: 'albedo', imageIndex: 0),
        ),
        isNull,
      );
      final SurfaceMaterial withTexture =
          history.project.materials.single.surface;
      expect(withTexture.baseColorTexture?.imageIndex, 0);

      expect(
        history.run(const SetTexture(materialIndex: 0, slot: 'albedo')),
        isNull,
      );
      expect(history.project.materials.single.surface.baseColorTexture, isNull);
    });

    test('a texture naming an image or a slot that does not exist is '
        'refused', () {
      final history = painted();

      expect(
        history.run(
          const SetTexture(materialIndex: 0, slot: 'albedo', imageIndex: 0),
        ),
        contains('image 0'),
      );
      expect(
        history.run(const SetTexture(materialIndex: 0, slot: 'shininess')),
        contains('shininess'),
      );
    });

    test('assigning paints, and null takes the paint off', () {
      final history = painted();
      final int unpainted = history.project.objects.last.id;

      expect(history.run(AssignMaterial(id: unpainted, to: 0)), isNull);
      expect(history.project[unpainted]!.materialSlots, <int>[0]);

      expect(history.run(AssignMaterial(id: unpainted, to: null)), isNull);
      expect(history.project[unpainted]!.materialSlots, isEmpty);
    });

    test('assigning an object or a material that is not there is refused', () {
      final history = painted();

      expect(
        history.run(const AssignMaterial(id: 99, to: 0)),
        contains('object 99'),
      );
      expect(
        history.run(
          AssignMaterial(id: history.project.objects.first.id, to: 9),
        ),
        contains('material 9'),
      );
    });

    test('two objects sharing a row export as one material', () {
      final history = painted();
      history.run(AssignMaterial(id: history.project.objects.last.id, to: 0));

      final document = toModelDocument(history.project);
      expect(document.materials, hasLength(1));
      expect(
        document.surfaces.map((ModelSurface s) => s.materialIndex),
        everyElement(0),
      );
    });
  });

  group('the origin and the transform', () {
    /// One cube, moved and stretched, with a small cube parented to it.
    ModelHistory family({Matrix4? node}) {
      var project = const ModelProject().added(
        (int id) => ModelObject(
          id: id,
          name: 'car',
          geometry: EditedGeometry(EditMesh.cuboid()),
          transform:
              node ??
              Matrix4.compose(
                Vector3(2, 0, 0),
                Quaternion.identity(),
                Vector3(2, 2, 2),
              ),
        ),
      );
      project = project.added(
        (int id) => ModelObject(
          id: id,
          name: 'wheel',
          geometry: EditedGeometry(EditMesh.cuboid()),
          transform: Matrix4.translation(Vector3(0.5, -0.5, 0)),
          parent: 1,
        ),
      );
      return ModelHistory(project);
    }

    /// Where the object's vertex [vertex] is in the world.
    Vector3 worldOf(ModelProject project, int id, int vertex) {
      final object = project[id]!;
      final EditMesh mesh = (object.geometry as EditedGeometry).mesh;
      final Vector3 local = mesh.positionOf(vertex);
      final Matrix4 up = object.parent == null
          ? object.transform
          : (project[object.parent!]!.transform.clone()
              ..multiply(object.transform));
      return up.transform3(local);
    }

    test('applying the transform leaves the model where it looked', () {
      final history = family();
      final Vector3 was = worldOf(history.project, 1, 0);

      expect(history.run(const ApplyTransform(1)), isNull);

      // Mutation: set the transform to the identity without moving the
      // vertices. The object collapses to a unit cube at the origin — which is
      // what "apply the transform" looks like when only half of it happened.
      expect(history.project[1]!.transform, Matrix4.identity());
      expect(worldOf(history.project, 1, 0), was);
    });

    test('the children stay where they were', () {
      final history = family();
      final Vector3 was = worldOf(history.project, 2, 0);

      history.run(const ApplyTransform(1));

      // A child's transform is local to its parent. Mutation: leave the
      // children alone and every wheel of the car shrinks to half size and
      // moves to the middle of it, because the scale it was standing in has
      // just been taken out from under it.
      expect(worldOf(history.project, 2, 0).x, closeTo(was.x, 1e-6));
      expect(worldOf(history.project, 2, 0).y, closeTo(was.y, 1e-6));
    });

    test('a mirrored transform does not leave the surface inside out', () {
      final history = family(node: Matrix4.diagonal3Values(-1, 1, 1));
      final EditMesh mesh = meshOf(history);
      expect(windingVolume(mesh), greaterThan(0));

      history.run(const ApplyTransform(1));

      // Mutation: skip the flip. The model looks right for as long as the
      // viewport is still applying the transform and is inside out the moment
      // anything reads the vertices on their own — which is the export.
      expect(windingVolume(mesh), greaterThan(0));
    });

    test('an identity transform is refused rather than recorded', () {
      final history = family(node: Matrix4.identity());

      expect(
        history.run(const ApplyTransform(1)),
        contains("already stands in the world's own axes"),
      );
      expect(history.canUndo, isFalse);
    });

    test('setting the origin to the bottom moves nothing visible', () {
      final history = family(node: Matrix4.identity());
      final Vector3 was = worldOf(history.project, 1, 0);

      expect(
        history.run(const SetOrigin(id: 1, to: OriginPlacement.boundsBottom)),
        isNull,
      );

      // The whole operation: the geometry goes one way and the node goes the
      // other. Mutation: move the vertices and leave the node alone, and
      // setting the origin becomes a move — the model drops by half its height
      // the moment somebody asks for a pivot to spin it about.
      expect(worldOf(history.project, 1, 0).y, closeTo(was.y, 1e-6));
      expect(
        history.project[1]!.transform.getTranslation().y,
        closeTo(-0.5, 1e-6),
      );
    });

    test('the origin that is already there is refused', () {
      final history = family(node: Matrix4.identity());

      expect(history.run(const SetOrigin(id: 1)), contains('already there'));
    });

    test('undo puts the geometry and the node back together', () {
      final history = family(node: Matrix4.identity());
      final EditMesh mesh = meshOf(history);
      final Vector3 was = mesh.positionOf(0);

      history.run(const SetOrigin(id: 1, to: OriginPlacement.boundsBottom));
      expect(history.undo(), isTrue);

      // Mutation: leave `meshTouched` off. The node comes back and the
      // vertices do not, so the model sits half its height below where every
      // step of the history says it is.
      expect(mesh.positionOf(0), was);
      expect(history.project[1]!.transform, Matrix4.identity());
    });

    test('a shape that still knows its parameters is refused by name', () {
      final history = ModelHistory(const ModelProject())
        ..run(const AddPrimitive(kind: 'cylinder'));

      final String? said = history.run(const SetOrigin(id: 1));

      expect(said, contains('still a cylinder'));
      expect(said, contains('Convert it to a mesh'));
    });
  });

  group('separating', () {
    test('the faces leave one object and arrive as another', () {
      final history = edited();
      history.selection = faces(history, <int>[0]);
      final EditMesh mesh = meshOf(history);

      expect(history.run(const Separate()), isNull);

      expect(history.project.objects.length, 2);
      expect(mesh.faceCount, 5);
      final part = history.project.objects.last;
      expect((part.geometry as EditedGeometry).mesh.faceCount, 1);
    });

    test('undo puts the document and the mesh back together', () {
      final history = edited();
      history.selection = faces(history, <int>[0]);
      final EditMesh mesh = meshOf(history);

      history.run(const Separate());
      expect(history.undo(), isTrue);

      // Mutation: leave `meshTouched` off the outcome. The object comes back in
      // the document and the face does not come back in the mesh, so the model
      // has one object drawing five faces of a box and no step of the history
      // that says where the sixth went.
      expect(history.project.objects.length, 1);
      expect(mesh.faceCount, 6);

      expect(history.redo(), isTrue);
      expect(history.project.objects.length, 2);
      expect(mesh.faceCount, 5);
    });

    test('the piece stands where the object stood', () {
      final project = const ModelProject().added(
        (int id) => ModelObject(
          id: id,
          name: 'crate',
          geometry: EditedGeometry(EditMesh.cuboid()),
          transform: Matrix4.translation(Vector3(3, 1, -2)),
        ),
      );
      final history = ModelHistory(project)
        ..selection = const ProjectSelection(
          mode: SelectionMode.mesh,
          objects: <int>[1],
          level: ElementLevel.face,
          elements: <int>[0],
        );

      history.run(const Separate());

      // Mutation: give the piece the identity transform. Separating a wall of a
      // building three metres out sends that wall to the origin, which reads as
      // the operation having deleted it.
      final part = history.project.objects.last;
      expect(part.transform.getTranslation(), Vector3(3, 1, -2));
      expect(part.name, 'crate part');
    });

    test('the piece is what is held afterwards, as a whole object', () {
      final history = edited();
      history.selection = faces(history, <int>[0]);

      history.run(const Separate());

      // The element numbers the person had were numbers in a mesh that has
      // just been renumbered. Mutation: keep the mesh-level selection and the
      // next command edits whatever face happens to wear those numbers now.
      expect(history.selection.mode, SelectionMode.object);
      expect(history.selection.objects, <int>[2]);
      expect(history.selection.elements, isEmpty);
    });

    test('a whole object is refused rather than emptied', () {
      final history = edited();
      history.selection = faces(history, <int>[0, 1, 2, 3, 4, 5]);

      final String? said = history.run(const Separate());

      // Blender leaves the husk behind. A husk with no faces is what
      // `ExportReadiness` calls an error, so the answer is a sentence rather
      // than a broken document. Mutation: allow it, and a person who pressed
      // ⌘A then P has an invisible object that stops the export.
      expect(said, contains('"cube"'));
      expect(history.project.objects.length, 1);
      expect(history.canUndo, isFalse);
    });

    test('nothing selected is refused', () {
      final history = edited();
      history.selection = faces(history, const <int>[]);

      expect(history.run(const Separate()), 'nothing is selected to separate');
    });

    test('a vertex selection that covers no whole face is refused', () {
      final history = edited();
      history.selection = history.selection.copyWith(
        level: ElementLevel.vertex,
        elements: <int>[0],
      );

      // A conversion up a level takes the faces whose corners are all in the
      // selection, and one corner is never all of them. Mutation: convert down
      // instead, or take any face that touches the vertex, and one click on a
      // corner separates three faces the person never asked for.
      final String? said = history.run(const Separate());
      expect(said, contains('no whole face is selected'));
    });

    test('the piece keeps the material slots of what it came from', () {
      final mesh = EditMesh.cuboid();
      // Outside the history, because this is the setup and not the thing being
      // measured — a mesh refuses a write with no step open.
      mesh.beginStep();
      mesh.setMaterialSlot(0, 2);
      mesh.endStep();
      final project = const ModelProject().added(
        (int id) => ModelObject(
          id: id,
          name: 'cube',
          geometry: EditedGeometry(mesh),
          transform: Matrix4.identity(),
          materialSlots: <int>[7, 4, 9],
        ),
      );
      final history = ModelHistory(project)
        ..selection = const ProjectSelection(
          mode: SelectionMode.mesh,
          objects: <int>[1],
          level: ElementLevel.face,
          elements: <int>[0],
        );

      history.run(const Separate());

      // `subMesh` copies the per-face attributes across; the object has to
      // carry the slot table itself. Mutation: leave `materialSlots` off the
      // new object and the slot the mesh still names indexes a table that is
      // not there — every separated piece comes out the wrong colour, on a
      // model with a dozen materials.
      final part = history.project.objects.last;
      final EditMesh cut = (part.geometry as EditedGeometry).mesh;
      expect(cut.materialSlotOf(0), 2);
      expect(part.materialSlots, <int>[7, 4, 9]);
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

    test(
      'an empty project says so rather than talking about the selection',
      () {
        final history = ModelHistory(const ModelProject());

        // Mutation: drop the `project.objects.isEmpty` guard from either of
        // these. Both still refuse — `_keep` compares the empty selection with
        // the empty one it built and says "that is what is selected already" —
        // so the step count is right and the sentence is nonsense. A person who
        // has just opened an empty file is told about their selection when the
        // answer is that there is nothing there.
        expect(
          history.run(const SelectAll()),
          contains('nothing in the project to select'),
        );
        expect(
          history.run(const InvertSelection()),
          contains('nothing in the project to invert'),
        );
        expect(history.canUndo, isFalse);
      },
    );

    test('the same objects in a different order is a different selection', () {
      // Picked in this order by hand, so object 1 is the active one — the one
      // a mesh command would act on.
      final history = ModelHistory(cubes(2))
        ..selection = const ProjectSelection(objects: <int>[2, 1]);

      // Mutation: compare the ids as sets — `a.toSet().containsAll(b)` with a
      // length check. "Select all" is then refused as already selected while it
      // in fact moves the active object from 1 to 2, so the next mesh command
      // acts on a different object from the one the interface is pointing at.
      expect(history.run(const SelectAll()), isNull);
      expect(history.selection.objects, <int>[1, 2]);
      expect(history.selection.activeObject, 2);
    });

    test('inverting inside a mesh gives back what was not picked', () {
      final history = edited();
      history.selection = faces(history, <int>[0]);

      expect(history.run(const InvertSelection()), isNull);

      // Mutation: drop the `.difference(target.elements)` and hand back
      // everything. Invert becomes a synonym for select-all, so pressing it
      // twice keeps the whole cube instead of getting the first face back, and
      // the one command that lets a person pick a region by picking its
      // complement stops answering.
      expect(history.selection.elements, <int>[1, 2, 3, 4, 5]);

      expect(history.run(const InvertSelection()), isNull);
      expect(history.selection.elements, <int>[0]);
    });

    test('a mesh with nothing left in it says so rather than selecting '
        'nothing', () {
      final history = edited();
      history.selection = faces(history, <int>[0, 1, 2, 3, 4, 5]);
      expect(history.run(const DeleteElements()), isNull);
      history.selection = faces(history, const <int>[]);

      // Mutation: drop the `everything.isEmpty` guard and return the empty
      // selection as a success. `_keep` then compares it with the empty
      // selection already there and refuses anyway — with "that is what is
      // selected already", which tells a person looking at a mesh they have
      // just emptied nothing at all about why the key did nothing.
      expect(
        history.run(const SelectAll()),
        contains('nothing left in it to select'),
      );
      expect(history.canUndo, isTrue);
      expect(history.undoSays, 'delete');
    });

    test('slots the mesh has stopped using are not handed back', () {
      final history = edited();
      history.selection = history.selection.copyWith(
        level: ElementLevel.vertex,
        elements: <int>[0],
      );
      // Deleting one corner of the cube takes the three faces that used it with
      // it, and leaves the vertex slot and three face slots dead rather than
      // compacting the arrays — which is what a journal needs to be able to put
      // them back.
      expect(history.run(const DeleteElements()), isNull);
      history.selection = history.selection.copyWith(elements: const <int>[]);

      // Mutation: drop the `isVertexAlive` filter from `_everything`. Select-all
      // hands back slot 0 as well, and every later command reads a position out
      // of a slot the mesh has stopped using — the overlay draws a corner that
      // is not there and a transform writes into a dead vertex.
      expect(history.run(const SelectAll()), isNull);
      expect(history.selection.elements, <int>[1, 2, 3, 4, 5, 6, 7]);

      // Mutation: drop the `isFaceAlive` filter. The twin check in `_everyEdge`
      // is caught by 'an edge the mesh no longer has is refused by name', which
      // is what makes this branch look covered when it is not.
      history.selection = faces(history, const <int>[]);
      expect(history.run(const SelectAll()), isNull);
      expect(history.selection.elements, <int>[0, 2, 4]);
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
      // Shrink carries the same guard and was the one of the three nothing
      // reached: with it gone, `shrunk` on an empty selection hands back an
      // empty one and the refusal that comes out says "that is what is selected
      // already" rather than naming what is missing.
      expect(
        history.run(const ShrinkSelection()),
        contains('nothing is selected to shrink'),
      );
    });

    test('an edge picked from the far side is the same edge', () {
      final history = edited();
      history.selection = faces(history, <int>[0]);

      // Half-edges 7 and 9 are the two sides of one edge of the cube, and 7 is
      // the smaller of the pair — so 7 is the number a selection holds and 9 is
      // what a click on the far face has in hand.
      // Mutation: look the number up as it arrives, without `EditMesh.edgeOf`.
      // The `contains` test against the mesh's own edges then rejects 9,
      // because `_everything` only ever holds the canonical half of a pair, and
      // picking an edge from one side of a surface works while picking the same
      // edge from the other side is refused as an edge that does not exist.
      expect(history.run(const SelectEdgeLoop(9)), isNull);
      expect(history.selection.level, ElementLevel.edge);
      expect(history.selection.elements, contains(7));
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

    test('a scale about each object\'s own origin leaves them where they '
        'are', () {
      final history = ModelHistory(cubes(2))
        ..selection = const ProjectSelection(objects: <int>[1, 2]);

      expect(
        history.run(const ScaleBy(2, pivot: TransformPivot.individual)),
        isNull,
      );

      // Mutation: hand `TransformPivot.median` to `_aboutThePivot` and ignore
      // the argument, which was proven to survive a round trip through JSON and
      // never proven to do anything. The two cubes sit at 1 and 3, so the
      // middle is 2 and doubling about it drags them to 0 and 4 — a person who
      // asked for two objects to get bigger watches them move apart as well.
      expect(
        history.project[1]!.transform.getTranslation().x,
        closeTo(1, 1e-6),
      );
      expect(
        history.project[2]!.transform.getTranslation().x,
        closeTo(3, 1e-6),
      );
      // And each of them really is twice the size, so the assertion above is
      // not passing because nothing happened.
      expect(
        history.project[1]!.transform.transform3(Vector3(1, 0, 0)).x -
            history.project[1]!.transform.getTranslation().x,
        closeTo(2, 1e-6),
      );
    });

    test('a selection whose objects have all gone is refused, not applied', () {
      // Straight to `apply` rather than through `ModelHistory.run`, and that is
      // the point of the test rather than a shortcut: the history's `selection`
      // getter puts the selection through `within` first, so an object a
      // previous step deleted is gone before any command sees it. The shape
      // below is the one that arrives from somewhere else — an agent's tool
      // call, a journal entry read back — where the selection was written down
      // against a project that no longer matches it.
      // Mutation: drop the `counted == 0` check. The middle is then divided by
      // nothing, comes out as NaN, the loop finds no object to touch, and the
      // command hands back the project unchanged as a success — so a step that
      // moved nothing goes on the stack and the ⌘Z after it does nothing
      // anybody can see.
      final Outcome scaled = const ScaleBy(
        2,
      ).apply(cubes(1), const ProjectSelection(objects: <int>[7]));
      expect(scaled.ok, isFalse);
      expect(scaled.refused, contains('nothing is selected to scale'));

      final Outcome turned = RotateBy(
        axis: Vector3(0, 1, 0),
        radians: 1,
      ).apply(cubes(1), const ProjectSelection(objects: <int>[7]));
      expect(turned.ok, isFalse);
      expect(turned.refused, contains('nothing is selected to turn'));
    });

    test('a local turn on a stretched object turns it rather than bending '
        'it', () {
      final history = ModelHistory(
        const ModelProject().added(
          (int id) => ModelObject(
            id: id,
            name: 'stretched',
            geometry: EditedGeometry(EditMesh.cuboid()),
            // Twice as long along its own X and nothing else: no rotation
            // in it at all, so the upper three by three is the scale and
            // the decomposed rotation is the identity. That gap is the
            // whole difference between the two ways of reading a basis.
            transform: Matrix4.diagonal3(Vector3(2, 1, 1)),
          ),
        ),
      )..selection = const ProjectSelection(objects: <int>[1]);

      // An eighth of a turn, which is the angle that makes a shear visible: at
      // a quarter the axes land back on the grid and a sheared result is merely
      // the wrong size.
      expect(
        history.run(
          RotateBy(
            axis: Vector3(0, 1, 0),
            radians: math.pi / 4,
            pivot: TransformPivot.individual,
            space: TransformSpace.local,
          ),
        ),
        isNull,
      );

      // Mutation: read the basis straight off the upper three by three —
      // `Matrix4.identity()..setRotation(transform.getRotation())`. The turn is
      // then sandwiched in a matrix that scales unevenly, which is a shear. The
      // object's own X comes back 1.581138803024151 long instead of 2, its own
      // Z the same length instead of 1, and the two of them meet at a dot
      // product of 1.4999999486571873 rather than at a right angle: a stretched
      // box turned by a person arrives leaning.
      final Matrix4 after = history.project[1]!.transform;
      final Vector3 alongX = after.transform3(Vector3(1, 0, 0));
      final Vector3 alongZ = after.transform3(Vector3(0, 0, 1));
      expect(alongX.length, closeTo(2, 1e-6));
      expect(alongZ.length, closeTo(1, 1e-6));
      expect(alongX.dot(alongZ), closeTo(0, 1e-6));
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
        const SetOrigin(id: 1, to: OriginPlacement.boundsBottom),
        const ApplyTransform(1),
        const AddPrimitive(kind: 'cylinder', size: 2, segments: 12),
        AddLathe(
          profile: <Vector2>[Vector2(0.4, 0), Vector2(0.2, 1)],
          segments: 12,
          shapeName: 'glass',
        ),
        const SetParametric(
          id: 1,
          to: ParametricSphere(radius: 0.75, segments: 16),
        ),
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
        const Separate(),
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
        const AddMaterial(materialName: 'brass'),
        const RemoveMaterial(0),
        const DuplicateMaterial(0),
        const SetMaterialField(index: 0, field: 'metallic', value: 1.0),
        SetTexture(
          materialIndex: 0,
          slot: 'albedo',
          imageIndex: 0,
          sampling: const TextureSampling(wrapS: TextureWrap.clampToEdge),
        ),
        AddImage(bytes: Uint8List.fromList(<int>[1, 2, 3]), imageName: 'atlas'),
        const AssignMaterial(id: 1, to: 0),
        AddModifier(
          id: 1,
          modifier: ArrayModifier(count: 2, offset: Vector3(1, 0, 0)),
        ),
        const SetModifierField(id: 1, index: 0, field: 'count', value: 5),
        const ToggleModifier(id: 1, index: 0),
        const ReorderModifier(id: 1, from: 0, to: 1),
        const RemoveModifier(id: 1, index: 0),
        const ApplyModifier(id: 1, index: 0),
        ApplyJobResult(
          objectId: 1,
          baseVersion: 1,
          meshBytes: Uint8List.fromList(<int>[1, 2, 3]),
        ),
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

  group('ParamHint', () {
    /// One of every command this session gave a hint, built so every
    /// argument that ever gets one is actually set — a null `distance` on
    /// `MergeByDistance` would still pass the subset check below for the
    /// wrong reason, by having nothing on either side to compare.
    final hinted = <ModelCommand>[
      MoveBy(Vector3(1, 2, 3)),
      RotateBy(axis: Vector3(0, 1, 0), radians: 0.5),
      const ScaleBy(2),
      const AddPrimitive(kind: 'sphere', size: 2, segments: 16),
      AddLathe(
        profile: <Vector2>[Vector2(0.4, 0), Vector2(0.2, 1)],
        segments: 12,
        shapeName: 'glass',
      ),
      const Extrude(0.25),
      const LoopCut(cuts: 3, factor: 0.25),
      TransformElements(Matrix4.identity()),
      const MergeByDistance(distance: 0.001),
      const RecalculateNormals(flip: true),
    ];

    test('a hint\'s keys are always among the command\'s own arguments', () {
      // Mutation: hint a key the command does not actually write under that
      // name — `AddLathe`'s own display name is `arguments['label']`, not
      // `arguments['shapeName']`, and a hint keyed the second way would slip
      // past every other check here while describing a control for nothing.
      for (final command in hinted) {
        expect(
          command.hints.keys,
          everyElement(isIn(command.arguments.keys)),
          reason:
              '${command.name}: ${command.hints.keys} vs '
              '${command.arguments.keys}',
        );
      }
    });

    test('a command with nothing numeric offers no hints at all', () {
      // The default on `ModelCommand` itself, unless a command overrides it.
      expect(const DeleteObjects().hints, isEmpty);
      expect(const SelectAll().hints, isEmpty);
    });

    test('LoopCut.cuts is a whole number, not a fraction', () {
      // Mutation: hint it as a `DoubleHint`. A slider built from that lets
      // somebody drag to "2.5 loops", which `loopCut` cannot cut.
      expect(const LoopCut().hints['cuts'], isA<IntHint>());
    });

    test('RecalculateNormals.flip is a flag, not a range', () {
      // The plan's own acceptance line names `Extrude.individual` for this —
      // a field that does not exist on `Extrude` today (it takes only
      // `distance`). `flip` is the flag this build actually has.
      expect(const RecalculateNormals().hints['flip'], isA<BoolHint>());
    });

    test('MergeByDistance hints nothing when there is nothing to hint', () {
      // Mutation: hint `distance` unconditionally. The subset test above
      // would not catch this on its own sample, since that one sets
      // `distance` — this is the instance that would.
      expect(const MergeByDistance().hints, isEmpty);
    });
  });

  group('the modifier stack', () {
    test('AddModifier appends, enabled', () {
      final history = edited();
      expect(
        history.run(
          AddModifier(
            id: 1,
            modifier: ArrayModifier(count: 2, offset: Vector3(2, 0, 0)),
          ),
        ),
        isNull,
      );

      final modifiers = history.project[1]!.modifiers;
      expect(modifiers, hasLength(1));
      expect(modifiers.single.enabled, isTrue);
      expect(modifiers.single.modifier, isA<ArrayModifier>());
    });

    test('AddModifier refuses an object that does not exist', () {
      final history = edited();
      expect(
        history.run(
          AddModifier(
            id: 99,
            modifier: ArrayModifier(count: 2, offset: Vector3(1, 0, 0)),
          ),
        ),
        contains('no object 99'),
      );
    });

    test('SetModifierField replaces one field and leaves the rest', () {
      final history = edited();
      history.run(
        AddModifier(
          id: 1,
          modifier: ArrayModifier(count: 2, offset: Vector3(2, 0, 0)),
        ),
      );

      expect(
        history.run(
          SetModifierField(id: 1, index: 0, field: 'count', value: 5),
        ),
        isNull,
      );

      final modifier =
          history.project[1]!.modifiers.single.modifier as ArrayModifier;
      // Mutation: rebuild the modifier from only the changed field,
      // defaulting the rest — `offset` would silently reset to zero the
      // moment anybody touched `count`.
      expect(modifier.count, 5);
      expect(modifier.offset, Vector3(2, 0, 0));
    });

    test('SetModifierField refuses a field the modifier does not have', () {
      final history = edited();
      history.run(
        AddModifier(id: 1, modifier: MirrorModifier(normal: Vector3(1, 0, 0))),
      );

      expect(
        history.run(
          SetModifierField(id: 1, index: 0, field: 'count', value: 5),
        ),
        contains('not a field'),
      );
    });

    test('SetModifierField refuses a value of the wrong shape', () {
      final history = edited();
      history.run(
        AddModifier(
          id: 1,
          modifier: ArrayModifier(count: 2, offset: Vector3(1, 0, 0)),
        ),
      );

      expect(
        history.run(
          SetModifierField(id: 1, index: 0, field: 'count', value: 'five'),
        ),
        contains('wrong shape'),
      );
    });

    test('SetModifierField can clear mergeDistance back to null', () {
      final history = edited();
      history.run(
        AddModifier(
          id: 1,
          modifier: ArrayModifier(
            count: 2,
            offset: Vector3(1, 0, 0),
            mergeDistance: 0.01,
          ),
        ),
      );

      history.run(
        SetModifierField(id: 1, index: 0, field: 'mergeDistance', value: null),
      );

      final modifier =
          history.project[1]!.modifiers.single.modifier as ArrayModifier;
      expect(modifier.mergeDistance, isNull);
    });

    test('ToggleModifier flips enabled, and again flips it back', () {
      final history = edited();
      history.run(
        AddModifier(
          id: 1,
          modifier: ArrayModifier(count: 2, offset: Vector3(1, 0, 0)),
        ),
      );

      history.run(const ToggleModifier(id: 1, index: 0));
      expect(history.project[1]!.modifiers.single.enabled, isFalse);

      history.run(const ToggleModifier(id: 1, index: 0));
      // Mutation: always set `enabled: false` instead of `!slot.enabled` —
      // the second toggle would then leave it off instead of turning it
      // back on.
      expect(history.project[1]!.modifiers.single.enabled, isTrue);
    });

    test('ReorderModifier moves a slot without touching the others', () {
      final history = edited();
      history.run(
        AddModifier(
          id: 1,
          modifier: ArrayModifier(count: 1, offset: Vector3(1, 0, 0)),
        ),
      );
      history.run(
        AddModifier(id: 1, modifier: MirrorModifier(normal: Vector3(1, 0, 0))),
      );
      history.run(
        AddModifier(
          id: 1,
          modifier: ArrayModifier(count: 3, offset: Vector3(3, 0, 0)),
        ),
      );

      expect(history.run(const ReorderModifier(id: 1, from: 2, to: 0)), isNull);

      final modifiers = history.project[1]!.modifiers;
      // Mutation: `insert` at `from` instead of `to`, or forget the
      // `removeAt` first — either leaves the moved slot in the wrong place
      // or duplicates it.
      expect((modifiers[0].modifier as ArrayModifier).count, 3);
      expect(modifiers[1].modifier, isA<ArrayModifier>());
      expect((modifiers[1].modifier as ArrayModifier).count, 1);
      expect(modifiers[2].modifier, isA<MirrorModifier>());
    });

    test('RemoveModifier drops one slot and keeps the others in order', () {
      final history = edited();
      history.run(
        AddModifier(
          id: 1,
          modifier: ArrayModifier(count: 1, offset: Vector3(1, 0, 0)),
        ),
      );
      history.run(
        AddModifier(id: 1, modifier: MirrorModifier(normal: Vector3(1, 0, 0))),
      );

      expect(history.run(const RemoveModifier(id: 1, index: 0)), isNull);

      final modifiers = history.project[1]!.modifiers;
      expect(modifiers, hasLength(1));
      expect(modifiers.single.modifier, isA<MirrorModifier>());
    });

    test(
      'ApplyModifier bakes the modifier into the base mesh and drops it',
      () {
        final history = edited();
        final beforeVertices = meshOf(history).vertexCount;
        history.run(
          AddModifier(
            id: 1,
            modifier: ArrayModifier(count: 2, offset: Vector3(2, 0, 0)),
          ),
        );

        expect(history.run(const ApplyModifier(id: 1, index: 0)), isNull);

        final object = history.project[1]!;
        // Mutation: leave the applied modifier on the stack instead of
        // dropping `0..index` — the same array would then double again on the
        // very next evaluation, past what "apply" means.
        expect(object.modifiers, isEmpty);
        expect(
          (object.geometry as EditedGeometry).mesh.vertexCount,
          beforeVertices * 2,
        );
      },
    );

    test('ApplyModifier bakes in a disabled modifier, matching an export '
        'with it switched on', () {
      final history = edited();
      final beforeVertices = meshOf(history).vertexCount;
      history.run(
        AddModifier(
          id: 1,
          modifier: ArrayModifier(count: 2, offset: Vector3(2, 0, 0)),
        ),
      );
      history.run(const ToggleModifier(id: 1, index: 0));

      history.run(const ApplyModifier(id: 1, index: 0));

      // Mutation: skip a disabled slot when building the stack to apply —
      // "apply" is what export with the modifier turned on would give,
      // which is this row's own acceptance line, read literally.
      expect(
        (history.project[1]!.geometry as EditedGeometry).mesh.vertexCount,
        beforeVertices * 2,
      );
    });

    test('ApplyModifier refuses a modifier that is not there', () {
      final history = edited();
      expect(
        history.run(const ApplyModifier(id: 1, index: 0)),
        contains('no modifier 0'),
      );
    });

    test('SetModifierField dispatches on the concrete modifier kind', () {
      final history = edited();
      history.run(
        AddModifier(id: 1, modifier: const SmoothModifier(iterations: 5)),
      );

      expect(
        history.run(
          SetModifierField(
            id: 1,
            index: 0,
            field: 'preserveVolume',
            value: true,
          ),
        ),
        isNull,
      );

      final modifier =
          history.project[1]!.modifiers.single.modifier as SmoothModifier;
      // Mutation: leave `preserveVolume` at the case's own default `false`
      // instead of forwarding `value` — the acceptance's own "10 iterations,
      // <5% with HC" is exactly the setting this field exists to turn on.
      expect(modifier.preserveVolume, isTrue);
      expect(modifier.iterations, 5);
    });

    test('SetModifierField dispatches SubdivisionModifier too', () {
      final history = edited();
      history.run(
        AddModifier(id: 1, modifier: const SubdivisionModifier(levels: 2)),
      );

      expect(
        history.run(
          SetModifierField(id: 1, index: 0, field: 'levels', value: 4),
        ),
        isNull,
      );

      final modifier =
          history.project[1]!.modifiers.single.modifier as SubdivisionModifier;
      // Mutation: no `SubdivisionModifier` case in `_modifierFieldSet` at
      // all — a non-exhaustive switch `dart analyze` would already have
      // caught, which is exactly the safety net this test confirms is wired
      // rather than merely present.
      expect(modifier.levels, 4);
      expect(modifier.viewLevels, 2);
    });

    test('SetModifierField dispatches BooleanModifier too', () {
      final history = edited();
      history.run(
        AddModifier(
          id: 1,
          modifier: BooleanModifier(
            operation: CsgOperation.union,
            operandId: 2,
            operandTransform: Matrix4.identity(),
          ),
        ),
      );

      expect(
        history.run(
          SetModifierField(
            id: 1,
            index: 0,
            field: 'operation',
            value: 'subtract',
          ),
        ),
        isNull,
      );
      expect(
        history.run(
          SetModifierField(id: 1, index: 0, field: 'operandId', value: 5),
        ),
        isNull,
      );

      final modifier =
          history.project[1]!.modifiers.single.modifier as BooleanModifier;
      // Mutation: no `BooleanModifier` case in `_modifierFieldSet` at all —
      // a non-exhaustive switch `dart analyze` would already have caught,
      // the same safety net every other modifier's own dispatch test
      // confirms is wired rather than merely present.
      expect(modifier.operation, CsgOperation.subtract);
      expect(modifier.operandId, 5);
    });

    // JSON round-tripping is covered once, for every command including
    // these six, by "every name has a sample and round-trips through JSON"
    // in the journal group above — no need for a second copy of that
    // assertion here.
  });

  group('ApplyJobResult', () {
    test('writes the job\'s own mesh in when the version still matches', () {
      final history = edited();
      final before = history.project[1]!;
      final baked = EditMesh.fromBytes(
        (before.geometry as EditedGeometry).mesh.toBytes(),
      );
      baked.beginStep();
      baked.addVertex(Vector3(9, 9, 9));
      baked.endStep();

      expect(
        history.run(
          ApplyJobResult(
            objectId: 1,
            baseVersion: before.version,
            meshBytes: baked.toBytes(),
          ),
        ),
        isNull,
      );

      final after = history.project[1]!;
      // Mutation: keep the object's own mesh instead of writing the job's —
      // a background bake that never reaches the document is
      // indistinguishable from one that silently failed.
      expect(
        (after.geometry as EditedGeometry).mesh.vertexCount,
        (before.geometry as EditedGeometry).mesh.vertexCount + 1,
      );
    });

    test('refuses a result whose baseVersion is stale', () {
      final history = edited();
      final before = history.project[1]!;
      // The object changes after the (imagined) job started.
      history.run(const Rename(id: 1, to: 'renamed'));

      final refusal = history.run(
        ApplyJobResult(
          objectId: 1,
          baseVersion: before.version,
          meshBytes: (before.geometry as EditedGeometry).mesh.toBytes(),
        ),
      );

      // Mutation: compare against the *new* version instead of the one the
      // job actually started from, or skip the check outright — either lets
      // a stale bake silently overwrite an edit that happened while it ran.
      expect(refusal, contains('changed since this job started'));
      expect(history.project[1]!.name, 'renamed');
    });

    test('refuses an object that no longer exists', () {
      final history = edited();
      expect(
        history.run(
          ApplyJobResult(objectId: 99, baseVersion: 1, meshBytes: Uint8List(0)),
        ),
        contains('no object 99'),
      );
    });

    // JSON round-tripping is covered once, for every command including this
    // one, by "every name has a sample and round-trips through JSON" in the
    // journal group above.
  });
}
