/// `DataSourceTrace.firstStepWhere` — `ls-i-02`'s own "an engineer...
/// scrubs the timeline to the moment the lesson named," answered as a real
/// question over a recorded trace rather than assumed to need a screen
/// first.
///
///     dart test test/data_source_trace_test.dart
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

DataSourceTrace _readingRisingPast(int step, double threshold) {
  final trace = DataSourceTrace();
  for (var s = 1; s <= 100; s++) {
    // A calm reading, then a real spike at [step] and everything after —
    // an "incident," not a single glitchy sample.
    final value = s < step ? 20.0 : threshold + 5.0;
    trace.record(s, <String, Object?>{'value': value});
  }
  return trace;
}

void main() {
  test('finds the first step a threshold is crossed, not a later one', () {
    final trace = _readingRisingPast(40, 80.0);
    final found = trace.firstStepWhere('value', (v) => v is num && v > 80.0);
    expect(found, 40);
  });

  test('null when the reading never crosses the threshold at all', () {
    final trace = _readingRisingPast(40, 80.0);
    final found = trace.firstStepWhere('value', (v) => v is num && v > 1000.0);
    expect(found, isNull);
  });

  test('reads the exact path named, not some other field at the same step', () {
    final trace = DataSourceTrace();
    trace.record(1, <String, Object?>{'temperature': 20.0, 'pressure': 99.0});
    trace.record(2, <String, Object?>{'temperature': 20.0, 'pressure': 150.0});

    expect(trace.firstStepWhere('pressure', (v) => v is num && v > 100.0), 2);
    expect(
      trace.firstStepWhere('temperature', (v) => v is num && v > 100.0),
      isNull,
    );
  });

  test('an empty trace finds nothing, rather than throwing', () {
    expect(DataSourceTrace().firstStepWhere('value', (_) => true), isNull);
  });
}
