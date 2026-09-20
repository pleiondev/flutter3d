/// `ls-i-00`'s controller, driven with no window — the same headless
/// discipline `flutter3d_lab_pendulum`'s own panel test uses for
/// `PendulumLabPanel`.
library;

import 'package:flutter3d_lab_twin/src/twin_dashboard_panel.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DataSourceRegistry sources;
  late TwinWhatIfController controller;

  setUp(() {
    sources = DataSourceRegistry(<String, EduDataSource>{
      'spindle-temp': SamplerDataSource(
        (step) => <String, Object?>{'value': 60.0 + step.toDouble()},
      ),
    });
    controller = TwinWhatIfController(
      dataSources: sources,
      sourceName: 'spindle-temp',
      bindingPath: 'value',
      overrideValue: 90.0,
      aheadSteps: 10,
    );
  });

  test('samples the live source and publishes the reading', () {
    controller.sampleAndRecord(0);
    expect(controller.reading.value, 60.0);

    controller.sampleAndRecord(1);
    expect(controller.reading.value, 61.0);
  });

  test('cannot branch before anything has been recorded', () {
    expect(controller.triggerWhatIf(), isFalse);
    expect(controller.branch.value, isNull);
  });

  test(
    'branches from the last recorded step without touching earlier readings',
    () {
      for (var step = 0; step < 20; step++) {
        controller.sampleAndRecord(step);
      }
      // The reading right before the branch, checked so the assertion below
      // that it survives really is a before/after comparison and not a
      // coincidence of both being unset.
      expect(controller.reading.value, 79.0);

      final triggered = controller.triggerWhatIf();
      expect(triggered, isTrue);

      final branch = controller.branch.value;
      expect(branch, isNotNull);
      final (trace, branchPoint) = branch!;
      expect(branchPoint, 19);

      // Everything up to and including the branch point is the real
      // history, unchanged.
      for (var step = 0; step <= branchPoint; step++) {
        expect(trace.valueAt(step), <String, Object?>{
          'value': 60.0 + step.toDouble(),
        });
      }
      // Everything after it is the override, not a continuation of the
      // sampler's own sweep.
      for (var step = branchPoint + 1; step <= branchPoint + 10; step++) {
        expect(trace.valueAt(step), <String, Object?>{'value': 90.0});
      }
    },
  );

  test('swaps the live source so ticks after the branch read the override', () {
    for (var step = 0; step < 5; step++) {
      controller.sampleAndRecord(step);
    }
    controller.triggerWhatIf();

    controller.sampleAndRecord(5);
    expect(controller.reading.value, 90.0);
    controller.sampleAndRecord(6);
    expect(controller.reading.value, 90.0);
  });

  test('a source with no reading yet publishes null, not a stale value', () {
    final emptySources = DataSourceRegistry(<String, EduDataSource>{});
    final emptyController = TwinWhatIfController(
      dataSources: emptySources,
      sourceName: 'missing',
      bindingPath: 'value',
    );
    emptyController.sampleAndRecord(0);
    expect(emptyController.reading.value, isNull);
  });
}
