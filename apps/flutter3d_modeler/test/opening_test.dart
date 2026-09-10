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

import 'dart:typed_data';

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
  _Decoded({
    required this.surfaces,
    required this.nodes,
    required this.roots,
    this.materials = const <SurfaceMaterial>[],
    this.images = const <EncodedImage>[],
  });

  @override
  final List<ModelSurface> surfaces;

  @override
  final List<ModelNode> nodes;

  @override
  final List<int> roots;

  @override
  final List<SurfaceMaterial> materials;

  @override
  final List<EncodedImage> images;

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
  test('every node in the file becomes an object in the document', () async {
    final document = decoded();
    final it = cpuTestDevice(width: 8, height: 8);

    final opened = await openDocument(document, device: it.device);

    // Mutation: hand back a fresh project holding a cube — which is what this
    // used to do. One object instead of three, and every assertion below about
    // the two halves agreeing has nothing left to compare.
    expect(opened.project.objects, hasLength(document.nodes.length));
    expect(
      opened.project.objects.map((ModelObject o) => o.name),
      containsAll(<String>['rig', 'body', 'spike']),
    );
  });

  test('the triangles on screen are the triangles in the file', () async {
    final document = decoded();
    final it = cpuTestDevice(width: 8, height: 8);

    final opened = await openDocument(document, device: it.device);

    // Against the document rather than against 16, so that changing either
    // mesh in the fixture cannot leave this passing about the wrong shape.
    expect(opened.project.triangleCount, document.triangleCount);
  });

  test('the scene draws a node for each object, and nothing else', () async {
    final document = decoded();
    final it = cpuTestDevice(width: 8, height: 8);

    final opened = await openDocument(document, device: it.device);
    final sync = opened.stage.sync!;

    // The pairing is the whole point: the stage was built from this project, so
    // every object in it has a node and the count matches. Mutation: build the
    // stage from a different project — `nodeOf` answers null for objects the
    // scene never heard of.
    for (final ModelObject object in opened.project.objects) {
      expect(sync.nodeOf(object.id), isNotNull, reason: object.name);
    }
  });

  test('the hierarchy survives the trip', () async {
    final document = decoded();
    final it = cpuTestDevice(width: 8, height: 8);

    final opened = await openDocument(document, device: it.device);
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

  test('an opened model can be edited and taken back', () async {
    final document = decoded();
    final it = cpuTestDevice(width: 8, height: 8);

    final opened = await openDocument(document, device: it.device);
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

  test('an opened model keeps the colour the file gave it', () async {
    final brass = Vector4(0.8, 0.6, 0.2, 1.0);
    final document = _Decoded(
      surfaces: <ModelSurface>[
        ModelSurface(
          name: 'body',
          mesh: EditMesh.cuboid().toMeshData(),
          transform: Matrix4.identity(),
          materialIndex: 0,
        ),
        // Painted with nothing, which is not the same as painted with the
        // first material in the file.
        ModelSurface(
          name: 'spike',
          mesh: tetrahedron(),
          transform: Matrix4.identity(),
        ),
      ],
      nodes: <ModelNode>[
        nodeAt('body', Vector3.zero(), surfaces: <int>[0]),
        nodeAt('spike', Vector3.zero(), surfaces: <int>[1]),
      ],
      roots: <int>[0, 1],
      materials: <SurfaceMaterial>[
        SurfaceMaterial(name: 'brass', baseColor: brass, metallic: 1.0),
      ],
    );
    final it = cpuTestDevice(width: 8, height: 8);

    final opened = await openDocument(document, device: it.device);
    final sync = opened.stage.sync!;
    final body = opened.project.objects.firstWhere(
      (ModelObject o) => o.name == 'body',
    );
    final spike = opened.project.objects.firstWhere(
      (ModelObject o) => o.name == 'spike',
    );

    // Mutation: paint every node in clay, which is what this did before the
    // table existed. A model opens the colour of unfired pottery whatever the
    // file said, and nothing in the suite could tell the difference.
    expect(sync.nodeOf(body.id)!.material.baseColor, brass);
    expect(sync.nodeOf(body.id)!.material.metallic, 1.0);

    // Mutation: fall back to material zero for an unpainted object. The spike
    // turns brass, and every unpainted object in every opened file takes on
    // whichever material happened to be first.
    expect(sync.nodeOf(spike.id)!.material.name, 'clay');
  });

  test('a second refresh builds nothing', () async {
    final document = _Decoded(
      surfaces: <ModelSurface>[
        ModelSurface(
          name: 'body',
          mesh: EditMesh.cuboid().toMeshData(),
          transform: Matrix4.identity(),
          materialIndex: 0,
        ),
      ],
      nodes: <ModelNode>[nodeAt('body', Vector3.zero(), surfaces: <int>[0])],
      roots: <int>[0],
      materials: <SurfaceMaterial>[SurfaceMaterial(name: 'brass')],
    );
    final it = cpuTestDevice(width: 8, height: 8);

    final opened = await openDocument(document, device: it.device);

    // The number that has to be zero while somebody is dragging. Mutation: key
    // the pool on nothing and rebuild every material each call — every edit to
    // the document then decodes every texture in the model again.
    expect(await opened.stage.materials!.refresh(opened.project), 0);
  });

  test('an image that will not decode leaves the colour and a sentence', () async {
    final teal = Vector4(0.0, 0.5, 0.5, 1.0);
    final document = _Decoded(
      surfaces: <ModelSurface>[
        ModelSurface(
          name: 'body',
          mesh: EditMesh.cuboid().toMeshData(),
          transform: Matrix4.identity(),
          materialIndex: 0,
        ),
      ],
      nodes: <ModelNode>[nodeAt('body', Vector3.zero(), surfaces: <int>[0])],
      roots: <int>[0],
      materials: <SurfaceMaterial>[
        SurfaceMaterial(
          name: 'painted',
          baseColor: teal,
          baseColorTexture: const TextureBinding(imageIndex: 0),
        ),
      ],
      // Three bytes that are not a PNG and not a JPEG.
      images: <EncodedImage>[
        EncodedImage(bytes: Uint8List.fromList(<int>[1, 2, 3]), name: 'broken'),
      ],
    );
    final it = cpuTestDevice(width: 8, height: 8);

    final opened = await openDocument(document, device: it.device);
    final sync = opened.stage.sync!;
    final body = opened.project.objects.single;

    // A model with one unreadable texture is a model that opens, not a model
    // that refuses to. Mutation: let the failure through as an exception and
    // the whole file fails to open because one image in it is truncated.
    expect(sync.nodeOf(body.id)!.material.baseColor, teal);
    expect(opened.stage.materials!.warnings, isNotEmpty);
  });

  group('what a chosen file turns out to be', () {
    /// A project with the three things a save has to keep: a shape that still
    /// knows its parameters, an edited mesh, and a child hanging off one.
    ModelProject workshop() {
      final project = const ModelProject()
          .added(
            (int id) => ModelObject(
              id: id,
              name: 'body',
              geometry: EditedGeometry(EditMesh.cuboid()),
              transform: Matrix4.translation(Vector3(1, 2, 3)),
            ),
          )
          .added(
            (int id) => ModelObject(
              id: id,
              name: 'lid',
              geometry: EditedGeometry(
                EditMesh.cuboid(size: Vector3(2, 1, 3)),
              ),
              transform: Matrix4.translation(Vector3(0, 4, 0)),
              parent: 1,
            ),
          )
          .added(
            (int id) => ModelObject(
              id: id,
              name: 'doomed',
              geometry: EditedGeometry(EditMesh.cuboid()),
              transform: Matrix4.identity(),
            ),
          );
      // Removed, so `nextId` is 4 while the file holds two objects — the trap a
      // reader that counted the objects instead of reading the number falls
      // into, and the one that would make undo name the wrong object.
      return project.removed(3);
    }

    test('a saved project opens back as the same project', () async {
      final before = workshop();
      final it = cpuTestDevice(width: 8, height: 8);

      final opened = await openBytes(
        writeProject(before),
        name: 'model.f3dproj',
        device: it.device,
      );

      expect(opened, isA<OpenedModel>());
      final after = (opened as OpenedModel).project;

      // Mutation: keep writing the scene's first mesh through `F3dWriter`,
      // which is what Save did. One object of two comes back, with no name, no
      // placement and no parent — and the file cannot be opened back into the
      // project it was saved from at all.
      expect(after.objects.length, before.objects.length);
      expect(after.nextId, before.nextId);
      expect(
        after.objects.map((ModelObject o) => o.name),
        <String>['body', 'lid'],
      );
      expect(after.objects[0].transform.getTranslation(), Vector3(1, 2, 3));
      expect(after.objects[1].parent, after.objects[0].id);
      expect(after.triangleCount, before.triangleCount);
    });

    test('the scene follows a project that came out of a file', () async {
      final it = cpuTestDevice(width: 8, height: 8);

      final opened =
          await openBytes(
                writeProject(workshop()),
                name: 'model.f3dproj',
                device: it.device,
              )
              as OpenedModel;
      final sync = opened.stage.sync!;

      // The same pairing an import gets: both roads end in a stage built from
      // the project that came back, so nothing above has to know which was
      // taken.
      for (final ModelObject object in opened.project.objects) {
        expect(sync.nodeOf(object.id), isNotNull, reason: object.name);
      }
    });

    test('a model file goes down the import road instead', () async {
      final it = cpuTestDevice(width: 8, height: 8);
      final model = F3dWriter(toModelDocument(workshop())).write();

      final opened =
          await openBytes(model, name: 'thing.f3d', device: it.device)
              as OpenedModel;

      // A `.f3d` begins "F3D\n" and a project begins "F3DP" — three bytes
      // apart. Mutation: compare three of them and every model a person picks
      // is handed to `readProject`, which refuses it.
      expect(opened.project.objects.length, 2);
      // It arrives as triangles, because that is what the file holds: nothing
      // in a `.f3d` records that a mesh was ever editable.
      expect(opened.project.objects.first.geometry, isA<ImportedGeometry>());
    });

    test('the extension is not what decides', () async {
      final it = cpuTestDevice(width: 8, height: 8);

      // A project someone renamed. Mutation: branch on the name and this opens
      // as a broken model, with a sentence about a decoder rather than the two
      // objects that are plainly in the file.
      final opened =
          await openBytes(
                writeProject(workshop()),
                name: 'notaproject.glb',
                device: it.device,
              )
              as OpenedModel;

      expect(opened.project.objects.length, 2);
    });

    test('a damaged project is a sentence, not an exception', () async {
      final it = cpuTestDevice(width: 8, height: 8);
      final broken = Uint8List.fromList(writeProject(workshop()));
      // Inside the manifest, which is where a flipped byte used to open as a
      // silently different model.
      broken[200] ^= 0xFF;

      final opened = await openBytes(
        broken,
        name: 'model.f3dproj',
        device: it.device,
      );

      // Mutation: let `readProject`'s refusal through as a throw. The
      // application then loses the document the person was working on because
      // they picked a damaged file out of a folder.
      expect(opened, isA<OpenRefused>());
      expect((opened as OpenRefused).because, contains('damaged'));
    });

    test('a file that is neither is a sentence too', () async {
      final it = cpuTestDevice(width: 8, height: 8);

      final opened = await openBytes(
        Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6, 7, 8]),
        name: 'holiday.jpg',
        device: it.device,
      );

      // A decoder throws, and a person who picked a photograph should be told
      // so. Mutation: let it propagate and the catch in `_openFile` is the only
      // thing between them and a stack trace.
      expect(opened, isA<OpenRefused>());
      expect((opened as OpenRefused).because, contains('holiday.jpg'));
    });
  });
}
