/// A pipeline the backend will not build: reported once, its draws skipped,
/// rebuilt a bounded number of times and then left refused.
///
/// A lazily linked pipeline on an OpenGL ES driver used to throw from the
/// draw, and the renderer rethrew it, so one pair of stages one phone would
/// not link failed every frame. These hold the device's half of the answer;
/// the renderer's half is `pipeline_refused_frame_test.dart` in
/// `flutter3d_core`.
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show Flutter3dException, ResourceException;
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter3d_hardware/trace.dart' show RecordingDevice;
import 'package:test/test.dart';

const _descriptor = RenderPassDescriptor(colors: <ColorTarget>[]);

/// One pass, as one frame of a scene draws it: the good pipeline, the one
/// that refuses, and the good one again.
FakePass _frame(FakeBackend device, PipelineHandle good, PipelineHandle bad) {
  final pass = device.beginRenderPass(_descriptor) as FakePass;
  pass
    ..bindPipeline(good)
    ..draw()
    ..bindPipeline(bad)
    ..draw()
    ..bindPipeline(good)
    ..draw()
    ..submit();
  return pass;
}

PipelineRefused _refusal([String pipeline = 'MeshVertex+Bad']) =>
    PipelineRefused(
      pipeline: pipeline,
      backend: 'test',
      reason: PipelineRefusalReason.link,
    );

