/// `ls-i-02`'s controller, driven with no window — the same headless
/// discipline `flutter3d_lab_twin`'s own panel test uses for
/// `TwinWhatIfController`.
library;

import 'package:flutter3d_lab_incident/src/incident_panel.dart';
import 'package:flutter3d_lab_incident/src/incident_scenario.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('recordSpindleOverheatIncident', () {
    test('is dense: every step from zero through the trace length', () {
      final trace = recordSpindleOverheatIncident();
      expect(trace.length, spindleOverheatTraceLength + 1);
      expect(trace.steps.first, 0);
      expect(trace.steps.last, spindleOverheatTraceLength);
    });

    test('reads back exactly what the closed-form curve says', () {
      final trace = recordSpindleOverheatIncident();
      for (final step in <int>[0, 50, 99, 130, 175, 219, 220, 260]) {
        expect(trace.valueAt(step), <String, Object?>{
          'value': spindleTemperatureAt(step),
        }, reason: 'step $step');
      }
    });

    test('rises above normal, then comes back down to it', () {
      expect(spindleTemperatureAt(20), 60.0, reason: 'before the anomaly');
      expect(
        spindleTemperatureAt(130),
        greaterThan(60.0),
        reason: 'mid-anomaly',
      );
      expect(spindleTemperatureAt(240), 60.0, reason: 'resolved');
    });
  });

  group('spindleOverheatMoments', () {
    test('every moment names a step the trace actually recorded', () {
      final trace = recordSpindleOverheatIncident();
      for (final moment in spindleOverheatMoments) {
        expect(
          trace.valueAt(moment.step),
          isNotNull,
          reason: '${moment.label} names step ${moment.step}',
        );
      }
    });

    test('in order, earliest first', () {
      for (var i = 1; i < spindleOverheatMoments.length; i++) {
        expect(
          spindleOverheatMoments[i].step,
          greaterThan(spindleOverheatMoments[i - 1].step),
        );
      }
    });
  });

  group('IncidentReplayController', () {
    late IncidentReplayController controller;

    setUp(() {
      controller = IncidentReplayController(
        trace: recordSpindleOverheatIncident(),
        moments: spindleOverheatMoments,
        bindingPath: spindleTempBindingPath,
      );
    });

    test('starts on the first moment, already applied', () {
      expect(controller.index, 0);
      expect(controller.current, spindleOverheatMoments.first);
      expect(controller.reading.value, spindleTemperatureAt(20));
      expect(controller.isFirst, isTrue);
    });

    test('next moves forward and reads that moment\'s own value', () {
      controller.next();
      expect(controller.current, spindleOverheatMoments[1]);
      expect(controller.reading.value, spindleTemperatureAt(130));
      expect(controller.isFirst, isFalse);
    });

    test('previous moves back', () {
      controller.next();
      controller.next();
      controller.previous();
      expect(controller.current, spindleOverheatMoments[1]);
    });

    test('next stops at the last moment rather than wrapping', () {
      for (var i = 0; i < spindleOverheatMoments.length + 3; i++) {
        controller.next();
      }
      expect(controller.index, spindleOverheatMoments.length - 1);
      expect(controller.isLast, isTrue);
    });

    test('previous stops at the first rather than going negative', () {
      controller.previous();
      controller.previous();
      expect(controller.index, 0);
      expect(controller.isFirst, isTrue);
    });

    test('jumpTo scrubs straight to a named moment — the "open by link" '
        'door', () {
      controller.jumpTo(2);
      expect(controller.current, spindleOverheatMoments[2]);
      expect(controller.reading.value, spindleTemperatureAt(175));
    });

    test('jumpTo outside the moment list is refused, not clamped', () {
      controller.jumpTo(1);
      controller.jumpTo(99);
      expect(controller.index, 1, reason: 'the bad jump changed nothing');
      controller.jumpTo(-1);
      expect(controller.index, 1);
    });

    test('momentIndex tracks the same scrub position as current', () {
      controller.jumpTo(3);
      expect(controller.momentIndex.value, 3);
    });
  });
}
