/// `ImportInto`: merging a second file into a project that already has
/// objects in it, rather than starting over.
///
///     dart test test/import_into_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

final class _Doc extends ModelDocument {
  _Doc({
    required this.surfaces,
    required this.nodes,
    required this.roots,
    this.materials = const <SurfaceMaterial>[],
    this.images = const <EncodedImage>[],
    this.warnings = const <String>[],
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
  final List<String> warnings;
}

/// A single-object document: one cube, one steel material sampling one
/// image, unless [withTexture] says otherwise.
// ignore: library_private_types_in_public_api
_Doc oneCube({
  String name = 'cube',
  bool withTexture = true,
  double roughness = 0.25,
}) => _Doc(
  surfaces: <ModelSurface>[
    ModelSurface(
      name: name,
      mesh: EditMesh.cuboid().toMeshData(),
      transform: Matrix4.identity(),
      materialIndex: 0,
    ),
  ],
  nodes: <ModelNode>[
    ModelNode(
      name: name,
      translation: Vector3.zero(),
      rotation: Quaternion.identity(),
      scale: Vector3(1, 1, 1),
      surfaces: <int>[0],
    ),
  ],
  roots: <int>[0],
  materials: <SurfaceMaterial>[
    SurfaceMaterial(
      name: 'steel',
      baseColor: Vector4(0.2, 0.3, 0.4, 1.0),
      metallic: 1.0,
      roughness: roughness,
      baseColorTexture: withTexture
          ? const TextureBinding(imageIndex: 0)
          : null,
    ),
  ],
  images: withTexture
      ? <EncodedImage>[
          EncodedImage(
            bytes: Uint8List.fromList(<int>[1, 2, 3]),
            name: 'atlas',
          ),
        ]
      : const <EncodedImage>[],
);

/// A document with a parent object and one child under it, so the merge's
/// own re-parenting can be checked.
// ignore: library_private_types_in_public_api
_Doc parentAndChild() => _Doc(
  surfaces: <ModelSurface>[
    ModelSurface(
      name: 'parent',
      mesh: EditMesh.cuboid().toMeshData(),
      transform: Matrix4.identity(),
    ),
    ModelSurface(
      name: 'child',
      mesh: EditMesh.cuboid().toMeshData(),
      transform: Matrix4.identity(),
    ),
  ],
  nodes: <ModelNode>[
    ModelNode(
      name: 'parent',
      translation: Vector3.zero(),
      rotation: Quaternion.identity(),
      scale: Vector3(1, 1, 1),
      children: <int>[1],
      surfaces: <int>[0],
    ),
    ModelNode(
      name: 'child',
      translation: Vector3.zero(),
      rotation: Quaternion.identity(),
      scale: Vector3(1, 1, 1),
      surfaces: <int>[1],
    ),
  ],
  roots: <int>[0],
);

void main() {
  group('two imports of the identical document', () {
    test('objects of both, one material, one image — not doubled', () {
      final doc = oneCube();
      final first = importInto(const ModelProject(), doc);
      final second = importInto(first.project, doc);

      // Mutation: append every incoming material/image unconditionally
      // instead of comparing by content — this would read 2 and 2 instead
      // of the acceptance's own "один SurfaceMaterial на одинаковый
      // материал."
      expect(second.project.objects, hasLength(2));
      expect(second.project.materials, hasLength(1));
      expect(second.project.images, hasLength(1));
    });

    test('both objects point at the same, single material slot', () {
      final doc = oneCube();
      final first = importInto(const ModelProject(), doc);
      final second = importInto(first.project, doc);

      expect(second.project.objects[0].materialSlots, <int>[0]);
      expect(second.project.objects[1].materialSlots, <int>[0]);
    });

    test(
      'the second import\'s own ids continue from the first, not from 1',
      () {
        final doc = oneCube();
        final first = importInto(const ModelProject(), doc);
        final second = importInto(first.project, doc);

        // Mutation: start `merged.nextId` fresh each call (e.g. build off a
        // bare `ModelProject()` instead of `project.copyWith(...)`) — the
        // second import's own object would collide with the first's id.
        expect(
          second.project.objects[0].id,
          isNot(second.project.objects[1].id),
        );
        expect(
          second.project.objects[1].id,
          greaterThan(second.project.objects[0].id),
        );
      },
    );
  });

  group('materials and images that genuinely differ are not merged', () {
    test('a different roughness keeps two materials', () {
      final a = importInto(const ModelProject(), oneCube(roughness: 0.25));
      final b = importInto(a.project, oneCube(roughness: 0.9));

      expect(b.project.materials, hasLength(2));
    });

    test('the same material with no texture and one with a texture do not '
        'merge', () {
      final a = importInto(const ModelProject(), oneCube(withTexture: false));
      final b = importInto(a.project, oneCube());

      expect(b.project.materials, hasLength(2));
      expect(b.project.images, hasLength(1));
    });
  });

  group('a texture binding is remapped onto the merged image table', () {
    test('an image already in the project is reused, not duplicated, and '
        'the new material\'s own binding points at it', () {
      final a = importInto(const ModelProject(), oneCube());
      final b = importInto(a.project, oneCube(name: 'second'));

      expect(b.project.images, hasLength(1));
      // Mutation: keep the incoming document's own raw `imageIndex` (0)
      // rather than rewriting it onto the merged table — this passes by
      // coincidence when the merged table also starts at 0 for the first
      // image, which is exactly why the next test exists: a case where the
      // raw and the remapped index are different numbers.
      expect(
        b.project.materials.single.surface.baseColorTexture!.imageIndex,
        0,
      );
    });

    test('a binding is rewritten onto a *different* index when the image '
        'lands somewhere else in the merged table', () {
      // The existing project already has an unrelated image at index 0, so
      // the incoming document's own image — index 0 in *its* table — has to
      // land at index 1 in the merged one.
      final unrelated = ModelProject(
        images: <EncodedImage>[
          EncodedImage(bytes: Uint8List.fromList(<int>[9, 9, 9])),
        ],
      );
      final result = importInto(unrelated, oneCube());

      expect(result.project.images, hasLength(2));
      // Mutation: forget the remap and this would read 0 — the wrong
      // picture, the one already in the project rather than the cube's own
      // atlas.
      expect(
        result.project.materials.single.surface.baseColorTexture!.imageIndex,
        1,
      );
    });
  });

  group('hierarchy: a root and its child both come in as roots of nothing '
      'except each other', () {
    test('the child\'s own parent is the new id its parent was actually '
        'given, not the id it had in the source document', () {
      final result = importInto(const ModelProject(), parentAndChild());

      expect(result.project.objects, hasLength(2));
      final parent = result.project.objects[0];
      final child = result.project.objects[1];
      expect(parent.parent, isNull);
      // Mutation: carry the incoming document's own parent id straight
      // through unmapped — `parentAndChild`'s own child names parent `0`,
      // which would then point at whatever object happens to already hold
      // id 0 in the *target* project (nothing, here, since ids start at 1)
      // rather than at the freshly-added parent.
      expect(child.parent, parent.id);
    });

    test('merged into a project that already has objects, the child still '
        'finds its own new parent, not the old one\'s id', () {
      final existing = importInto(const ModelProject(), oneCube());
      final result = importInto(existing.project, parentAndChild());

      final parent = result.project.objects[1]; // after the pre-existing cube
      final child = result.project.objects[2];
      expect(child.parent, parent.id);
      expect(parent.id, isNot(1)); // ids did not restart
    });
  });

  group('the report', () {
    test('counts and warnings describe the incoming document alone, not '
        'the whole merged project', () {
      final existing = importInto(const ModelProject(), oneCube());
      final result = importInto(existing.project, parentAndChild());

      // Mutation: count `result.project.objects.length` (3, including the
      // pre-existing cube) instead of just what this call brought in (2).
      expect(result.counts.objects, 2);
    });

    test('warnings pass the decoder\'s own words through verbatim', () {
      final withWarning = _Doc(
        surfaces: const <ModelSurface>[],
        nodes: const <ModelNode>[],
        roots: const <int>[],
        warnings: const <String>['a made-up decoder warning'],
      );
      final result = importInto(const ModelProject(), withWarning);
      expect(result.issues, <String>['a made-up decoder warning']);
    });
  });
}
