import 'package:flutter3d_lab/flutter3d_lab.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

DataSourceTrace _traceOf(List<double> lengths, {String path = 'length'}) {
  final trace = DataSourceTrace();
  for (var step = 0; step < lengths.length; step++) {
    trace.record(step, <String, Object?>{path: lengths[step]});
  }
  return trace;
}

void main() {
  test('null when the student never touched the assigned parameter', () {
    final assignment = _traceOf(<double>[1.2, 1.2, 1.2, 1.2]);
    final student = _traceOf(<double>[1.2, 1.2, 1.2, 1.2]);

    expect(
      firstLabDivergence(assignment, student, path: 'length'),
      isNull,
    );
  });

  test('names the exact step and both values where they first disagree', () {
    final assignment = _traceOf(<double>[1.2, 1.2, 1.2, 1.2, 1.2]);
    final student = _traceOf(<double>[1.2, 1.2, 1.5, 1.5, 1.5]);

    final divergence = firstLabDivergence(assignment, student, path: 'length');
    expect(divergence, isNotNull);
    expect(divergence!.step, 2);
    expect(divergence.assigned, 1.2);
    expect(divergence.actual, 1.5);
  });

  test('a student who overshoots and returns still diverges at the first step', () {
    final assignment = _traceOf(<double>[1.2, 1.2, 1.2, 1.2]);
    final student = _traceOf(<double>[1.2, 0.8, 1.2, 1.2]);

    final divergence = firstLabDivergence(assignment, student, path: 'length');
    expect(divergence!.step, 1);
  });

  test('a difference smaller than tolerance does not count', () {
    final assignment = _traceOf(<double>[1.2]);
    final student = _traceOf(<double>[1.2 + 1e-12]);

    expect(
      firstLabDivergence(assignment, student, path: 'length'),
      isNull,
    );
  });

  test('a step the assignment never recorded is skipped, not a false positive', () {
    final assignment = DataSourceTrace()
      ..record(0, <String, Object?>{'length': 1.2})
      ..record(2, <String, Object?>{'length': 1.2});
    final student = DataSourceTrace()
      ..record(0, <String, Object?>{'length': 1.2})
      ..record(1, <String, Object?>{'length': 1.2})
      ..record(2, <String, Object?>{'length': 1.2});

    expect(
      firstLabDivergence(assignment, student, path: 'length'),
      isNull,
    );
  });
}
