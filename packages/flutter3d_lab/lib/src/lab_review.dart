import 'package:flutter3d_sim/flutter3d_sim.dart';

/// The step a student's own recorded parameter first differs from the
/// assignment's — `doc/lesson-scenarios-plan.md`'s own wording for
/// `ls-e-01`'s acceptance: "преподаватель видит на шкале rp-02, на каком
/// шаге студент выставил длину, отличную от задания".
final class LabDivergence {
  const LabDivergence({
    required this.step,
    required this.assigned,
    required this.actual,
  });

  final int step;
  final double assigned;
  final double actual;
}

/// Compares [assignment] against [student] step by step on [path] and
/// answers the first step they disagree, or null when the student never
/// touched the parameter the assignment set.
///
/// **Not [DigestTrace.divergenceFrom].** `rp-01`'s own mechanism answers
/// "did the simulation state end up different" — true only after physics
/// has propagated an input difference through at least one checkpoint
/// interval, so it names a step *after* the one a student actually acted
/// on. A teacher reviewing a lab wants the input itself, which is exactly
/// what `DataSourceTrace` already recorded — one comparison of two traces,
/// not a second simulation run to diff against.
LabDivergence? firstLabDivergence(
  DataSourceTrace assignment,
  DataSourceTrace student, {
  required String path,
  double tolerance = 1e-9,
}) {
  for (final step in student.steps) {
    final actual = _numberAt(student, step, path);
    final assigned = _numberAt(assignment, step, path);
    if (actual == null || assigned == null) continue;
    if ((actual - assigned).abs() > tolerance) {
      return LabDivergence(step: step, assigned: assigned, actual: actual);
    }
  }
  return null;
}

double? _numberAt(DataSourceTrace trace, int step, String path) {
  final value = trace.valueAt(step)?[path];
  return value is num ? value.toDouble() : null;
}
