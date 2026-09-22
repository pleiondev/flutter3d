/// `pro-sim-04`'s own acceptance: frame 0 and frame 60 of a played-back cache
/// differ, and the obstacle the simulation collided against draws.
///
///     flutter test test/simulation_playback_test.dart
///
/// The cache baked here is not synthetic noise: it is `pro-sim-01`'s own
/// `stepCloth` run 60 times on a small pinned grid falling under gravity onto
/// a `CollisionBox` floor, so frame 60 differing from frame 0 is a real solver
/// result, not an arithmetic fixture built to differ on purpose.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter3d_modeler/src/simulation_collision_draw.dart';
import 'package:flutter3d_modeler/src/simulation_playback.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'support/simulation_cache_stub.dart';

/// Bakes 61 frames (frame 0 = rest pose, frames 1..60 = one `stepCloth` each)
/// of a pinned cloth grid falling under gravity onto a floor.
SimulationCacheStub _bakeFallingCloth() {
  final mesh = ClothMesh.grid(
    cols: 6,
    rows: 6,
    spacing: 0.1,
    height: 1.0,
    mass: 0.05,
  );
  const settings = ClothSettings();
  const dt = 1 / 60;
  final floor = ClothObstacle(
    CollisionBox(Vector3(5, 0.05, 5)),
    Vector3(0.25, 0.2, 0.25),
  );

  final frames = <Float32List>[Float32List.fromList(mesh.positions)];
  for (var step = 0; step < 60; step++) {
    stepCloth(mesh, settings, dt, obstacles: [floor]);
    frames.add(Float32List.fromList(mesh.positions));
  }

  return SimulationCacheStub(vertexCount: mesh.particleCount, frames: frames);
}

void main() {
  group("pro-sim-04's own acceptance", () {
    test('frame 0 and frame 60 of a baked cloth cache differ', () {
      final cache = _bakeFallingCloth();
      expect(cache.frameCount, greaterThanOrEqualTo(61));

      final frame0 = cache.frameAt(0);
      final frame60 = cache.frameAt(60);

      var maxAbsDifference = 0.0;
      for (var i = 0; i < frame0.length; i++) {
        final diff = (frame0[i] - frame60[i]).abs();
        if (diff > maxAbsDifference) maxAbsDifference = diff;
      }
      expect(
        maxAbsDifference,
        greaterThan(1e-4),
        reason:
            'a cloth falling under gravity for a simulated second should have '
            'moved well past floating-point noise between frame 0 and 60',
      );
    });

    test(
      'playSimulationFrame writes frame 0, then frame 60, onto the mesh',
      () {
        final cache = _bakeFallingCloth();
        final meshData = MeshData(
          layout: VertexLayout.positionOnly,
          vertices: Float32List.fromList(cache.frameAt(0)),
          indices: Uint32List.fromList([0, 1, 2]),
        );
        final device = FakeBackend();
        final deviceMesh = DeviceMesh.upload(
          device,
          meshData,
          keepSourceData: false,
        );

        final versionBefore = deviceMesh.version;
        playSimulationFrame(deviceMesh, device, cache, 0);
        playSimulationFrame(deviceMesh, device, cache, 60);

        // FakeBackend records wiring, not content (see
        // `device_mesh_overwrite_bench_test.dart`'s own doc comment for why),
        // so the whole-buffer-overwrite shape is asserted on what it *does*
        // record: two overwrites, each covering every vertex from zero.
        expect(device.overwrites, hasLength(2));
        final expectedBytes = cache.vertexCount * 12; // position-only stride.
        for (final overwrite in device.overwrites) {
          expect(overwrite.offsetInBytes, 0);
          expect(overwrite.lengthInBytes, expectedBytes);
        }
        expect(deviceMesh.version, versionBefore + 2);

        // The content actually handed to `overwriteVertices` for each call is
        // the cache's own frame data — the numeric difference belongs to the
        // frames themselves, checked directly above; this call confirms
        // playback does not throw and wires the whole buffer both times.
      },
    );

    test('rejects a cache whose vertex count does not match the mesh', () {
      final cache = _bakeFallingCloth();
      final meshData = MeshData(
        layout: VertexLayout.positionOnly,
        vertices: Float32List(3 * 3), // 3 vertices, not `cache.vertexCount`.
        indices: Uint32List.fromList([0, 1, 2]),
      );
      final device = FakeBackend();
      final deviceMesh = DeviceMesh.upload(
        device,
        meshData,
        keepSourceData: false,
      );

      expect(
        () => playSimulationFrame(deviceMesh, device, cache, 0),
        throwsArgumentError,
      );
    });

    test(
      'draws a wireframe box around the collision obstacle the cloth fell onto',
      () {
        final floor = ClothObstacle(
          CollisionBox(Vector3(5, 0.05, 5)),
          Vector3(0.25, 0.2, 0.25),
        );
        final draw = DebugDraw();

        expect(draw.isEmpty, isTrue);
        drawClothObstacles(draw, [floor]);

        // A box has 12 edges, 2 vertices each.
        expect(draw.lineCount, 12);
        expect(draw.isEmpty, isFalse);

        // Every drawn vertex should lie on the obstacle's own world-space
        // bounds — the box grown to nothing beyond `boundsHalfExtents`,
        // centred on its position.
        final bounds = Aabb3();
        floor.shape.computeBounds(floor.position, bounds);
        final bytes = draw.vertexBytes;
        for (var v = 0; v < draw.vertexCount; v++) {
          final base = v * DebugDraw.floatsPerVertex * 4;
          final x = bytes.getFloat32(base, Endian.host);
          final y = bytes.getFloat32(base + 4, Endian.host);
          final z = bytes.getFloat32(base + 8, Endian.host);
          expect(x, inInclusiveRange(bounds.min.x - 1e-6, bounds.max.x + 1e-6));
          expect(y, inInclusiveRange(bounds.min.y - 1e-6, bounds.max.y + 1e-6));
          expect(z, inInclusiveRange(bounds.min.z - 1e-6, bounds.max.z + 1e-6));
        }
      },
    );
  });
}