void main() {
  group('PipelineRefusalReason', () {
    test('is an open set that reads its names back', () {
      // Mutation: make it an enum, and the S0 rule fails the snapshot; drop
      // `byName`, and a log line cannot be read back.
      expect(PipelineRefusalReason.values.map((r) => r.name), <String>[
        'compile',
        'link',
        'unsupportedFormat',
        'deviceLost',
        'other',
      ]);
      for (final reason in PipelineRefusalReason.values) {
        expect(PipelineRefusalReason.byName(reason.name), same(reason));
      }
      expect(PipelineRefusalReason.byName('cosmicRay'), isNull);
    });
  });

  group('PipelineRefused', () {
    test('is a resource exception naming the pipeline, backend and reason', () {
      const refusal = PipelineRefused(
        pipeline: 'MeshVertex+Pbr',
        backend: 'Impeller',
        reason: PipelineRefusalReason.link,
        detail: 'Failed to append drawIndexed',
      );
      expect(refusal, isA<ResourceException>());
      expect(refusal, isA<Flutter3dException>());
      expect(refusal.message, contains('MeshVertex+Pbr'));
      expect(refusal.message, contains('Impeller'));
      expect(refusal.message, contains('link'));
      expect(refusal.message, contains('Failed to append drawIndexed'));
    });
  });

  group('PipelineRefusals', () {
    test('may build again until maxBuilds failures, then is refused', () {
      // Mutation: answer `true` from `report` always, and a pipeline that
      // will never link is rebuilt every frame for ever.
      final device = FakeBackend();
      final pipeline = device.createPipeline(
        device.shaders['MeshVertex']!,
        device.shaders['Bad']!,
      );
      final refusals = PipelineRefusals();
      final answers = <bool>[
        for (var i = 0; i < PipelineRefusals.maxBuilds; i++)
          refusals.report(pipeline, _refusal()),
      ];
      expect(answers, <bool>[
        for (var i = 1; i <= PipelineRefusals.maxBuilds; i++)
          i < PipelineRefusals.maxBuilds,
      ]);
      expect(refusals.isRefused(pipeline), isTrue);
      expect(refusals.failuresOf(pipeline), PipelineRefusals.maxBuilds);
    });

    test('a refusal no rebuild can change is left refused at once', () {
      // Mutation: ignore `retry`, and a backend that knows the format will
      // never be readable builds the pipeline twice more for nothing.
      final device = FakeBackend();
      final pipeline = device.createPipeline(
        device.shaders['MeshVertex']!,
        device.shaders['Bad']!,
      );
      final refusals = PipelineRefusals();
      expect(refusals.report(pipeline, _refusal(), retry: false), isFalse);
      expect(refusals.isRefused(pipeline), isTrue);
      expect(refusals.take(), hasLength(1));
    });

    test('tells each pipeline once, and take drains what it told', () {
      // Mutation: queue every report rather than the first, and a refused
      // pipeline is told on every frame that skips it.
      final device = FakeBackend();
      final vertex = device.shaders['MeshVertex']!;
      final a = device.createPipeline(vertex, device.shaders['A']!);
      final b = device.createPipeline(vertex, device.shaders['B']!);
      final refusals = PipelineRefusals()
        ..report(a, _refusal('MeshVertex+A'))
        ..report(a, _refusal('MeshVertex+A'))
        ..report(b, _refusal('MeshVertex+B'));
      expect(refusals.take().map((r) => r.pipeline), <String>[
        'MeshVertex+A',
        'MeshVertex+B',
      ]);
      expect(refusals.take(), isEmpty);
      refusals.report(a, _refusal('MeshVertex+A'));
      expect(refusals.take(), isEmpty);
      expect(refusals.refusalOf(a)?.pipeline, 'MeshVertex+A');
    });

    test('a device that never reports has nothing to take', () {
      // The default an outside backend inherits: an empty record, which
      // reads as every pipeline built.
      final device = FakeBackend();
      final vertex = device.shaders['MeshVertex']!;
      final good = device.createPipeline(vertex, device.shaders['Good']!);
      _frame(device, good, good);
      expect(device.pipelineRefusals.take(), isEmpty);
    });
  });

  group('a fake backend whose driver refuses a pipeline', () {
    test('skips its draws, draws the others, and tells it once', () {
      // Mutation: record the refused draw in FakePass.draw, and the count of
      // draws per frame is three; report on every failed build, and the
      // first frame tells it twice over the frames below.
      final device = FakeBackend(refusingPipelines: <String>{'MeshVertex+Bad'});
      final vertex = device.shaders['MeshVertex']!;
      final good = device.createPipeline(vertex, device.shaders['Good']!);
      final bad = device.createPipeline(vertex, device.shaders['Bad']!);

      final told = <PipelineRefused>[];
      for (var frame = 0; frame < 10; frame++) {
        final pass = _frame(device, good, bad);
        expect(pass.drawCount, 2, reason: 'frame $frame');
        told.addAll(device.pipelineRefusals.take());
      }
      expect(told, hasLength(1));
      expect(told.single.pipeline, 'MeshVertex+Bad');
      expect(told.single.reason, PipelineRefusalReason.link);
      expect(told.single.backend, 'FakeBackend');
    });

    test('builds it at most maxBuilds times, then leaves it refused', () {
      // Mutation: build at every draw whatever `isRefused` says, and the
      // ten frames below make ten builds.
      final device = FakeBackend(refusingPipelines: <String>{'MeshVertex+Bad'});
      final vertex = device.shaders['MeshVertex']!;
      final good = device.createPipeline(vertex, device.shaders['Good']!);
      final bad = device.createPipeline(vertex, device.shaders['Bad']!);
      for (var frame = 0; frame < 10; frame++) {
        _frame(device, good, bad);
      }
      expect(
        device.pipelineBuilds['MeshVertex+Bad'],
        PipelineRefusals.maxBuilds,
      );
      expect(device.pipelineRefusals.isRefused(bad), isTrue);
      expect(device.pipelineRefusals.isRefused(good), isFalse);
    });

    test('a rebuild that links draws again, and is still told once', () {
      // A driver that refused once — a link that ran out of memory while a
      // level loaded — and links at the next try.
      //
      // Mutation: never build again after a refusal, and every later frame
      // still skips the draw.
      final device = FakeBackend(
        refusingPipelines: <String>{'MeshVertex+Bad'},
        refusedBuilds: 1,
      );
      final vertex = device.shaders['MeshVertex']!;
      final good = device.createPipeline(vertex, device.shaders['Good']!);
      final bad = device.createPipeline(vertex, device.shaders['Bad']!);

      expect(_frame(device, good, bad).drawCount, 2);
      expect(_frame(device, good, bad).drawCount, 3);
      expect(_frame(device, good, bad).drawCount, 3);
      expect(device.pipelineRefusals.take(), hasLength(1));
      expect(device.pipelineRefusals.isRefused(bad), isFalse);
      expect(device.pipelineBuilds['MeshVertex+Bad'], 2);
    });

    test('a pipeline the record leaves refused is skipped whoever said so', () {
      // What the conformance check leans on: it refuses through the record,
      // and the encoder has to ask it for every pipeline, not only those its
      // own driver refused.
      //
      // Mutation: ask `refusingPipelines` before the record, and the good
      // pipeline refused here still draws.
      final device = FakeBackend();
      final vertex = device.shaders['MeshVertex']!;
      final good = device.createPipeline(vertex, device.shaders['Good']!);
      final bad = device.createPipeline(vertex, device.shaders['Bad']!);
      device.pipelineRefusals.report(bad, _refusal(), retry: false);
      expect(_frame(device, good, bad).drawCount, 2);
    });

    test('a recorder answers with the device it records', () {
      // Mutation: drop the override in RecordingDevice, and a renderer
      // drawing through a recorder never hears of a refusal.
      final inner = FakeBackend(refusingPipelines: <String>{'MeshVertex+Bad'});
      final recorder = RecordingDevice(inner);
      expect(recorder.pipelineRefusals, same(inner.pipelineRefusals));
    });
  });
}
