/// `wg-02`'s second demo scene — the operator panel `tpl-04`'s own
/// `twin.json` now hosts (`template_widgets.dart`'s `'twin-dashboard'`
/// entry). `edu-05`'s own `SamplerDataSource`/`WidgetSurface` wiring, driving
/// a real widget rather than a description of one.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_session/flutter3d_session.dart';
import 'package:flutter3d_template_app/src/operator_panel.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sixteen by nine: only `WidgetSurface`'s own upload path needs a device
/// here, the same reason `run_cubit_test.dart` picks a small one.
GraphicsDevice _device() => CpuDevice(
  width: 16,
  height: 9,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OperatorPanel', () {
    testWidgets('shows the reading it is handed', (tester) async {
      final reading = ValueNotifier<double>(41.2);
      await tester.pumpWidget(
        MaterialApp(
          home: OperatorPanel(label: 'spindle temp', unit: '°C', value: reading),
        ),
      );
      expect(find.text('41.2°C'), findsOneWidget);
      expect(find.text('SPINDLE TEMP'), findsOneWidget);
    });

    testWidgets('redraws when the value changes underneath it', (tester) async {
      final reading = ValueNotifier<double>(20.0);
      await tester.pumpWidget(
        MaterialApp(home: OperatorPanel(label: 'temp', unit: '°C', value: reading)),
      );
      expect(find.text('20.0°C'), findsOneWidget);

      reading.value = 63.4;
      await tester.pump();

      expect(find.text('63.4°C'), findsOneWidget);
      expect(find.text('20.0°C'), findsNothing);
    });
  });

  group('wg-02 + edu-05: a real SamplerDataSource drives the panel', () {
    testWidgets(
      'stepping the source updates a live WidgetSurface\'s own texture',
      (tester) async {
        // `edu-05`'s own honest source, not a network stack: a deterministic
        // function of the step, the one `EduDataSource` implementation this
        // session can prove without a broker.
        final source = SamplerDataSource(
          (step) => 20.0 + 5.0 * math.sin(step / 10.0),
        );

        final reading = ValueNotifier<double>(
          (source.sample(0)! as num).toDouble(),
        );

        final device = _device();
        final surface = WidgetSurface(
          device: device,
          child: OperatorPanel(label: 'spindle temp', unit: '°C', value: reading),
        );
        addTearDown(surface.dispose);

        // `tick()` reaches `WidgetSurfacePipeline.currentImage()`, which
        // asks the engine to rasterise a frame — `wg-01`'s own test found
        // this needs `tester.runAsync`, the same reason repeated here.
        //
        // The very first frame is already drawn by the pipeline's own
        // constructor (`WidgetSurfacePipeline`'s docstring), so `tick()`'s
        // forced first upload moves the mesh's texture, not `redrawCount` —
        // `wg-01`'s own test found this the same way. What matters here is
        // the texture the panel's starting reading actually reaches.
        final before = surface.node.material.albedo;
        await tester.runAsync(surface.tick);
        expect(
          surface.node.material.albedo,
          isNot(same(before)),
          reason: 'the first frame the pipeline already drew reaches the mesh',
        );

        final steadyCount = surface.redrawCount;
        await tester.runAsync(surface.tick);
        expect(
          surface.redrawCount,
          steadyCount,
          reason: 'nothing changed between these two ticks',
        );

        // `resolveBindings` reads `edu_step.bindings`; this drives the same
        // source directly, the way `tpl-04`'s own frame loop would after
        // resolving `source: "lathe-broker"` off the level once.
        for (var step = 1; step <= 20; step++) {
          reading.value = (source.sample(step)! as num).toDouble();
        }
        await tester.runAsync(surface.tick);

        expect(
          surface.redrawCount,
          greaterThan(steadyCount),
          reason: 'twenty real samples moved the panel, so the surface '
              'above it had something to redraw',
        );
      },
    );
  });
}
