/// The seam between the document a person edits and the one every writer takes.
///
///     dart test test/project_document_test.dart
///
/// The round trip at the bottom goes through `F3dWriter` and `F3dDocument` for
/// real rather than through a document built in this file, because the claim
/// being made is about the writer that already exists: a project converted here
/// has to survive being written to bytes and read back by code that has never
/// heard of a project.
library;

import 'dart:typed_data';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_model_core/src/project_document.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A project holding [objects], with ids already handed out.
ModelProject projectOf(List<ModelObject Function(int id)> objects) {
  var project = const ModelProject();
  for (final ModelObject Function(int id) build in objects) {
    project = project.added(build);
  }
  return project;
}

ModelObject Function(int) cube({
  String name = 'cube',
  Matrix4? transform,
  int? parent,
}) =>
    (int id) => ModelObject(
      id: id,
      name: name,
      geometry: EditedGeometry(EditMesh.cuboid()),
      transform: transform ?? Matrix4.identity(),
      parent: parent,
    );

/// Where a surface sits, which is the number a game engine framing a camera
/// reads out of `ModelDocument.computeBounds`.
Vector3 placementOf(ModelSurface surface) => surface.transform.getTranslation();

/// A document assembled by hand, for the shapes only an importer produces: a
/// node drawing several primitives, and a node no root reaches.
final class _Doc extends ModelDocument {
  _Doc({required this.surfaces, required this.nodes, required this.roots});

  @override
  final List<ModelSurface> surfaces;

  @override
  final List<ModelNode> nodes;

  @override
  final List<int> roots;

  @override
  List<SurfaceMaterial> get materials => const <SurfaceMaterial>[];

  @override
  List<EncodedImage> get images => const <EncodedImage>[];

  @override
  List<String> get warnings => const <String>[];
}

