/// `ls-i-02`'s own panel: the operator's own dashboard (`wg-02`'s own
/// scene), reading whatever [IncidentReplayController] scrubbed to rather
/// than a live feed.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'incident_scenario.dart';

/// Scrubs a pre-recorded [DataSourceTrace] between named moments — `edu-05`'s
/// own trace read back by [DataSourceTrace.valueAt], which a what-if run
/// would branch rather than only read. This one never writes: an incident
/// that already happened is
/// read, not branched, so [DataSourceTrace.record]/`branchAt` never appear
/// here at all — [trace] is built once, by [recordSpindleOverheatIncident],
/// before this controller ever sees it.
final class IncidentReplayController {
  /// A replay of [trace] standing on the first of [moments], with the
  /// reading under [bindingPath] already read; [moments] must not be empty.
  IncidentReplayController({
    required this.trace,
    required this.moments,
    required this.bindingPath,
  }) : assert(
         moments.isNotEmpty,
         'a replay with no moments has nowhere to scrub to',
       ) {
    _apply();
  }

  /// The recorded incident, read and never written.
  final DataSourceTrace trace;

  /// The named points of the incident the replay steps between, in the
  /// order a scrub visits them.
  final List<IncidentMoment> moments;

  /// Which value in each recorded step the panel shows: the key into what
  /// [DataSourceTrace.valueAt] returns.
  final String bindingPath;

  /// Which of [moments] is current, from zero. Move it with [next],
  /// [previous] or [jumpTo], which also refresh [reading]; writing it
  /// directly does not.
  int index = 0;

  /// The moment the replay stands on.
  IncidentMoment get current => moments[index];

  /// Whether [previous] has anywhere to go; the panel greys its button out.
  bool get isFirst => index <= 0;

  /// Whether [next] has anywhere to go; the panel greys its button out.
  bool get isLast => index >= moments.length - 1;

  /// What [trace] recorded at [current]'s own step — [ValueListenable]
  /// rather than a plain getter, the same door `TwinDashboardPanel`'s own
  /// `controller.reading` already opens for a `ValueListenableBuilder`.
  final ValueNotifier<Object?> reading = ValueNotifier<Object?>(null);

  /// Which moment is current — a second notifier rather than folding the
  /// caption into [reading]'s own value, because a widget showing the
  /// caption and a widget showing the number are two different questions
  /// about the same scrub position.
  final ValueNotifier<int> momentIndex = ValueNotifier<int>(0);

  /// Steps to the moment after [current]; on the last one, does nothing.
  void next() {
    if (isLast) return;
    index++;
    _apply();
  }

  /// Steps to the moment before [current]; on the first one, does nothing.
  void previous() {
    if (isFirst) return;
    index--;
    _apply();
  }

  /// Scrubs straight to [target] — `ls-i-02`'s own "открывает записанный
  /// сбой по ссылке": a URL naming a moment directly, the same query-param
  /// door every other app in this tree already answers. Out-of-range is a
  /// no-op, the same forgiveness `LessonPlayer`'s own clamped `start`
  /// already extends to a bad step index.
  void jumpTo(int target) {
    if (target < 0 || target >= moments.length) return;
    index = target;
    _apply();
  }

  void _apply() {
    momentIndex.value = index;
    reading.value = trace.valueAt(current.step)?[bindingPath];
  }
}

/// The `WidgetSurface` `wg-02`'s own operator panel draws — the live
/// reading `OperatorPanel` (`apps/flutter3d_demo_dungeon`) already proved,
/// with the moment's own caption underneath it: the "что случилось" half of
/// `ls-i-02`'s own acceptance line, which a bare number cannot say by
/// itself.
final class IncidentPanel extends StatelessWidget {
  /// The panel showing wherever [controller] has scrubbed to.
  const IncidentPanel({super.key, required this.controller});

  /// The replay the panel reads its number and caption from; it rebuilds on
  /// the controller's notifiers and never moves it.
  final IncidentReplayController controller;

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
              fontSize: 16.0,
              letterSpacing: 2.0,
            ),
          ),
          const SizedBox(height: 6.0),
          ValueListenableBuilder<Object?>(
            valueListenable: controller.reading,
            builder: (context, value, _) => Text(
              value is num ? '${value.toStringAsFixed(1)} °C' : '— °C',
              style: const TextStyle(
                color: Color(0xFFE7C46E),
                fontFamily: 'monospace',
                fontSize: 34.0,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 8.0),
          ValueListenableBuilder<int>(
            valueListenable: controller.momentIndex,
            builder: (context, index, _) {
              final moment = controller.moments[index];
              return Column(
                children: <Widget>[
                  Text(
                    moment.label,
                    style: const TextStyle(
                      color: Color(0xFFFFB74D),
                      fontFamily: 'monospace',
                      fontSize: 13.0,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4.0),
                  Text(
                    moment.caption,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFB8C0CC),
                      fontSize: 11.0,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    ),
  );
}
