/// `SubdivideMesh` — `pro-sc-08`'s own Subdivide button, as a command.
///
///     dart test test/subdivide_mesh_test.dart
///
/// `subdivide_test.dart` (`flutter3d_mesh`) covers what Catmull-Clark does to
/// a mesh. This file covers what only exists once it is a command: the undo,
/// the refusals on a mesh carrying something a subdivision would drop, and
/// the selection that has to go because its ids named the old mesh.
library;

import 'dart:typed_data';

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

({ModelHistory history, EditMesh mesh}) opened({
  bool skinned = false,
  bool withShapes = false,
}) {
  final EditMesh mesh = EditMesh.cuboid(size: Vector3(2, 2, 2));
  final ModelProject project = ModelProject(
    objects: <ModelObject>[
      ModelObject(
        id: 1,
        name: 'cube',
        geometry: EditedGeometry(mesh),
        transform: Matrix4.identity(),
        skeletonIndex: skinned ? 0 : null,
        shapeSet: withShapes
            ? ShapeSet(
                keys: <ShapeKey>[
                  ShapeKey('wide', Float32List(mesh.vertexSlotCount * 3)),
                ],
              )
            : const ShapeSet(),
      ),
    ],
    skeletons: skinned
        ? <ProjectSkeleton>[
            ProjectSkeleton(
              joints: <int>[1],
              inverseBindMatrices: <Matrix4>[Matrix4.identity()],
            ),
          ]
        : const <ProjectSkeleton>[],
    nextId: 2,
  );
  return (
    history: ModelHistory(project)
      ..selection = const ProjectSelection(objects: <int>[1]),
    mesh: mesh,
  );
}

EditMesh meshOf(ModelHistory history) =>
    (history.project[1]!.geometry as EditedGeometry).mesh;

void main() {
  group('one level', () {
    test('is four quads per face, and the old mesh is untouched', () {
      final (:history, :mesh) = opened();
      expect(history.run(const SubdivideMesh()), isNull);

      final EditMesh next = meshOf(history);
      expect(next.faceCount, 24);
      expect(next.vertexCount, 26);
      // **The old mesh is what undo puts back, so nothing may have been
      // written into it.** Mutation: subdivide in place. The kept document
      // then names a mesh that has already changed, and ⌘Z restores a
      // project whose geometry is the *new* shape under the old count.
      expect(identical(next, mesh), isFalse);
      expect(mesh.faceCount, 6);
    });

    test('and undo is the mesh that was there', () {
      final (:history, :mesh) = opened();
      expect(history.run(const SubdivideMesh()), isNull);
      expect(history.undo(), isTrue);
      expect(identical(meshOf(history), mesh), isTrue);
      expect(meshOf(history).faceCount, 6);
    });

    test('unsmoothed leaves every vertex where it was', () {
      final (:history, :mesh) = opened();
      final Vector3 corner = mesh.positionOf(0).clone();
      expect(history.run(const SubdivideMesh(smooth: false)), isNull);

      // A linear subdivision adds topology and moves nothing — which is the
      // whole reason it is offered beside the smooth one: a bevelled panel
      // is already the shape it is meant to be.
      final EditMesh next = meshOf(history);
      var found = false;
      final at = Vector3.zero();
      for (var v = 0; v < next.vertexSlotCount; v++) {
        if (!next.isVertexAlive(v)) continue;
        next.positionOf(v, at);
        if (at.distanceTo(corner) < 1e-6) found = true;
      }
      expect(found, isTrue);
    });

    test('drops the element selection, which named the old mesh', () {
      final (:history, :mesh) = opened();
      history.selection = const ProjectSelection(
        objects: <int>[1],
        elements: <int>[0, 1, 2],
        level: ElementLevel.face,
      );
      expect(history.run(const SubdivideMesh()), isNull);
      // Face 2 of a subdivided cube is not the face 2 that was picked, and
      // keeping the number would be worse than keeping nothing: the next
      // operation would run somewhere nobody chose.
      expect(history.selection.elements, isEmpty);
    });
  });

  group('refusals', () {
    test('a level count outside one to four', () {
      final (:history, :mesh) = opened();
      expect(history.run(const SubdivideMesh(levels: 0)), contains('not 0'));
      expect(history.run(const SubdivideMesh(levels: 9)), contains('not 9'));
      expect(history.canUndo, isFalse);
    });

    test('a mesh with shape keys, naming them', () {
      final (:history, :mesh) = opened(withShapes: true);
      expect(history.run(const SubdivideMesh()), contains('shape keys'));
    });

    test('a mesh bound to a skeleton, naming the weights', () {
      final (:history, :mesh) = opened(skinned: true);
      expect(history.run(const SubdivideMesh()), contains('skin weights'));
    });

    test('and an object with nothing selected', () {
      final (:history, :mesh) = opened();
      history.selection = ProjectSelection.none;
      expect(history.run(const SubdivideMesh()), isNotNull);
    });
  });

  group('four levels', () {
    test('is two hundred and fifty-six quads per face', () {
      final (:history, :mesh) = opened();
      expect(history.run(const SubdivideMesh(levels: 4)), isNull);
      expect(meshOf(history).faceCount, 6 * 256);
    });
  });
}
