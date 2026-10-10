/// A pipeline flutter_gpu will not link is reported and its draw skipped,
/// with no GPU in the room.
///
///     flutter test test/gpu_pipeline_test.dart
///
/// **The field case.** On an Adreno phone that falls back to OpenGL ES,
/// flutter_gpu links a pipeline lazily at its first draw, and a refused link
/// comes back as `Exception: Failed to append drawIndexed`. The encoder threw
/// it, the renderer rethrew, and every frame failed. [GpuPipeline] is what the
/// encoder now asks instead; it is generic over the linked object, so these
/// tests hand it strings where the backend hands it a `gpu.RenderPipeline`.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter3d_impeller/src/gpu_pipeline.dart';
import 'package:flutter_test/flutter_test.dart';

/// A handle to report against; the fake's, since a handle cannot be made
/// without a device.
PipelineHandle _handle(FakeBackend device) => device.createPipeline(
  device.shaders['MeshVertex']!,
  device.shaders['Pbr']!,
);

void main() {
  test('a link that throws is reported, and built again at the next use', () {
    // Mutation: let `linked` rethrow, and `createPipeline` throws on the
    // GLES phone exactly as the draw did.
    final device = FakeBackend();
    final handle = _handle(device);
    final refusals = PipelineRefusals();
    var builds = 0;
    final pipeline = GpuPipeline<String>('MeshVertex+Pbr', () {
      builds++;
      if (builds == 1) throw Exception('Failed to create pipeline');
      return 'linked';
    });

    expect(pipeline.linked(handle, refusals, deviceLost: false), isNull);
    expect(refusals.drain().single.reason, PipelineRefusalReason.link);
    expect(pipeline.linked(handle, refusals, deviceLost: false), 'linked');
    expect(pipeline.linked(handle, refusals, deviceLost: false), 'linked');
    expect(builds, 2);
  });

  test('a refused draw drops the pipeline, and the next bind relinks', () {
    // Mutation: keep `_linked` after `refusedAtDraw`, and the next bind
    // binds the pipeline the driver has already refused.
    final device = FakeBackend();
    final handle = _handle(device);
    final refusals = PipelineRefusals();
    var builds = 0;
    final pipeline = GpuPipeline<String>('MeshVertex+Pbr', () {
      builds++;
      return 'linked $builds';
    });

    expect(pipeline.linked(handle, refusals, deviceLost: false), 'linked 1');
    pipeline.refusedAtDraw(
      handle,
      refusals,
      Exception('Failed to append drawIndexed'),
      deviceLost: false,
    );
    expect(pipeline.linked(handle, refusals, deviceLost: false), 'linked 2');
    final told = refusals.drain().single;
    expect(told.pipeline, 'MeshVertex+Pbr');
    expect(told.backend, 'Impeller');
    expect(told.detail, contains('Failed to append drawIndexed'));
  });

  test('after maxBuilds failures nothing is built and nothing bound', () {
    // Mutation: ignore `isRefused` in `linked`, and a pipeline the driver
    // never links is built on every bind of every frame.
    final device = FakeBackend();
    final handle = _handle(device);
    final refusals = PipelineRefusals();
    var builds = 0;
    final pipeline = GpuPipeline<String>('MeshVertex+Pbr', () {
      builds++;
      throw Exception('Failed to create pipeline');
    });
    for (var bind = 0; bind < 10; bind++) {
      expect(pipeline.linked(handle, refusals, deviceLost: false), isNull);
    }
    expect(builds, PipelineRefusals.maxBuilds);
    expect(refusals.isRefused(handle), isTrue);
    expect(refusals.drain(), hasLength(1));
  });

  test('a linked pipeline the record leaves refused is not bound', () {
    // The conformance check refuses through the record, as a backend does
    // after the builds fail; a backend has to ask it whatever it linked.
    //
    // Mutation: return `_linked` before asking `isRefused`, and the check's
    // refused pipeline draws red.
    final device = FakeBackend();
    final handle = _handle(device);
    final refusals = PipelineRefusals();
    final pipeline = GpuPipeline<String>('MeshVertex+Pbr', () => 'linked');
    expect(pipeline.linked(handle, refusals, deviceLost: false), 'linked');
    refusals.report(
      handle,
      const PipelineRefusedException(
        pipeline: 'MeshVertex+Pbr',
        backend: 'test',
        reason: PipelineRefusalReason.other,
      ),
      retry: false,
    );
    expect(pipeline.linked(handle, refusals, deviceLost: false), isNull);
  });

  test('a refusal on a lost device says so', () {
    final device = FakeBackend();
    final handle = _handle(device);
    final refusals = PipelineRefusals();
    GpuPipeline<String>(
      'MeshVertex+Pbr',
      () => throw Exception('Failed to create pipeline'),
    ).linked(handle, refusals, deviceLost: true);
    expect(refusals.drain().single.reason, PipelineRefusalReason.deviceLost);
  });

  test('only a refused draw is taken for a link failure', () {
    // Mutation: answer true for any exception, and a binding mistake (a
    // sparse vertex slot, which flutter_gpu throws a StateError for) is
    // swallowed as a refused pipeline.
    expect(isRefusedDraw(Exception('Failed to append drawIndexed')), isTrue);
    expect(isRefusedDraw(Exception('Failed to append draw')), isTrue);
    expect(isRefusedDraw(StateError('vertex slot 1 unbound')), isFalse);
    expect(isRefusedDraw(Exception('Failed to bind texture')), isFalse);
  });
}