void main() {
  group('a project becomes a document', () {
    test('every kind of geometry becomes a surface', () {
      final imported = EditMesh.cuboid().toMeshData();
      final project = projectOf(<ModelObject Function(int)>[
        (int id) => ModelObject(
          id: id,
          name: 'lathe',
          geometry: ParametricGeometry(const ParametricCylinder(segments: 8)),
          transform: Matrix4.identity(),
        ),
        cube(name: 'edited'),
        (int id) => ModelObject(
          id: id,
          name: 'arrived',
          geometry: ImportedGeometry(imported),
          transform: Matrix4.identity(),
        ),
      ]);

      final document = toModelDocument(project);

      // Mutation: have `_meshOf` answer `_nothing` for a parametric shape —
      // the case where the triangles do not exist yet and have to be built —
      // and this is 2 surfaces rather than 3, because a mesh with no vertices
      // is written as an object with nothing in it. The cylinder leaves the
      // file entirely and the modeller finds out on the other machine.
      expect(document.surfaces.length, 3);
      expect(
        <String?>[for (final ModelSurface s in document.surfaces) s.name],
        <String>['lathe', 'edited', 'arrived'],
      );
      // An imported mesh goes out as the very thing that arrived: converting
      // it to a uniform layout would drop or invent attributes.
      expect(identical(document.surfaces[2].mesh, imported), isTrue);
      expect(
        document.triangleCount,
        project.objects.fold(
          0,
          (int sum, ModelObject o) => sum + o.geometry.triangleCount,
        ),
      );
    });

    test('the transform rides on a node, not in the vertices', () {
      final project = projectOf(<ModelObject Function(int)>[
        cube(transform: Matrix4.translation(Vector3(5.0, 0.0, 0.0))),
      ]);

      final document = toModelDocument(project);
      final mesh = document.surfaces.single.mesh;
      final corner = Vector3.zero();
      mesh.positionAt(0, corner);

      // Mutation: write `translation: Vector3.zero()` on the node, which is
      // what an export that baked the placement into the vertices would leave
      // behind, and the node assertions below fail. The vertex assertion is
      // the other half of the same claim and it holds either way, which is the
      // point: baking is not detectable from the vertices alone, only from
      // what the node no longer says.
      expect(document.nodes.single.translation, Vector3(5.0, 0.0, 0.0));
      expect(placementOf(document.surfaces.single), Vector3(5.0, 0.0, 0.0));
      expect(corner.x.abs() <= 0.5, isTrue, reason: 'vertices stay local');
    });

    test('a child sits under every parent above it', () {
      final project = projectOf(<ModelObject Function(int)>[
        cube(name: 'root', transform: Matrix4.rotationY(1.5707963267948966)),
        cube(
          name: 'child',
          transform: Matrix4.translation(Vector3(0.0, 0.0, 1.0)),
          parent: 1,
        ),
        cube(
          name: 'grandchild',
          transform: Matrix4.translation(Vector3(0.0, 2.0, 0.0)),
          parent: 2,
        ),
      ]);

      final document = toModelDocument(project);

      // Mutation: compose the other way round — `objects[child].transform
      // .multiplied(world[parent]!)` — and the child lands at (0, 0, 1)
      // instead of (1, 0, 0): the quarter turn stops being something the
      // parent does to the child and becomes something the child does to
      // itself. Mutation: use the child's own transform as its world matrix,
      // forgetting the parent entirely, and it lands at (0, 0, 1) as well.
      final child = placementOf(document.surfaces[1]);
      expect(child.x, closeTo(1.0, 1e-6));
      expect(child.z, closeTo(0.0, 1e-6));

      final grandchild = placementOf(document.surfaces[2]);
      expect(grandchild.x, closeTo(1.0, 1e-6));
      expect(grandchild.y, closeTo(2.0, 1e-6));

      // The node keeps the local transform, which is what an animation moves.
      expect(document.nodes[2].translation, Vector3(0.0, 2.0, 0.0));
      expect(document.nodes[0].children, <int>[1]);
      expect(document.nodes[1].children, <int>[2]);
      expect(document.roots, <int>[0]);
    });

    test('an object with nothing in it keeps its node', () {
      final project = projectOf(<ModelObject Function(int)>[
        (int id) => ModelObject(
          id: id,
          name: 'arm',
          geometry: EditedGeometry(EditMesh.empty()),
          transform: Matrix4.translation(Vector3(0.0, 3.0, 0.0)),
        ),
        cube(name: 'hand', parent: 1),
      ]);

      final document = toModelDocument(project);

      // Mutation: skip an empty object rather than giving it a node — the
      // tempting cleanup, since it draws nothing — and this is 1 node rather
      // than 2. The hand still *draws* three units up, because its surface
      // carries the composed matrix; what goes is the handle. Node indices
      // stop being object indices, so the root index 0 now names the hand,
      // and an animation of the arm has nothing left to move.
      expect(document.nodes.length, 2);
      expect(document.surfaces.length, 1);
      expect(document.nodes[0].surfaces, isEmpty);
      expect(document.nodes[0].children, <int>[1]);
      expect(document.nodes[1].surfaces, <int>[0]);
      expect(placementOf(document.surfaces.single), Vector3(0.0, 3.0, 0.0));
    });

    test('a mirrored object asks for its winding to be flipped', () {
      final project = projectOf(<ModelObject Function(int)>[
        cube(transform: Matrix4.diagonal3(Vector3(-1.0, 1.0, 1.0))),
        cube(),
      ]);

      final document = toModelDocument(project);

      // Mutation: drop `flipWinding` from the surface and the other glove
      // draws inside out — backface culling keeps exactly the faces that
      // should have been hidden.
      expect(document.surfaces[0].flipWinding, isTrue);
      expect(document.surfaces[1].flipWinding, isFalse);
    });

    test('a transform a node cannot express says so', () {
      final sheared = Matrix4.identity()..setEntry(0, 1, 1.0);
      final project = projectOf(<ModelObject Function(int)>[
        cube(name: 'skewed', transform: sheared),
      ]);

      final document = toModelDocument(project);

      // Mutation: drop the `_matchesComposed` check and the warning list is
      // empty — the file then carries a node that is not the transform the
      // modeller applied and nothing anywhere says which object moved.
      expect(document.warnings.length, 1);
      expect(document.warnings.single, contains('"skewed"'));
      expect(document.warnings.single, contains('not a translate'));
      // The surface still carries the matrix exactly, which is why the
      // warning is a warning rather than a refusal.
      expect(document.surfaces.single.transform.storage[4], 1.0);
    });

    test('an object hanging from nothing is a sentence and a root', () {
      final project = projectOf(<ModelObject Function(int)>[
        cube(name: 'orphan', parent: 404),
      ]);

      final document = toModelDocument(project);

      // Mutation: delete the sweep that follows the walk from the roots and
      // this throws on a null world matrix — a crash where a file was asked
      // for. The earlier temptation, dropping the object, is worse: it is a
      // silent export missing an arm.
      expect(document.roots, <int>[0]);
      expect(document.surfaces.length, 1);
      expect(document.warnings.single, contains('names parent 404'));
    });

    test('a loop is cut rather than walked', () {
      // Two objects each naming the other. `ParentObject` refuses to build
      // this — it walks up from the new parent looking for the object — so it
      // arrives only from a file or from a caller assembling objects by hand,
      // which is exactly what an importer is.
      final project = ModelProject(
        objects: <ModelObject>[
          ModelObject(
            id: 1,
            name: 'a',
            geometry: EditedGeometry(EditMesh.cuboid()),
            transform: Matrix4.identity(),
            parent: 2,
          ),
          ModelObject(
            id: 2,
            name: 'b',
            geometry: EditedGeometry(EditMesh.cuboid()),
            transform: Matrix4.identity(),
            parent: 1,
          ),
        ],
        nextId: 3,
      );

      final document = toModelDocument(project);

      // Mutation: give each node the children the parent table lists rather
      // than the ones the walk reached — `childrenByParent[i] ?? <int>[]` —
      // and node 1's children come back as `[0]`: the root already claims
      // node 1, so the emitted tree has the project's loop still in it and a
      // loader instantiating from the roots follows it round.
      expect(document.nodes.length, 2);
      expect(document.roots, <int>[0]);
      expect(document.nodes[0].children, <int>[1]);
      expect(document.nodes[1].children, isEmpty);
      expect(document.warnings.single, contains('hangs under itself'));
    });
  });

  group('a document becomes a project', () {
    test('a node with no mesh comes back as an object with nothing in it', () {
      final document = _Doc(
        surfaces: <ModelSurface>[
          ModelSurface(name: 'hand', mesh: EditMesh.cuboid().toMeshData()),
        ],
        nodes: <ModelNode>[
          ModelNode(
            name: 'arm',
            translation: Vector3(0.0, 3.0, 0.0),
            children: <int>[1],
          ),
          ModelNode(name: 'hand', surfaces: <int>[0]),
        ],
        roots: <int>[0],
      );

      final project = fromModelDocument(document);

      // Mutation: give the empty node no object at all and the hand arrives
      // with no parent and no three units of height above it.
      expect(project.objects.length, 2);
      expect(project.objects[0].name, 'arm');
      expect(project.objects[0].geometry.triangleCount, 0);
      expect(project.objects[1].parent, project.objects[0].id);
      expect(
        project.objects[0].transform.getTranslation(),
        Vector3(0.0, 3.0, 0.0),
      );
    });

    test('a node drawing several meshes gets the rest as children', () {
      final mesh = EditMesh.cuboid().toMeshData();
      final document = _Doc(
        surfaces: <ModelSurface>[
          ModelSurface(name: 'body', mesh: mesh),
          ModelSurface(name: 'trim', mesh: mesh),
        ],
        nodes: <ModelNode>[
          ModelNode(
            name: 'prop',
            translation: Vector3(1.0, 0.0, 0.0),
            surfaces: <int>[0, 1],
          ),
        ],
        roots: <int>[0],
      );

      final project = fromModelDocument(document);

      // Mutation: keep only the first surface and the second material's worth
      // of the model is silently missing. Mutation: put every surface under a
      // new empty object instead, and the ordinary one-mesh node — every node
      // this file writes — comes back as two objects, so nothing round-trips.
      expect(project.objects.length, 2);
      expect(project.objects[1].name, 'trim');
      expect(project.objects[1].parent, project.objects[0].id);
      // Identity, so it draws where it did: the node above already places it.
      expect(project.objects[1].transform, Matrix4.identity());
    });

    test('a node no root reaches still arrives', () {
      final document = _Doc(
        surfaces: <ModelSurface>[
          ModelSurface(name: 'seen', mesh: EditMesh.cuboid().toMeshData()),
          ModelSurface(name: 'stranded', mesh: EditMesh.cuboid().toMeshData()),
        ],
        nodes: <ModelNode>[
          ModelNode(name: 'seen', surfaces: <int>[0]),
          ModelNode(name: 'stranded', surfaces: <int>[1]),
        ],
        roots: <int>[0],
      );

      final project = fromModelDocument(document);

      // Mutation: delete the sweep over untaken nodes and this is one object —
      // the file's second mesh is dropped on the floor of an importer that
      // says nothing about it.
      expect(project.objects.length, 2);
      expect(project.objects[1].name, 'stranded');
      expect(project.objects[1].parent, isNull);
    });

    test('a child index that points nowhere is skipped', () {
      final document = _Doc(
        surfaces: <ModelSurface>[
          ModelSurface(mesh: EditMesh.cuboid().toMeshData()),
        ],
        nodes: <ModelNode>[
          ModelNode(name: 'root', children: <int>[7], surfaces: <int>[0]),
        ],
        roots: <int>[0],
      );

      // Mutation: index `nodes` without the range check and this is a range
      // error rather than a project. A file is bytes somebody else wrote.
      expect(fromModelDocument(document).objects.length, 1);
    });
  });

  group('out and back', () {
    test('a hierarchy survives being written and read', () {
      final project = projectOf(<ModelObject Function(int)>[
        (int id) => ModelObject(
          id: id,
          name: 'barrel',
          geometry: ParametricGeometry(const ParametricCylinder(segments: 8)),
          transform: Matrix4.translation(Vector3(2.0, 0.0, 0.0)),
        ),
        cube(
          name: 'lid',
          transform: Matrix4.translation(Vector3(0.0, 1.0, 0.0)),
          parent: 1,
        ),
      ]);

      final Uint8List bytes = F3dWriter(toModelDocument(project)).write();
      final reopened = fromModelDocument(F3dDocument.parse(bytes));

      // Mutation: hand `F3dWriter` a document whose nodes are the flat default
      // — drop the `nodes` override from `_ProjectDocument` — and the lid comes
      // back at (2, 1, 0) with no parent, because the default derives a node
      // per surface from the world matrix and the hierarchy is gone. That is
      // the shape of the bug this seam exists to prevent.
      expect(reopened.objects.length, 2);
      expect(reopened.objects[0].name, 'barrel');
      expect(reopened.objects[1].name, 'lid');
      expect(
        reopened.objects[0].transform.getTranslation(),
        Vector3(2.0, 0.0, 0.0),
      );
      expect(
        reopened.objects[1].transform.getTranslation(),
        Vector3(0.0, 1.0, 0.0),
      );
      expect(reopened.objects[1].parent, reopened.objects[0].id);
    });

    test('a cylinder comes back an imported mesh, and that is the answer', () {
      final project = projectOf(<ModelObject Function(int)>[
        (int id) => ModelObject(
          id: id,
          name: 'barrel',
          geometry: ParametricGeometry(const ParametricCylinder(segments: 8)),
          transform: Matrix4.identity(),
        ),
      ]);

      final before = project.objects.single.geometry;
      final Uint8List bytes = F3dWriter(toModelDocument(project)).write();
      final after = fromModelDocument(F3dDocument.parse(bytes)).objects.single;

      // Not a loss, and not a mutation either: nothing on the way out records
      // that these triangles came from a cylinder of eight segments, so
      // nothing on the way back could honestly claim it. An importer that
      // guessed "this looks like a cylinder" would hand the modeller a
      // segments field which, when changed, would silently discard whatever
      // had been done to the mesh since. The triangles are what the file
      // holds, and `ImportedGeometry` is the honest name for them.
      expect(before, isA<ParametricGeometry>());
      expect(after.geometry, isA<ImportedGeometry>());
      expect(after.geometry.triangleCount, before.triangleCount);
      expect(after.name, 'barrel');
    });
  });
}
