/// GPU timings on Impeller: each labelled pass, from its submission to the
/// queue's completion, reported once the frame is done.
///
///     flutter test test/gpu_timings_test.dart
///
/// flutter_gpu has no timestamp query, so the span the backend can see is
/// the one `GpuFrame` measures; the device hands the frame its passes and
/// forwards the report to `onGpuTimings`.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_impeller/src/gpu_frame.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('passes are reported in submission order, with their spans', () {
    // Mutation: `settleIfDone` not reporting — the listener hears nothing,
    // as `onGpuTimings` did when it was an empty body.
    var now = 0;
    final reports = <GpuFrameTimings>[];
    final frame = GpuFrame(number: 7, now: () => now, report: reports.add);

    final shadow = frame.timePass('shadow');
    now = 100;
    final opaque = frame.timePass('opaque');
    frame
      ..outstanding = 2
      ..encoded = true;
    // The second pass completes first; the report keeps submission order.
    now = 400;
    opaque();
    frame.outstanding--;
    frame.settleIfDone();
    expect(reports, isEmpty, reason: 'the frame is not done yet');
    now = 500;
    shadow();
    frame.outstanding--;
    frame.settleIfDone();

    final timings = reports.single;
    expect(timings.frame, 7);
    expect(
      <(String, int)>[for (final p in timings.passes) (p.label, p.micros)],
      <(String, int)>[('shadow', 500), ('opaque', 300)],
    );
  });

  test('a frame with no labelled pass reports nothing', () {
    final reports = <GpuFrameTimings>[];
    GpuFrame(report: reports.add)
      ..encoded = true
      ..settleIfDone();
    expect(reports, isEmpty);
  });
}
