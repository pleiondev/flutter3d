import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'spindle_temp.dart';

/// `spindle-temp`'s own reading, recorded step by step — `ls-i-00`'s own
/// "the value with no controller behind it," recorded the same way
/// `flutter3d_lab`'s own `PendulumLabRun` records a pendulum's length.
final class SpindleTempRun {
  factory SpindleTempRun({required int steps}) {
    final readings = DataSourceTrace();
    for (var step = 1; step <= steps; step++) {
      readings.record(step, <String, Object?>{'value': spindleTempAt(step)});
    }
    return SpindleTempRun._(readings, steps);
  }

  const SpindleTempRun._(this.readings, this.steps);

  /// What the sensor read at every step, [spindleTempAt]'s own values
  /// unless a branch (see [branchAt]) has substituted its own.
  final DataSourceTrace readings;

  final int steps;

  /// A "what if": a new run that reads exactly as this one did up to
  /// [atStep], then [temperatureAt] instead through [throughStep] —
  /// [DataSourceTrace.branchAt] underneath, a real branch rather than an
  /// overwrite, since [readings] here is left untouched. `ls-i-00`'s own
  /// acceptance: "changing the value creates a visible branch rather than
  /// overwriting history."
  SpindleTempRun branchAt(
    int atStep,
    int throughStep,
    double Function(int step) temperatureAt,
  ) => SpindleTempRun._(
    readings.branchAt(
      atStep,
      throughStep,
      (step) => <String, Object?>{'value': temperatureAt(step)},
    ),
    throughStep,
  );
}
