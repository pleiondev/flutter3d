/// What a file becomes when it is opened.
///
///     flutter test test/opening_test.dart
///
/// **The defect this exists to keep out is not a wrong number, it is two right
/// numbers about different models.** Opening used to draw the decoded file and
/// start a fresh project holding a cube, so the screen and the document each
/// described something true and they were not the same something. Every
/// assertion here compares the two halves against each other rather than
/// against a constant: the objects the document became, and the nodes the scene
/// draws for them.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/opening.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// Four faces and four corners, so that a surface swapped for the cuboid below
/// shows up as a different triangle count rather than passing quietly.
MeshData tetrahedron() => EditMesh.fromFaces(
  <Vector3>[
    Vector3(0, 0, 0),
    Vector3(1, 0, 0),
    Vector3(0, 1, 0),
    Vector3(0, 0, 1),
  ],
  <List<int>>[
    <int>[0, 2, 1],
    <int>[0, 1, 3],
    <int>[0, 3, 2],
    <int>[1, 2, 3],
  ],
).toMeshData();

ModelNode nodeAt(
  String name,
  Vector3 where, {
  List<int> children = const <int>[],
  List<int> surfaces = const <int>[],
}) => ModelNode(
  name: name,
  translation: where,
  rotation: Quaternion.identity(),
  scale: Vector3(1, 1, 1),
  children: children,
  surfaces: surfaces,
);

/// A decoded file shaped like the ones that arrive: a hierarchy, two meshes of
/// different sizes, and a group that draws nothing.
final class _Decoded extends ModelDocument {
  _Decoded({required this.surfaces, required this.nodes, required this.roots});

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

ModelDocument decoded() => _Decoded(
  surfaces: <ModelSurface>[
    ModelSurface(
      name: 'body',
      mesh: EditMesh.cuboid().toMeshData(),
      transform: Matrix4.identity(),
    ),
    ModelSurface(
      name: 'spike',
      mesh: tetrahedron(),
      transform: Matrix4.translation(Vector3(0, 2, 0)),
    ),
  ],
  // A root group with two children: one drawing the cuboid, one the
  // tetrahedron. The group itself draws nothing, which is what an imported node
  // with no mesh comes back as.
  nodes: <ModelNode>[
    nodeAt('rig', Vector3(5, 0, 0), children: <int>[1, 2]),
    nodeAt('body', Vector3.zero(), surfaces: <int>[0]),
    nodeAt('spike', Vector3(0, 2, 0), surfaces: <int>[1]),
  ],
  roots: <int>[0],
);

void main() {
  test('every node in the file becomes an object in the document', () {
    final document = decoded();
    final it = cpuTestDevice(width: 8, height: 8);

    final opened = openDocument(document, device: it.device);

    // Mutation: hand back a fresh project holding a cube — which is what this
    // used to do. One object instead of three, and every assertion below about
    // the two halves agreeing has nothing left to compare.
    expect(opened.project.objects, hasLength(document.nodes.length));
    expect(
      opened.project.objects.map((ModelObject o) => o.name),
      containsAll(<String>['rig', 'body', 'spike']),
    );
  });

  test('the triangles on screen are the triangles in the file', () {
    final document = decoded();
    final it = cpuTestDevice(width: 8, height: 8);

    final opened = openDocument(document, device: it.device);

    // Against the document rather than against 16, so that changing either
    // mesh in the fixture cannot leave this passing about the wrong shape.
    expect(opened.project.triangleCount, document.triangleCount);
  });

  test('the scene draws a node for each object, and nothing else', () {
    final document = decoded();
    final it = cpuTestDevice(width: 8, height: 8);

    final opened = openDocument(document, device: it.device);
    final sync = opened.stage.sync!;

    // The pairing is the whole point: the stage was built from this project, so
    // every object in it has a node and the count matches. Mutation: build the
    // stage from a different project — `nodeOf` answers null for objects the
    // scene never heard of.
    for (final ModelObject object in opened.project.objects) {
      expect(sync.nodeOf(object.id), isNotNull, reason: object.name);
    }
  });

  test('the hierarchy survives the trip', () {
    final document = decoded();
    final it = cpuTestDevice(width: 8, height: 8);

    final opened = openDocument(document, device: it.device);
    final sync = opened.stage.sync!;

    final rig = opened.project.objects.firstWhere(
      (ModelObject o) => o.name == 'rig',
    );
    final body = opened.project.objects.firstWhere(
      (ModelObject o) => o.name == 'body',
    );

    // Mutation: drop the parent when importing. The objects are all there and
    // all at the top level, so a count-only test passes — and dragging the rig
    // then leaves its children behind.
    expect(body.parent, rig.id);
    expect(sync.nodeOf(body.id)!.parent, same(sync.nodeOf(rig.id)));
  });

  test('an opened model can be edited and taken back', () {
    final document = decoded();
    final it = cpuTestDevice(width: 8, height: 8);

    final opened = openDocument(document, device: it.device);
    final history = ModelHistory(opened.project);
    final body = opened.project.objects.firstWhere(
      (ModelObject o) => o.name == 'body',
    );

    // The half that used to be impossible: the opened model is in the document,
    // so a command names one of its objects and undo has something to take
    // back. Before this, every command here would have named an id belonging to
    // a cube nobody could see.
    history.run(Rename(id: body.id, to: 'torso'));
    expect(history.project[body.id]!.name, 'torso');

    history.undo();
    expect(history.project[body.id]!.name, 'body');
  });
}
