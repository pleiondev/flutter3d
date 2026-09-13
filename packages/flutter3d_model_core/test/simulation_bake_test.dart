/// `BakeSimulationCommand`: `pro-sim-01`'s cloth solver, run frame by frame
/// into a `SimulationCache` — `pro-sim-03`'s own row.
///
///     dart test test/simulation_bake_test.dart
library;

import 'package:flutter3d_cloth/flutter3d_cloth.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';

BakeSimulationCommand bake({int frameCount = 120}) => BakeSimulationCommand(
  objectId: 1,
  baseVersion: 1,
  mesh: ClothMesh.grid(cols: 20, rows: 20, spacing: 0.03, mass: 0.01),
  settings: const ClothSettings(),
  dt: 1 / 60,
  frameCount: frameCount,
);

void main() {
  group("pro-sim-03's own acceptance", () {
    test('baking every frame of a 20×20 cloth gives a 120×400 cache', () async {
      final job = bake(frameCount: 120);

      for (var i = 0; i < job.frameCount; i++) {
        await job.runChunk(i);
      }

      final cache = job.buildCache();
      // The row's own literal acceptance: "120×400 — ожидаемый размер".
      expect(cache.frameCount, 120);
      expect(cache.vertexCount, 400);
      expect(job.bakedFrameCount, 120);
    });

    test('cancelling at frame 50 leaves exactly 50 frames cached', () async {
      final job = bake(frameCount: 120);
      var cancelled = false;

      for (var i = 0; i < job.frameCount; i++) {
        // The same shape a `Job`'s own runner checks between chunks: stop
        // before the next one starts, never partway through one.
        if (cancelled) break;
        await job.runChunk(i);
        if (i == 49) cancelled = true;
      }

      // Mutation: keep baking past 50, or stop one short (49) or one over
      // (51) — any of those and this would no longer be "exactly 50".
      expect(job.bakedFrameCount, 50);
      final cache = job.buildCache();
      expect(cache.frameCount, 50);
      expect(cache.vertexCount, 400);
    });

    test('cancelling before any chunk runs leaves an empty cache, not a null one', () async {
      final job = bake(frameCount: 120);

      final cache = job.buildCache();

      expect(job.bakedFrameCount, 0);
      expect(cache.frameCount, 0);
      expect(cache.isEmpty, isTrue);
      // vertexCount is known from the mesh up front, independent of how many
      // frames actually ran.
      expect(cache.vertexCount, 400);
    });
  });

  group('BakeSimulationCommand', () {
    test('every captured frame is the mesh\'s own particleCount × 3 long', () async {
      final job = bake(frameCount: 3);
      for (var i = 0; i < job.frameCount; i++) {
        await job.runChunk(i);
      }

      final cache = job.buildCache();
      for (var f = 0; f < cache.frameCount; f++) {
        expect(cache.frame(f).length, 400 * 3);
      }
    });

    test('each frame is a snapshot, not a live view into the solver', () async {
      final job = bake(frameCount: 2);
      await job.runChunk(0);
      final firstFrame = job.buildCache().frame(0);
      final firstX = firstFrame[0];

      await job.runChunk(1);

      // Mutation: capture a view over the solver's own mutable positions
      // instead of copying them — the frame recorded for step 0 would then
      // silently read as step 1's values too.
      expect(firstFrame[0], firstX);
    });

    test('buildCache called mid-bake does not see frames captured afterwards', () async {
      final job = bake(frameCount: 5);
      await job.runChunk(0);
      final partial = job.buildCache();
      await job.runChunk(1);

      expect(partial.frameCount, 1);
      expect(job.buildCache().frameCount, 2);
    });

    test('rejects a bake of zero frames', () {
      expect(
        () => BakeSimulationCommand(
          objectId: 1,
          baseVersion: 1,
          mesh: ClothMesh.grid(cols: 2, rows: 2),
          settings: const ClothSettings(),
          dt: 1 / 60,
          frameCount: 0,
        ),
        throwsA(isA<AssertionError>()),
        skip: !_assertionsEnabled(),
      );
    });

    test('objectId and baseVersion are carried through to buildCache\'s own '
        'ApplySimulationCache.of', () async {
      final job = bake(frameCount: 1);
      await job.runChunk(0);

      final command = ApplySimulationCache.of(job);

      expect(command.objectId, 1);
      expect(command.baseVersion, 1);
      expect(command.cache.frameCount, 1);
    });
  });
}

bool _assertionsEnabled() {
  var enabled = false;
  assert(() {
    enabled = true;
    return true;
  }());
  return enabled;
}
