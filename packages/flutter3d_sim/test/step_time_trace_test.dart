/// `rp-06`'s mechanism: how long each step of a run cost, keyed by step
/// number, the way `DigestTrace` keys a checkpoint.
///
///     dart test test/step_time_trace_test.dart
library;

import 'dart:convert';

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

void main() {
  group('observe', () {
    test('keeps a sample every step by default', () {
      final trace = StepTimeTrace();
      for (var step = 1; step <= 5; step++) {
        trace.observe(step, step.toDouble());
      }
      expect(trace.steps, <int>[1, 2, 3, 4, 5]);
      expect(trace.millis, <double>[1.0, 2.0, 3.0, 4.0, 5.0]);
    });

    test('keeps only every Nth step when asked', () {
      final trace = StepTimeTrace(every: 10);
      for (var step = 1; step <= 30; step++) {
        trace.observe(step, 1.0);
      }
      expect(trace.steps, <int>[10, 20, 30]);
    });

    test('is empty until the first sample', () {
      final trace = StepTimeTrace();
      expect(trace.isEmpty, isTrue);
      expect(trace.worstStep, isNull);
      expect(trace.worstMillis, isNull);
      expect(trace.meanMillis, isNull);
      trace.observe(1, 5.0);
      expect(trace.isEmpty, isFalse);
    });
  });

  group('record', () {
    test('times the body and returns its result unchanged', () {
      final trace = StepTimeTrace();
      final result = trace.record(1, () {
        var total = 0;
        for (var i = 0; i < 100000; i++) {
          total += i;
        }
        return total;
      });
      expect(result, 4999950000);
      expect(trace.steps, <int>[1]);
      expect(trace.millis.single, greaterThanOrEqualTo(0.0));
    });
  });

  group('worstStep, worstMillis and meanMillis', () {
    test('name the spike, not just its size', () {
      final trace = StepTimeTrace()
        ..observe(1, 2.0)
        ..observe(2, 9.5)
        ..observe(3, 3.0);

      expect(trace.worstStep, 2, reason: 'step 2 cost the most');
      expect(trace.worstMillis, 9.5);
      expect(trace.meanMillis, closeTo((2.0 + 9.5 + 3.0) / 3, 1e-9));
    });

    test('names the first spike when two steps tie', () {
      final trace = StepTimeTrace()
        ..observe(1, 5.0)
        ..observe(2, 9.0)
        ..observe(3, 9.0);

      expect(trace.worstStep, 2);
    });
  });

  group('the document', () {
    test('survives a round trip through JSON', () {
      final written = StepTimeTrace(every: 3)
        ..observe(3, 1.25)
        ..observe(6, 4.5)
        ..observe(9, 0.75);

      final read = StepTimeTrace.fromJson(
        jsonDecode(jsonEncode(written.toJson())) as Map<String, Object?>,
      );

      expect(read.every, written.every);
      expect(read.steps, written.steps);
      expect(read.millis, written.millis);
    });

    test('refuses a trace with mismatched steps and costs', () {
      expect(
        () => StepTimeTrace.fromJson(<String, Object?>{
          'every': 1,
          'steps': <int>[1, 2],
          'millis': <double>[1.0],
        }),
        throwsA(isA<StepTimeTraceFormatException>()),
      );
    });

    test('refuses a trace sampled every no steps', () {
      expect(
        () => StepTimeTrace.fromJson(<String, Object?>{
          'every': 0,
          'steps': <int>[],
          'millis': <double>[],
        }),
        throwsA(isA<StepTimeTraceFormatException>()),
      );
    });

    test('refuses a document missing its steps or its costs', () {
      expect(
        () => StepTimeTrace.fromJson(<String, Object?>{'every': 1}),
        throwsA(isA<StepTimeTraceFormatException>()),
      );
    });
  });
}
