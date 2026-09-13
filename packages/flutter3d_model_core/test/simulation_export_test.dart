/// `pro-sim-05`'s own row, option (a): a baked [SimulationCache] turned into
/// up to eight shape keys, exported as glTF morph targets and read back.
///
///     dart test test/simulation_export_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A project holding one cube, edited rather than parametric — the same
/// fixture `commands_test.dart`'s own `edited()` builds.
ModelHistory edited() {
  final project = const ModelProject().added(
    (int id) => ModelObject(
      id: id,
      name: 'cloth',
      geometry: EditedGeometry(EditMesh.cuboid()),
      transform: Matrix4.identity(),
    ),
  );
  return ModelHistory(project);
}

/// A cache of [frames] frames over [vertexCount] vertices, frame `i` holding
/// every vertex at `(i, i, i)` — distinct enough that no two frames could be
/// mistaken for one another once blended back in.
SimulationCache cacheOf(int vertexCount, int frames) => SimulationCache(
  vertexCount: vertexCount,
  frames: <Float32List>[
    for (var i = 0; i < frames; i++)
      Float32List.fromList(<double>[
        for (var v = 0; v < vertexCount; v++) ...<double>[
          i.toDouble(),
          i.toDouble(),
          i.toDouble(),
        ],
      ]),
  ],
);

