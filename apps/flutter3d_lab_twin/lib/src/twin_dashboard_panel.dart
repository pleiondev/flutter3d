/// `ls-i-00`'s own panel: a live sensor reading, and the one button that
/// turns "what if this had been hotter" into a real branch rather than a
/// rewritten one.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

/// Drives one `edu_data_source`'s live reading and, on request, a "what if"
/// branch of its recorded [DataSourceTrace] — `doc/lesson-scenarios-plan.md`'s
/// own wording for `ls-i-00`: "ветка от текущего шага с подменённым
/// значением", not a rewind. [DataSourceTrace.branchAt] already proves the
/// property this needs (the branch never touches the trace it forked from,
/// `run_timeline_data_source_test.dart`); this controller is the thinnest
/// caller of it a widget can drive.
final class TwinWhatIfController {
  TwinWhatIfController({
    required this.dataSources,
    required this.sourceName,
    required this.bindingPath,
    this.overrideValue = 90.0,
    this.aheadSteps = 120,
  });

  final DataSourceRegistry dataSources;

  /// Which `edu_data_source` in [dataSources] the branch swaps.
  final String sourceName;

  /// The payload key a reading is read back by — `resolveBindings`'s own
  /// `path`, `"value"` for this app's one sensor.
  final String bindingPath;

  final double overrideValue;

  /// How far past the branch point the projected "what if" trace is drawn —
  /// a display choice, not a limit on how long the override actually lasts:
  /// [dataSources] is swapped for good, this only bounds how much of the
  /// branch a caller renders ahead of time.
  final int aheadSteps;

  final ValueNotifier<Object?> reading = ValueNotifier<Object?>(null);

  final _trace = DataSourceTrace();
  int _lastStep = -1;

  /// The branch and the step it forked from, once triggered — null before,
  /// so a widget can tell "no what-if yet" from "the what-if reads back to
  /// the same value".
  final ValueNotifier<(DataSourceTrace, int)?> branch =
      ValueNotifier<(DataSourceTrace, int)?>(null);

  /// Samples [sourceName] at [step], writes the result into [reading], and
  /// records it into the trace a future [triggerWhatIf] branches — the two
  /// things a caller does every tick, `RewindBuffer`'s own doc comment's
  /// discipline ("record alongside simulating, not after").
  void sampleAndRecord(int step) {
    final source = dataSources[sourceName];
    final payload = source?.sample(step);
    final value = payload is Map ? payload[bindingPath] : null;
    reading.value = value;
    _trace.record(step, <String, Object?>{bindingPath: value});
    _lastStep = step;
  }

  /// Branches from the last recorded step and swaps [sourceName] so every
  /// tick after this one reads [overrideValue] too — the order
  /// `run_timeline_data_source_test.dart` proves matters: the branch is
  /// built from what already happened, then the source changes for what
  /// has not.
  bool triggerWhatIf() {
    if (_lastStep < 0) return false;
    final branchPoint = _lastStep;
    final branched = _trace.branchAt(
      branchPoint,
      branchPoint + aheadSteps,
      (s) => <String, Object?>{bindingPath: overrideValue},
    );
    dataSources.replace(
      sourceName,
      SamplerDataSource((_) => <String, Object?>{bindingPath: overrideValue}),
    );
    branch.value = (branched, branchPoint);
    return true;
  }
}

/// The dashboard `WidgetSurface` hosts: the live reading, and the button
/// that forks it.
final class TwinDashboardPanel extends StatelessWidget {
  const TwinDashboardPanel({super.key, required this.controller});

  final TwinWhatIfController controller;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFF15181C),
    child: Padding(
      padding: const EdgeInsets.all(14.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Text(
            'SPINDLE TEMP',
            style: TextStyle(
              color: Color(0xFF8FA0B3),
              fontFamily: 'monospace',
              fontSize: 18.0,
              letterSpacing: 2.0,
            ),
          ),
          const SizedBox(height: 8.0),
          ValueListenableBuilder<Object?>(
            valueListenable: controller.reading,
            builder: (context, value, _) => Text(
              value is num ? '${value.toStringAsFixed(1)} °C' : '— °C',
              style: const TextStyle(
                color: Color(0xFFE7C46E),
                fontFamily: 'monospace',
                fontSize: 40.0,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 12.0),
          ValueListenableBuilder<(DataSourceTrace, int)?>(
            valueListenable: controller.branch,
            builder: (context, branched, _) => branched == null
                ? _WhatIfButton(onTap: controller.triggerWhatIf)
                : Text(
                    'branch: ${controller.overrideValue.toStringAsFixed(0)} '
                    '°C from step ${branched.$2}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFFFB74D),
                      fontFamily: 'monospace',
                      fontSize: 13.0,
                    ),
                  ),
          ),
        ],
      ),
    ),
  );
}

final class _WhatIfButton extends StatelessWidget {
  const _WhatIfButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
      decoration: BoxDecoration(
        color: const Color(0xFF283040),
        borderRadius: BorderRadius.circular(10.0),
      ),
      child: const Text(
        'what if hotter?',
        style: TextStyle(color: Color(0xFFE6EAF0), fontSize: 14.0),
      ),
    ),
  );
}
