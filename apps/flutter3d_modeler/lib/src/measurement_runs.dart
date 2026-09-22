/// The measured camera orbit and the edit-convert-upload churn loop, ticked
/// together because both finish into the same one-line report `_onTick`
/// prints — see `main.dart`, whose own unconditional `setState` this class
/// does not touch: repainting the panel after a drag or a scrub stays that
/// method's job regardless of whether a run is going.
library;

import 'package:flutter/foundation.dart' show debugPrint;

import 'churn_run.dart';
import 'orbit_run.dart';

/// Owns [OrbitRun] and [ChurnRun] for the run a build asked for with
/// `--dart-define=orbit=`/`--dart-define=churn=true`, and turns one tick's
/// measurement into whatever the finished run has to say.
class MeasurementRuns {
  MeasurementRuns({required this.what});

  /// What was measured, named once at construction — the cube, an asset's
  /// path, or the stress lattice's own triangle count.
  final String what;

  /// The measured camera move, when the build asked for one.
  OrbitRun? orbit;

  /// The edit-convert-upload loop, when the build asked for one.
  ChurnRun? churn;

  /// Milliseconds from opening the device to the first frame being ready,
  /// set once by the opening code and read here to build the report line.
  int openedInMs = 0;

  /// One frame's worth of both runs.
  ///
  /// Returns the finished report the moment [orbit] completes — printed to
  /// the console the same frame — or null on every other tick, including
  /// every tick where no run was ever asked for.
  String? step(int elapsedMicros, int? renderMicros) {
    churn?.step();
    final run = orbit;
    if (run == null) return null;
    run.step(elapsedMicros, renderMicros);
    if (!run.done) return null;
    // To stderr through `debugPrint`, which is what reaches a browser's
    // console as well as a terminal — the same line on every platform this
    // is measured on.
    final said = OrbitRun.describe(run.report(), what: what);
    final ranChurn = churn;
    final whole = ranChurn == null
        ? '$said\n  opened in    $openedInMs ms'
        : '$said\n  opened in    $openedInMs ms\n${ranChurn.describe()}';
    debugPrint(whole);
    churn = null;
    orbit = null;
    return whole;
  }
}
