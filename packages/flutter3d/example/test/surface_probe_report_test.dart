/// The surface probe's arithmetic and its report, held still without a GPU.
///
///     flutter test test/surface_probe_report_test.dart
///
/// The probe itself runs as an application —
/// `packages/flutter3d_impeller/tool/surface_probe.sh` — and its numbers are
/// read by a person and by a script. Both read the same lines, so the lines
/// are what is pinned here: which percentile a sample lands at, which
/// findings count as failures, and the verdict line the script greps for.
/// Each test was written by breaking what it covers, and the mutation is
/// named where the test is: the nearest-rank round became a floor, the empty
/// case threw, the resize readback and then a path's readback were left out
/// of the failure count, each number was dropped from its line in turn, and
/// the note was left off — each was seen to fail before it passed.
library;

import 'package:flutter3d_example/surface_probe_report.dart';
import 'package:flutter_test/flutter_test.dart';

PresentPathMeasurement _path(String name, {bool readbackOk = true}) =>
    PresentPathMeasurement(
      name: name,
      stepMicros: const MicrosSamples(<int>[120, 80, 100]),
      imageMicros: const MicrosSamples(<int>[10, 30, 20]),
      intervalMicros: const MicrosSamples(<int>[16600, 16700, 33300]),
      texturesPeak: 3,
      texturesAtEnd: 2,
      bytesPerTexture: 1280 * 800 * 4,
      readbackOk: readbackOk,
    );

const ResizeOutcome _resize = ResizeOutcome(
  statusBefore: 'success',
  statusAfter: 'success',
  backingBefore: 3,
  backingJustAfter: 3,
  backingSettled: 2,
  whileAcquired: 'Bad state: cannot resize',
  readbackOk: true,
);

void main() {
  group('MicrosSamples', () {
    test('the median and p95 are nearest-rank over the sorted samples', () {
      const samples = MicrosSamples(<int>[50, 10, 40, 20, 30]);
      expect(samples.median, 30);
      // (5 - 1) * 0.95 = 3.8, which rounds to rank 4: the last sample.
      expect(samples.p95, 50);
      expect(samples.max, 50);
    });

    test('an empty run reports zero rather than throwing', () {
      // Mutation: the empty guard removed, which makes `sorted[-1]` throw.
      const none = MicrosSamples(<int>[]);
      expect(none.median, 0);
      expect(none.p95, 0);
      expect(none.max, 0);
    });

    test('the ends are pinned and the middle rounds up', () {
      // Two samples make the rounding visible: rank (2 - 1) * 0.5 = 0.5,
      // which `round` takes to 1 and a floor would take to 0. A single sample
      // would have passed floor, ceil and `samples[0]` alike.
      const two = MicrosSamples(<int>[10, 20]);
      expect(two.percentile(0.0), 10);
      expect(two.percentile(1.0), 20);
      expect(two.percentile(0.5), 20);
    });
  });

  group('SurfaceProbeReport', () {
    test('a path whose image read back wrong is a failure', () {
      final report = SurfaceProbeReport(
        width: 1280,
        height: 800,
        frames: 240,
        paths: <PresentPathMeasurement>[
          _path('ring'),
          _path('surface', readbackOk: false),
        ],
        resize: _resize,
      );
      expect(report.failures, 1);
      expect(report.lines.last, '=== surface probe done, 1 failed ===');
    });

    test('a resize whose frame read back wrong is a failure too', () {
      final report = SurfaceProbeReport(
        width: 1280,
        height: 800,
        frames: 240,
        paths: <PresentPathMeasurement>[_path('ring')],
        resize: const ResizeOutcome(
          statusBefore: 'success',
          statusAfter: 'success',
          backingBefore: 3,
          backingJustAfter: 3,
          backingSettled: 3,
          whileAcquired: 'no error',
          readbackOk: false,
        ),
      );
      expect(report.failures, 1);
    });

    test('the lines carry every number a reader needs, once each', () {
      final report = SurfaceProbeReport(
        width: 1280,
        height: 800,
        frames: 240,
        paths: <PresentPathMeasurement>[_path('ring'), _path('surface')],
        resize: _resize,
      );
      final lines = report.lines;
      expect(lines, hasLength(5));
      expect(lines.first, 'surface-probe  1280x800, 240 frames per path');
      // The path line: median step 100, p95 120; median image 20, p95 30;
      // three textures of 4 MB each at the peak, two left at the end.
      expect(lines[1], startsWith('ring     '));
      expect(lines[1], contains('step p50   100us p95   120us'));
      expect(lines[1], contains('image p50    20us p95    30us'));
      expect(lines[1], contains('interval p50  16.7ms p95  33.3ms'));
      expect(lines[1], contains('textures 3 peak (11.7 MB) 2 at end'));
      expect(lines[1], endsWith('readback ok'));
      expect(lines[3], startsWith('resize   status success -> success'));
      expect(lines[3], contains('backing 3 -> 3 -> 2'));
      expect(lines[3], contains('while acquired: Bad state: cannot resize'));
      expect(lines.last, '=== surface probe done, 0 failed ===');
    });

    test('a note rides on the end of its path line', () {
      final report = SurfaceProbeReport(
        width: 64,
        height: 64,
        frames: 1,
        paths: <PresentPathMeasurement>[
          PresentPathMeasurement(
            name: 'trailing',
            stepMicros: const MicrosSamples(<int>[]),
            imageMicros: const MicrosSamples(<int>[]),
            intervalMicros: const MicrosSamples(<int>[]),
            texturesPeak: 0,
            texturesAtEnd: 0,
            bytesPerTexture: 64 * 64 * 4,
            readbackOk: false,
            note: 'present threw: Exception: no',
          ),
        ],
        resize: _resize,
      );
      expect(
        report.lines[1],
        endsWith('readback WRONG  present threw: Exception: no'),
      );
    });
  });
}
