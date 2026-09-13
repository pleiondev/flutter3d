/// `edu-04`'s panel of parameters, proven the same way `wg-02`'s own
/// `OperatorPanel` was — without `tpl-04` to host it in yet: a real
/// `WidgetSurface`, a real `PendulumSimulation`, and a real
/// `DataSourceTrace` recording the one number a tap on it changes.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_demo_dungeon/src/pendulum_lab_panel.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_lab/flutter3d_lab.dart';
import 'package:flutter3d_session/flutter3d_session.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

GraphicsDevice _device() => CpuDevice(
  width: 16,
  height: 9,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PendulumLabPanel', () {
    testWidgets('shows the length it is handed', (tester) async {
      final length = ValueNotifier<double>(1.0);
      await tester.pumpWidget(
        MaterialApp(
          home: PendulumLabPanel(lengthMeters: length, onChangeLength: (_) {}),
        ),
      );
      expect(find.text('1.00 m'), findsOneWidget);
    });

    testWidgets('+ calls back with the length nudged up by step', (tester) async {
      final length = ValueNotifier<double>(1.0);
      double? changedTo;
      await tester.pumpWidget(
        MaterialApp(
          home: PendulumLabPanel(
            lengthMeters: length,
            onChangeLength: (v) => changedTo = v,
          ),
        ),
      );

      await tester.tap(find.text('+'));
      await tester.pump();

      expect(changedTo, closeTo(1.1, 1e-9));
    });

    testWidgets('a nudge past the upper bound clamps rather than overshoots', (
      tester,
    ) async {
      final length = ValueNotifier<double>(2.95);
      double? changedTo;
      await tester.pumpWidget(
        MaterialApp(
          home: PendulumLabPanel(
            lengthMeters: length,
            onChangeLength: (v) => changedTo = v,
            maxLength: 3.0,
          ),
        ),
      );

      await tester.tap(find.text('+'));
      await tester.pump();

      expect(changedTo, 3.0);
    });
  });

  group('edu-04: a tap on a real WidgetSurface changes a real pendulum, '
      'and it is recorded at the step it changed', () {
    testWidgets(
      'the full chain: tap on the surface -> PendulumSimulation.lengthMeters '
      'changes -> DataSourceTrace records it at that step, not before',
      (tester) async {
        final pendulum = PendulumSimulation(lengthMeters: 1.0);
        final trace = DataSourceTrace();
        var recordedStep = 0;
        trace.record(recordedStep, <String, Object?>{
          'length': pendulum.lengthMeters,
        });

        void increase() {
          pendulum.lengthMeters += 0.1;
          recordedStep++;
          trace.record(recordedStep, <String, Object?>{
            'length': pendulum.lengthMeters,
          });
        }

        // The button's own on-tap wiring (`+` nudges the length by `step`
        // and calls back) is proven above, on an ordinarily-pumped
        // `PendulumLabPanel`. What is not proven yet is the other half —
        // that a tap landing through a real `WidgetSurface`'s own pointer
        // path reaches a live callback that mutates a real
        // `PendulumSimulation` and is recorded. `widget_surface_test.dart`
        // already proves the raycast-to-UV half of that chain on exactly
        // this geometry (`Align(-0.5, 0.5)` over a `SizedBox(100, 60)` on a
        // 2.0 x 1.0 surface lands at UV `(0.25, 0.75)`), so this test
        // reuses that same known placement rather than re-deriving it —
        // `PendulumLabPanel`'s own button position, being centred by a
        // `Column`/`Row`, is not one this test can hand-compute honestly.
        final device = _device();
        final surface = WidgetSurface(
          device: device,
          width: 2.0,
          height: 1.0,
          child: Align(
            alignment: const Alignment(-0.5, 0.5),
            child: SizedBox(
              width: 100,
              height: 60,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: increase,
              ),
            ),
          ),
        );
        addTearDown(surface.dispose);

        const pointer = 7;
        surface.pipeline.announcePointer(pointer, added: true);
        surface.pipeline.dispatchAtUv(
          const Offset(0.25, 0.75),
          (local) => PointerDownEvent(pointer: pointer, position: local),
        );
        surface.pipeline.dispatchAtUv(
          const Offset(0.25, 0.75),
          (local) => PointerUpEvent(pointer: pointer, position: local),
        );
        surface.pipeline.announcePointer(pointer, added: false);

        expect(
          pendulum.lengthMeters,
          closeTo(1.1, 1e-9),
          reason: 'the tap reached the real callback through the real '
              'pipeline, not a copy of it',
        );
        expect(trace.length, 2, reason: 'exactly one change was recorded');
        expect(trace.valueAt(0)!['length'], 1.0);
        expect(
          trace.valueAt(1)!['length'],
          closeTo(1.1, 1e-9),
          reason: 'the new length is recorded at the step it changed, '
              'not retroactively at step zero',
        );
      },
    );
  });
}
