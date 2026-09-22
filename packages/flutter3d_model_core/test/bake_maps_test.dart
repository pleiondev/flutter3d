/// `BakeMaps` — `pro-rt-06`: the bake as a command, the images it adds and
/// the slots they land in.
///
///     dart test test/bake_maps_test.dart
library;

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A UV-mapped unit quad — the low mesh a bake writes into.
EditMesh sheet({double z = 0, bool withUv = true}) {
  final builder = EditMeshBuilder();
  builder
    ..addVertex(Vector3(0, 0, z))
    ..addVertex(Vector3(1, 0, z))
    ..addVertex(Vector3(1, 1, z))
    ..addVertex(Vector3(0, 1, z));
  final int face = builder.addFace(<int>[0, 1, 2, 3]);
  final EditMesh mesh = builder.build();
  if (withUv) {
    mesh.beginStep();
    mesh.forEachHalfEdge(face, (int he) {
      final Vector3 at = mesh.positionOf(mesh.originOf(he));
      mesh.setUv(he, Vector2(at.x, at.y));
    });
    mesh.endStep();
  }
  mesh.clearJournal();
  return mesh;
}

ModelHistory opened({bool withMaterial = true, bool withUv = true}) {
  final ModelProject project = ModelProject(
    objects: <ModelObject>[
      ModelObject(
        id: 1,
        name: 'high',
        geometry: EditedGeometry(sheet(z: -0.05)),
        transform: Matrix4.identity(),
      ),
      ModelObject(
        id: 2,
        name: 'low',
        geometry: EditedGeometry(sheet(withUv: withUv)),
        transform: Matrix4.identity(),
        materialSlots: withMaterial ? const <int>[0] : const <int>[],
      ),
    ],
    materials: withMaterial
        ? <ProjectMaterial>[
            ProjectMaterial(surface: SurfaceMaterial(name: 'shell')),
          ]
        : const <ProjectMaterial>[],
    nextId: 3,
  );
  return ModelHistory(project);
}

void main() {
  group('a normal bake', () {
    test('adds one image and binds it to the material', () {
      final ModelHistory history = opened();
      expect(
        history.run(const BakeMaps(sourceId: 1, targetId: 2, resolution: 32)),
        isNull,
      );

      expect(history.project.images, hasLength(1));
      expect(history.project.images.single.name, 'normal bake');
      final SurfaceMaterial surface = history.project.materials.single.surface;
      expect(surface.normalTexture?.imageIndex, 0);
      // **Mutation: leave the image unbound.** A baked map nothing points at
      // is a file that grows and a model that draws exactly as it did
      // before, which reads as the bake having silently failed.
      expect(surface.occlusionTexture, isNull);
    });

    test('and undo takes the image and the binding back together', () {
      final ModelHistory history = opened();
      expect(
        history.run(const BakeMaps(sourceId: 1, targetId: 2, resolution: 16)),
        isNull,
      );
      expect(history.undo(), isTrue);
      expect(history.project.images, isEmpty);
      expect(history.project.materials.single.surface.normalTexture, isNull);
    });
  });

  group('several maps', () {
    test('are one step, and land in the slots the format has', () {
      final ModelHistory history = opened();
      expect(
        history.run(
          const BakeMaps(
            sourceId: 1,
            targetId: 2,
            maps: <String>['normal', 'ao', 'curvature', 'thickness'],
            resolution: 16,
          ),
        ),
        isNull,
      );

      expect(history.steps, hasLength(1));
      expect(history.project.images, hasLength(4));
      final SurfaceMaterial surface = history.project.materials.single.surface;
      expect(surface.normalTexture, isNotNull);
      expect(surface.occlusionTexture, isNotNull);
      // Curvature and thickness have no slot in glTF at all, so they are in
      // the project for a texture graph to read and bound to nothing — which
      // is the format's own shape rather than a gap here.
      expect(
        history.project.images.map((EncodedImage it) => it.name),
        containsAll(<String>['curvature bake', 'thickness bake']),
      );
    });

    test('curvature alone changes no material', () {
      final ModelHistory history = opened();
      expect(
        history.run(
          const BakeMaps(
            sourceId: 1,
            targetId: 2,
            maps: <String>['curvature'],
            resolution: 16,
          ),
        ),
        isNull,
      );
      expect(history.project.images, hasLength(1));
      expect(history.project.materials.single.surface.normalTexture, isNull);
    });
  });

  group('refusals', () {
    test('a resolution outside 16..4096', () {
      final ModelHistory history = opened();
      expect(
        history.run(const BakeMaps(sourceId: 1, targetId: 2, resolution: 8)),
        contains('not 8'),
      );
    });

    test('a map this build does not know, naming the ones it does', () {
      final ModelHistory history = opened();
      final String? refusal = history.run(
        const BakeMaps(
          sourceId: 1,
          targetId: 2,
          maps: <String>['displacement'],
          resolution: 16,
        ),
      );
      expect(refusal, contains('displacement'));
      expect(refusal, contains('curvature'));
    });

    test('a target with no UVs, saying to unwrap it', () {
      final ModelHistory history = opened(withUv: false);
      expect(
        history.run(const BakeMaps(sourceId: 1, targetId: 2, resolution: 16)),
        contains('unwrap'),
      );
    });

    test('a target with no material for the map to land on', () {
      final ModelHistory history = opened(withMaterial: false);
      expect(
        history.run(const BakeMaps(sourceId: 1, targetId: 2, resolution: 16)),
        contains('material'),
      );
    });

    test('and an object that is not there', () {
      final ModelHistory history = opened();
      expect(
        history.run(const BakeMaps(sourceId: 9, targetId: 2, resolution: 16)),
        contains('9'),
      );
    });
  });

  group('written down', () {
    test('reads back as itself', () {
      final ModelCommand? read = modelCommandFromJson(
        const BakeMaps(
          sourceId: 1,
          targetId: 2,
          maps: <String>['normal', 'ao'],
          resolution: 512,
          shell: 0.25,
        ).toJson(),
      );
      expect(read, isA<BakeMaps>());
      final BakeMaps back = read! as BakeMaps;
      expect(back.sourceId, 1);
      expect(back.targetId, 2);
      expect(back.maps, <String>['normal', 'ao']);
      expect(back.resolution, 512);
      expect(back.shell, 0.25);
    });
  });
}
