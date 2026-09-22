/// `ls-i-02`'s own recorded incident — synthetic, and named as such: a
/// spindle temperature that rises past normal, an operator response, and a
/// return to normal, built as a dense per-step [DataSourceTrace] the same
/// way any real run's own `edu_data_source` reading would be recorded
/// (`edu-05`'s own mechanism), not as a live sample this screen improvises.
///
/// **No real machine behind this.** `doc/lesson-scenarios-plan.md`'s
/// `ls-i-02` names no specific factory or sensor — unlike `ls-e-00`'s own
/// `prep-00`, closing this scenario never needed one: a plausible, clearly
/// synthetic temperature curve is what `flutter3d_lab_twin`'s own
/// `spindle-temp` sampler already stood in for the same real object, and an
/// incident replay needs a shape to scrub through, not a real factory's own
/// data.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';

/// The reading `edu-00` §9's own `resolveBindings` would read back —
/// `flutter3d_lab_twin`'s own key for the same synthetic sensor.
const String spindleTempBindingPath = 'value';

/// The synthetic spindle temperature at [step] — 60°C at rest, a rise
/// starting at step 100 that would keep climbing past 95°C if nothing
/// changed, an operator's own response bending the curve back down from
/// step 160, and rest again by step 220. A closed-form function rather than
/// anything read live, because a recorded incident is read back the same
/// way twice — the same reason [DataSourceTrace] itself exists.
double spindleTemperatureAt(int step) {
  if (step < 100) return 60.0;
  if (step < 160) return 60.0 + (step - 100) * 0.6;
  if (step < 220) {
    final peak = 60.0 + 60 * 0.6;
    return peak - (step - 160) * 0.6;
  }
  return 60.0;
}

/// The last step this incident's trace is recorded through — comfortably
/// past every [spindleOverheatMoments] entry, so [DataSourceTrace.valueAt]
/// never answers null for a moment this scenario actually names.
const int spindleOverheatTraceLength = 260;

/// Records [spindleTemperatureAt] into a real [DataSourceTrace], one step at
/// a time — the same `record` call a live run's own sampling loop makes
/// (`flutter3d_lab_twin`'s own `_onTick`), just run once up front rather
/// than on a ticker, since what this screen shows is a recording, not a
/// live feed.
DataSourceTrace recordSpindleOverheatIncident() {
  final trace = DataSourceTrace();
  for (var step = 0; step <= spindleOverheatTraceLength; step++) {
    trace.record(step, <String, Object?>{
      spindleTempBindingPath: spindleTemperatureAt(step),
    });
  }
  return trace;
}

/// One named point in the incident an engineer scrubs to by name — a step
/// into the trace [recordSpindleOverheatIncident] built, and the two lines
/// `ls-i-02`'s own acceptance line asks a lesson to walk through: what the
/// sensor showed, and what happened.
typedef IncidentMoment = ({int step, String label, String caption});

/// `ls-i-02`'s own four-step narration — "что показывал датчик → что
/// сделал оператор → что случилось", one moment per arrow.
const List<IncidentMoment> spindleOverheatMoments = <IncidentMoment>[
  (
    step: 20,
    label: 'Normal operation',
    caption:
        'The spindle temperature sensor reads 60°C — the machine\'s normal '
        'running temperature.',
  ),
  (
    step: 130,
    label: 'Anomaly detected',
    caption:
        'The reading has climbed well past normal and is still rising — '
        'already at 78°C, and climbing about six tenths of a degree every '
        'step.',
  ),
  (
    step: 175,
    label: 'Operator response',
    caption:
        'The operator sees the trend on this same panel and reduces the '
        'machine\'s load. The temperature stops climbing and starts to fall.',
  ),
  (
    step: 240,
    label: 'Resolved',
    caption:
        'The temperature is back to 60°C. The incident is over, and the '
        'machine is back to its normal running state.',
  ),
];
