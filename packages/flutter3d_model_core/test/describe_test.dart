/// `ux-19`'s own half in core: elements said in numbers, the two picks built
/// on them, and a listing that carries what the next command will ask for.
///
///     dart test test/describe_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

ModelProject _cube({String name = 'cube'}) => const ModelProject().added(
  (int id) => ModelObject(
    id: id,
    name: name,
    geometry: EditedGeometry(EditMesh.cuboid()),
    transform: Matrix4.identity(),
  ),
);

/// The history, in mesh mode on the one object, at [level].
ModelHistory _editing(ModelProject project, ElementLevel level) {
  final history = ModelHistory(project);
  history.selection = ProjectSelection(
    mode: SelectionMode.mesh,
    objects: <int>[project.objects.single.id],
    level: level,
  );
  return history;
}

void main() {
  group('ux-19: elements said in numbers', () {
    test('a cube has six faces, each a unit square with an outward normal', () {
      final EditMesh mesh = EditMesh.cuboid();
      final List<DescribedElement> faces = describeElements(
        mesh,
        ElementLevel.face,
      );

      expect(faces, hasLength(6));
      for (final DescribedElement face in faces) {
        expect(face.area, closeTo(1.0, 1e-6));
        expect(face.length, isNull);
        expect(face.normal, isNotNull);
        // A cuboid's own faces are axis-aligned unit squares, so a centre is
        // half a unit out along one axis and zero on the other two — which is
        // what makes "which one points up" answerable at all.
        expect(face.at.length, closeTo(0.5, 1e-6));
      }

      // The acceptance this row is about: the top face is findable without a
      // picture.
      final DescribedElement top = faces.firstWhere(
        (DescribedElement it) => it.normal!.y > 0.99,
      );
      expect(top.at.y, closeTo(0.5, 1e-6));
    });

    test('an edge carries its length and the average of its two sides', () {
      final EditMesh mesh = EditMesh.cuboid();
      final List<DescribedElement> edges = describeElements(
        mesh,
        ElementLevel.edge,
      );

      // Twelve, each once: an edge is two half-edges and a sweep that counted
      // both would hand an agent twelve ids that mean twenty-four things.
      expect(edges, hasLength(12));
      expect(edges.map((DescribedElement it) => it.id).toSet(), hasLength(12));
      for (final DescribedElement edge in edges) {
        expect(edge.length, closeTo(1.0, 1e-6));
        expect(edge.area, isNull);
        // Between two faces at right angles, so neither of them and not zero.
        expect(edge.normal!.length, closeTo(1.0, 1e-6));
      }
    });

    test('a vertex has a position and no size', () {
      final List<DescribedElement> vertices = describeElements(
        EditMesh.cuboid(),
        ElementLevel.vertex,
      );
      expect(vertices, hasLength(8));
      expect(vertices.first.area, isNull);
      expect(vertices.first.length, isNull);
      expect(vertices.first.normal, isNotNull);
    });

    test('a dead element is left out rather than described as zeroes', () {
      final EditMesh mesh = EditMesh.cuboid();
      mesh
        ..beginStep()
        ..deleteFace(0);

      expect(describeElements(mesh, ElementLevel.face), hasLength(5));
      // Mutation: describe it anyway. A row of zeroes for a face somebody
      // deleted is a row an agent will select, and selecting it is how a
      // stale id gets as far as an edit.
      expect(describeElements(mesh, ElementLevel.face, ids: <int>[0]), isEmpty);
    });

    test('the cap is a cap, and naming ids ignores it', () {
      final EditMesh mesh = EditMesh.cuboid();
      expect(describeElements(mesh, ElementLevel.face, limit: 2), hasLength(2));
      expect(
        describeElements(mesh, ElementLevel.face, ids: <int>[0, 1, 2, 3, 4, 5]),
        hasLength(6),
      );
    });

    test('bounds are the box round the live vertices', () {
      final Aabb3 box = boundsOfMesh(EditMesh.cuboid())!;
      expect(box.min.y, closeTo(-0.5, 1e-6));
      expect(box.max.y, closeTo(0.5, 1e-6));
      expect(boundsOfMesh(EditMesh.empty()), isNull);
    });
  });

  group('ux-19: selectFacing', () {
    test('picks the face that points up, from face level', () {
      final ModelHistory history = _editing(_cube(), ElementLevel.face);

      expect(
        history.run(SelectFacing(axis: Vector3(0, 1, 0))),
        isNull,
        reason: 'a cube has a top',
      );
      expect(history.selection.elements, hasLength(1));

      final int picked = history.selection.elements.single;
      final EditMesh mesh =
          (history.project.objects.single.geometry as EditedGeometry).mesh;
      expect(mesh.normalOf(picked).y, closeTo(1.0, 1e-6));
    });

    test('and from vertex level, coming back at face level', () {
      final ModelHistory history = _editing(_cube(), ElementLevel.vertex);
      expect(history.run(SelectFacing(axis: Vector3(0, 1, 0))), isNull);

      // Mutation: keep the level that was live. Four face numbers under a
      // vertex level name four different elements, and the next command acts
      // on those.
      expect(history.selection.level, ElementLevel.face);
    });

    test('a wide angle takes in more than a narrow one', () {
      final ModelHistory wide = _editing(_cube(), ElementLevel.face);
      wide.run(SelectFacing(axis: Vector3(0, 1, 0), within: 120));
      final ModelHistory narrow = _editing(_cube(), ElementLevel.face);
      narrow.run(SelectFacing(axis: Vector3(0, 1, 0), within: 10));

      expect(wide.selection.elements.length, 5);
      expect(narrow.selection.elements.length, 1);
    });

    test('refusals say what to do instead', () {
      final history = ModelHistory(_cube());
      history.selection = ProjectSelection(objects: <int>[1]);
      expect(
        history.run(SelectFacing(axis: Vector3(0, 1, 0))),
        contains('mesh mode'),
      );

      final ModelHistory mesh = _editing(_cube(), ElementLevel.face);
      expect(
        mesh.run(SelectFacing(axis: Vector3.zero())),
        contains('no direction'),
      );
      expect(
        mesh.run(SelectFacing(axis: Vector3(0, 1, 0), within: 0)),
        contains('degrees'),
      );
      // A cube's corners point at 1,1,1; no *face* does, and a degree of
      // slack does not reach one.
      expect(
        mesh.run(SelectFacing(axis: Vector3(1, 1, 1), within: 1)),
        contains('points that way'),
      );
    });

    test('it survives the journal', () {
      final ModelCommand? read = modelCommandFromJson(
        SelectFacing(axis: Vector3(0, 1, 0), within: 20).toJson(),
      );
      expect(read, isA<SelectFacing>());
      expect((read! as SelectFacing).within, 20);
      expect((read as SelectFacing).axis.y, 1);
      // A journal line written before `within` existed replays as the
      // default rather than as nothing.
      final SelectFacing old =
          modelCommandFromJson(<String, Object?>{
                'name': 'selectFacing',
                'axis': <double>[0, 1, 0],
              })!
              as SelectFacing;
      expect(old.within, 45.0);
    });
  });

  group('ux-19: selectNear', () {
    test('picks the vertices around a corner and nothing else', () {
      final ModelHistory history = _editing(_cube(), ElementLevel.vertex);

      expect(
        history.run(SelectNear(point: Vector3(0.5, 0.5, 0.5), radius: 0.1)),
        isNull,
      );
      expect(history.selection.elements, hasLength(1));

      // Reaching to the three neighbours a unit away, and not to the far
      // corner at √3.
      final ModelHistory wider = _editing(_cube(), ElementLevel.vertex);
      wider.run(SelectNear(point: Vector3(0.5, 0.5, 0.5), radius: 1.05));
      expect(wider.selection.elements, hasLength(4));
    });

    test('at face level it measures centroids', () {
      final ModelHistory history = _editing(_cube(), ElementLevel.face);
      expect(
        history.run(SelectNear(point: Vector3(0, 0.5, 0), radius: 0.01)),
        isNull,
      );
      expect(history.selection.elements, hasLength(1));
      expect(history.selection.level, ElementLevel.face);
    });

    test('refusals', () {
      final history = ModelHistory(_cube());
      history.selection = ProjectSelection(objects: <int>[1]);
      expect(
        history.run(SelectNear(point: Vector3.zero(), radius: 1)),
        contains('mesh mode'),
      );

      final ModelHistory mesh = _editing(_cube(), ElementLevel.vertex);
      expect(
        mesh.run(SelectNear(point: Vector3.zero(), radius: 0)),
        contains('positive distance'),
      );
      expect(
        mesh.run(SelectNear(point: Vector3(99, 99, 99), radius: 1)),
        contains('within'),
      );
    });

    test('it survives the journal', () {
      final ModelCommand? read = modelCommandFromJson(
        SelectNear(point: Vector3(1, 2, 3), radius: 0.5).toJson(),
      );
      expect(read, isA<SelectNear>());
      expect((read! as SelectNear).radius, 0.5);
      expect((read as SelectNear).point.z, 3);
      expect(
        modelCommandFromJson(<String, Object?>{
          'name': 'selectNear',
          'point': <double>[1, 2, 3],
        }),
        isNull,
        reason: 'a radius is not optional — there is no sensible default',
      );
    });
  });

  group('ux-19: a listing that carries what the next command asks for', () {
    test('an object row has its parent, transform, version and counts', () {
      var project = _cube();
      project = project.added(
        (int id) => ModelObject(
          id: id,
          name: 'child',
          geometry: EditedGeometry(EditMesh.cuboid()),
          transform: Matrix4.translation(Vector3(0, 2, 0)),
          parent: 1,
        ),
      );

      final List<Listed> rows = contentsOf(project);
      expect(rows.map((Listed it) => it.id), <int>[1, 2]);
      expect(rows[0].parent, isNull);
      expect(rows[1].parent, 1);
      expect(rows[1].transform, hasLength(16));
      expect(rows[1].transform![13], 2.0);
      expect(rows[1].version, 1);
      expect(rows[1].about['faces'], 6);
      expect(rows[1].about['vertices'], 8);

      // Mutation: drop the transform. "Where did the thing I just made land"
      // was the question the old three-field row could not answer at all.
      expect(rows[1].toJson()['transform'], isNotNull);
      expect(rows[1].toJson()['parent'], 1);
    });

    test('hidden and locked are on the row, since an export reads them', () {
      final ModelProject project = _cube().withObject(
        _cube().objects.single.copyWith(visible: false, locked: true),
      );
      final Listed row = contentsOf(project).single;
      expect(row.about['hidden'], isTrue);
      expect(row.about['locked'], isTrue);
    });

    test('skeletons and clips are listed rather than always empty', () {
      final ModelProject project = _cube().copyWith(
        skeletons: <ProjectSkeleton>[
          ProjectSkeleton(
            name: 'rig',
            joints: <int>[1],
            inverseBindMatrices: <Matrix4>[Matrix4.identity()],
          ),
        ],
        clips: <ProjectClip>[
          const ProjectClip(name: 'walk', tracks: <ProjectTrack>[]),
        ],
      );

      // Mutation: go on returning `const []` because rigging was "phase 3".
      // It stopped being phase 3 at `anim-03`, and an agent asked to retarget
      // a clip had to be told an index by a person.
      expect(skeletonsOf(project).single.name, 'rig');
      expect(skeletonsOf(project).single.about['joints'], 1);
      expect(clipsOf(project).single.name, 'walk');
      expect(clipsOf(project).single.about['tracks'], 0);
    });

    test('lights, shapes and modifiers are addressed by the index a command '
        'takes', () {
      final ModelProject lit = _cube().copyWith(
        lighting: SceneLighting(
          lights: <ProjectLight>[ProjectLight(intensity: 3.0)],
        ),
      );
      expect(lightsOf(lit).single.kind, 'directional');
      expect(lightsOf(lit).single.about['intensity'], 3.0);

      final ModelProject shaped = _cube().withObject(
        _cube().objects.single.copyWith(
          shapeSet: ShapeSet(
            keys: <ShapeKey>[ShapeKey('wide', Float32List(24))],
            weights: const <double>[0.25],
          ),
          modifiers: <ModifierSlot>[
            const ModifierSlot(
              modifier: SubdivisionModifier(levels: 1),
              inExport: false,
            ),
          ],
        ),
      );
      expect(shapesOf(shaped, 1).single.name, 'wide');
      expect(shapesOf(shaped, 1).single.about['weight'], 0.25);
      expect(modifiersOf(shaped, 1).single.name, 'subdivision');
      expect(modifiersOf(shaped, 1).single.about['inExport'], isFalse);
      // An id nothing holds is an empty list rather than a throw: a listing
      // is something a caller asks about whatever it has.
      expect(shapesOf(shaped, 99), isEmpty);
      expect(modifiersOf(shaped, 99), isEmpty);
    });
  });
}
