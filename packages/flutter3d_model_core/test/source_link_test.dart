/// `ux-48`: an object linked to the file its geometry came from, and read
/// again without losing the work done around it.
///
///     flutter test test/source_link_test.dart
///
/// **The row is stated as what a re-import does not touch.** Replacing a mesh
/// is easy; keeping the transform, the materials and the modifier stack while
/// doing it is the whole feature, because that is the work nobody wants to do
/// twice when a file moves.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart' show SurfaceMaterial;
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A crate at x = 3, painted, mirrored, and imported from a file.
ModelProject _crate({bool linked = true}) {
  final ModelProject project = const ModelProject()
      .copyWith(
        materials: <ProjectMaterial>[
          ProjectMaterial(surface: SurfaceMaterial(name: 'oak')),
        ],
      )
      .added(
        (int id) => ModelObject(
          id: id,
          name: 'crate',
          geometry: EditedGeometry(EditMesh.cuboid()),
          transform: Matrix4.translationValues(3, 0, 0),
          materialSlots: const <int>[0],
          modifiers: <ModifierSlot>[
            ModifierSlot(modifier: MirrorModifier(normal: Vector3(1, 0, 0))),
          ],
        ),
      );
  if (!linked) return project;
  final ModelHistory history = ModelHistory(project);
  expect(
    history.run(
      const LinkToSource(id: 1, path: 'props/crate.obj', sha: 'before'),
    ),
    isNull,
  );
  return history.project;
}

/// An `EditMesh` that is not the cuboid, so a replacement is visible as a
/// change in the vertex count rather than only in the bytes.
EditMesh _plane() => EditMesh.fromFaces(
  <Vector3>[
    Vector3(0, 0, 0),
    Vector3(1, 0, 0),
    Vector3(1, 0, 1),
    Vector3(0, 0, 1),
  ],
  <List<int>>[
    <int>[0, 1, 2, 3],
  ],
);

void main() {
  group('linking', () {
    test('records the path and the digest', () {
      final ModelObject crate = _crate().objects.single;

      expect(crate.source?.path, 'props/crate.obj');
      expect(crate.source?.sha, 'before');
    });

    test('an object built here has no link at all', () {
      expect(_crate(linked: false).objects.single.source, isNull);
    });

    test('a path of nothing is refused, rather than stored', () {
      final ModelHistory history = ModelHistory(_crate(linked: false));

      // Mutation: store it. The object then claims a source nothing can
      // read, and "Re-import" becomes a button that fails every time.
      expect(
        history.run(const LinkToSource(id: 1, path: '   ', sha: 'x')),
        contains('needs a path'),
      );
      expect(history.project.objects.single.source, isNull);
    });

    test('unlinking forgets where it came from and nothing else', () {
      final ModelHistory history = ModelHistory(_crate());
      final EditMesh was =
          (history.project.objects.single.geometry as EditedGeometry).mesh;

      expect(history.run(const UnlinkSource(id: 1)), isNull);

      final ModelObject crate = history.project.objects.single;
      expect(crate.source, isNull);
      // What the object looks like now *is* what the file last gave it.
      expect(
        (crate.geometry as EditedGeometry).mesh.vertexCount,
        was.vertexCount,
      );
    });

    test('and unlinking what was never linked says so', () {
      final ModelHistory history = ModelHistory(_crate(linked: false));
      expect(history.run(const UnlinkSource(id: 1)), contains('not linked'));
    });
  });

  group('re-importing', () {
    test('replaces the geometry and keeps everything around it', () {
      final ModelHistory history = ModelHistory(_crate());
      final ModelObject before = history.project.objects.single;

      expect(
        history.run(
          Reimport(id: 1, sha: 'after', meshBytes: _plane().toBytes()),
        ),
        isNull,
      );

      // **The row's own acceptance.** Mutation: rebuild the object from the
      // file instead of replacing its geometry, which is what "import again"
      // would do — the transform, the material and the modifier stack all go,
      // and the work done around the mesh has to be done a second time.
      final ModelObject after = history.project.objects.single;
      expect((after.geometry as EditedGeometry).mesh.faceCount, 1);
      expect((before.geometry as EditedGeometry).mesh.faceCount, 6);
      expect(after.transform.getTranslation().x, 3);
      expect(after.materialSlots, <int>[0]);
      expect(after.modifiers, hasLength(1));
      expect(after.name, 'crate');
    });

    test('and moves the digest on, so "has it changed" stays answerable', () {
      final ModelHistory history = ModelHistory(_crate());

      expect(
        history.run(
          Reimport(id: 1, sha: 'after', meshBytes: _plane().toBytes()),
        ),
        isNull,
      );

      expect(history.project.objects.single.source?.sha, 'after');
      expect(history.project.objects.single.source?.path, 'props/crate.obj');
    });

    test('an object with no link refuses, and names what to do', () {
      final ModelHistory history = ModelHistory(_crate(linked: false));

      final String? refused = history.run(
        Reimport(id: 1, sha: 'after', meshBytes: _plane().toBytes()),
      );
      expect(refused, contains('not linked'));
      expect(refused, contains('link it to one first'));
    });

    test('bytes that are not a mesh refuse, naming the file', () {
      final ModelHistory history = ModelHistory(_crate());

      final String? refused = history.run(
        Reimport(id: 1, sha: 'after', meshBytes: Uint8List.fromList(<int>[9])),
      );
      // The last good geometry stays: a file being written while this reads
      // it is the ordinary case, not an exceptional one.
      expect(refused, contains('props/crate.obj'));
      expect(
        (history.project.objects.single.geometry as EditedGeometry)
            .mesh
            .faceCount,
        6,
      );
    });

    test('and one undo puts the old mesh back', () {
      final ModelHistory history = ModelHistory(_crate());

      expect(
        history.run(
          Reimport(id: 1, sha: 'after', meshBytes: _plane().toBytes()),
        ),
        isNull,
      );
      expect(history.undo(), isTrue);

      // A file changing behind the editor is one ordinary step, which is the
      // reason this is a command at all.
      final ModelObject back = history.project.objects.single;
      expect((back.geometry as EditedGeometry).mesh.faceCount, 6);
      expect(back.source?.sha, 'before');
    });
  });

  group('the file format', () {
    test('a link survives a save and a reopen', () {
      final ModelProject project = _crate();

      final ProjectRead read = readProject(writeProject(project));

      expect(read, isA<ProjectOpened>());
      final ModelProject back = (read as ProjectOpened).project;
      expect(back.objects.single.source?.path, 'props/crate.obj');
      expect(back.objects.single.source?.sha, 'before');
    });

    test('and an unlinked object writes no key for it', () {
      // Mutation: always write the pair. Two more keys per object is real
      // bytes on a project of thousands, and almost nothing in almost any
      // file is linked.
      final ModelProject project = _crate(linked: false);
      final ProjectRead read = readProject(writeProject(project));

      expect(read, isA<ProjectOpened>());
      expect((read as ProjectOpened).project.objects.single.source, isNull);
    });
  });
}