void main() {
  group('simulationCacheToShapeKeys', () {
    test('a cache with fewer frames than maxKeys keeps every one of them', () {
      final keys = simulationCacheToShapeKeys(cacheOf(2, 3), maxKeys: 8);
      expect(keys.map((k) => k.name), <String>['sim_0', 'sim_1', 'sim_2']);
    });

    test(
      'a cache with exactly maxKeys frames keeps every one of them, in order',
      () {
        final keys = simulationCacheToShapeKeys(cacheOf(2, 8), maxKeys: 8);
        expect(keys.map((k) => k.name), <String>[
          'sim_0',
          'sim_1',
          'sim_2',
          'sim_3',
          'sim_4',
          'sim_5',
          'sim_6',
          'sim_7',
        ]);
      },
    );

    test(
      'a cache with more frames than maxKeys spreads evenly, both ends included',
      () {
        final keys = simulationCacheToShapeKeys(cacheOf(2, 71), maxKeys: 8);
        expect(keys, hasLength(8));
        expect(keys.first.name, 'sim_0');
        expect(keys.last.name, 'sim_70');
        // Strictly increasing: no frame picked twice, none picked out of order.
        final indices = keys
            .map((k) => int.parse(k.name.substring(4)))
            .toList();
        for (var i = 1; i < indices.length; i++) {
          expect(indices[i], greaterThan(indices[i - 1]));
        }
      },
    );

    test('an empty cache yields no keys at all', () {
      expect(simulationCacheToShapeKeys(cacheOf(2, 0)), isEmpty);
    });

    test('a chosen frame\'s positions travel verbatim, not resampled', () {
      final cache = cacheOf(2, 71);
      final keys = simulationCacheToShapeKeys(cache, maxKeys: 8);
      for (final key in keys) {
        final frame = int.parse(key.name.substring(4));
        expect(key.positions, cache.frame(frame));
      }
    });

    test('maxKeys under one is refused', () {
      expect(
        () => simulationCacheToShapeKeys(cacheOf(2, 3), maxKeys: 0),
        throwsArgumentError,
      );
    });
  });

  group('BakeSimulationToShapes', () {
    test('refuses an object with no baked simulation', () {
      final history = edited();
      expect(
        history.run(const BakeSimulationToShapes(id: 1)),
        contains('no baked simulation'),
      );
    });

    test('refuses an object with no mesh to hold a shape key', () {
      final project = const ModelProject().added(
        (int id) => ModelObject(
          id: id,
          name: 'sphere',
          geometry: ParametricGeometry(const ParametricSphere()),
          transform: Matrix4.identity(),
        ),
      );
      final history = ModelHistory(project);
      history.run(
        ApplySimulationCache(
          objectId: 1,
          baseVersion: history.project[1]!.version,
          cache: cacheOf(1, 2),
        ),
      );

      expect(
        history.run(const BakeSimulationToShapes(id: 1)),
        contains('no mesh to hold a shape key'),
      );
    });

    test('refuses a cache whose vertex count does not match the mesh', () {
      final history = edited();
      final vertexSlots =
          (history.project[1]!.geometry as EditedGeometry).mesh.vertexSlotCount;
      history.run(
        ApplySimulationCache(
          objectId: 1,
          baseVersion: history.project[1]!.version,
          cache: cacheOf(vertexSlots + 1, 2),
        ),
      );

      final refusal = history.run(const BakeSimulationToShapes(id: 1));
      expect(refusal, contains('${vertexSlots + 1} vertices'));
      expect(refusal, contains('$vertexSlots'));
    });

    test(
      'appends up to eight shape keys at weight zero, on top of any already there',
      () {
        final history = edited();
        final vertexSlots = (history.project[1]!.geometry as EditedGeometry)
            .mesh
            .vertexSlotCount;
        history.run(const AddShapeFromMesh(id: 1, shapeName: 'hand-sculpted'));
        history.run(
          ApplySimulationCache(
            objectId: 1,
            baseVersion: history.project[1]!.version,
            cache: cacheOf(vertexSlots, 20),
          ),
        );

        expect(
          history.run(const BakeSimulationToShapes(id: 1, maxKeys: 8)),
          isNull,
        );

        final shapes = history.project[1]!.shapeSet;
        expect(
          shapes.keys,
          hasLength(9),
        ); // the hand-sculpted one, plus 8 baked.
        expect(shapes.keys.first.name, 'hand-sculpted');
        expect(shapes.keys.skip(1).map((k) => k.name).first, 'sim_0');
        expect(shapes.weights.skip(1), everyElement(0.0));
      },
    );

    test('undoes back to no shape keys at all', () {
      final history = edited();
      final vertexSlots =
          (history.project[1]!.geometry as EditedGeometry).mesh.vertexSlotCount;
      history.run(
        ApplySimulationCache(
          objectId: 1,
          baseVersion: history.project[1]!.version,
          cache: cacheOf(vertexSlots, 4),
        ),
      );
      history.run(const BakeSimulationToShapes(id: 1));
      expect(history.project[1]!.shapeSet.keys, isNotEmpty);

      history.undo();
      expect(history.project[1]!.shapeSet.keys, isEmpty);
    });
  });

  group("pro-sim-05's own acceptance", () {
    test('cloth to shapes to GLB: a frame equals the cache', () async {
      final history = edited();
      final vertexSlots =
          (history.project[1]!.geometry as EditedGeometry).mesh.vertexSlotCount;
      final cache = cacheOf(vertexSlots, 20);
      history.run(
        ApplySimulationCache(
          objectId: 1,
          baseVersion: history.project[1]!.version,
          cache: cache,
        ),
      );
      history.run(const BakeSimulationToShapes(id: 1, maxKeys: 8));

      final baseMesh = (history.project[1]!.geometry as EditedGeometry).mesh;
      final plan = MeshLayoutPlan()..build(baseMesh);
      final basePositions = Float32List(plan.vertexCount * 3);
      for (var v = 0; v < plan.vertexCount; v++) {
        final vertex = plan.gpuVertexToVertex[v];
        final position = baseMesh.positionOf(vertex, Vector3.zero());
        basePositions[v * 3] = position.x;
        basePositions[v * 3 + 1] = position.y;
        basePositions[v * 3 + 2] = position.z;
      }

      final document = toModelDocument(history.project);
      final bytes = GltfWriter(document).writeGlb();
      final decoded = await GltfLoader().load(bytes);

      expect(decoded.surfaces, hasLength(1));
      final mesh = decoded.surfaces.single.mesh;
      expect(mesh.morphTargets, hasLength(8));
      // Every new shape key starts at weight zero — the object's rest pose
      // stays the rest pose until somebody dials one in.
      expect(decoded.surfaces.single.morphWeights, everyElement(0.0));

      final chosen = simulationCacheToShapeKeys(cache, maxKeys: 8);
      for (var k = 0; k < mesh.morphTargets.length; k++) {
        final target = mesh.morphTargets[k];
        final sourceFrame = int.parse(chosen[k].name.substring(4));
        final wanted = cache.frame(sourceFrame);
        // A GPU row and the mesh vertex id it came from can differ — a
        // cuboid duplicates a corner once per face for flat shading — so
        // the cache (indexed by `EditMesh` vertex id, the same space a
        // `ShapeKey` is) is compared through [MeshLayoutPlan
        // .gpuVertexToVertex], not by row number.
        for (var v = 0; v < plan.vertexCount; v++) {
          final vertex = plan.gpuVertexToVertex[v];
          for (var c = 0; c < 3; c++) {
            final blended =
                basePositions[v * 3 + c] + target.positions[v * 3 + c];
            expect(
              blended,
              closeTo(wanted[vertex * 3 + c], 1e-4),
              reason: 'target $k, row $v, vertex $vertex, component $c',
            );
          }
        }
      }
    });
  });
}
