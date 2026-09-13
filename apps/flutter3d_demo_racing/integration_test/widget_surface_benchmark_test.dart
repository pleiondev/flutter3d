/// `wg-00`'s redraw-cost measurement, on the one platform `flutter test`
/// cannot reach: an actual device.
///
///     flutter test integration_test/widget_surface_benchmark_test.dart -d <device-id>
///
/// **Mirrors
/// `packages/flutter3d_session/test/widget_surface_pipeline_benchmark_test.dart`
/// on purpose, rather than importing it** — see
/// `apps/flutter3d_demo_platformer/integration_test/parity_test.dart` for why
/// that shape is used across this repository's device probes. See
/// `doc/tooling-plan.md` `wg-00` for what this answers.
library;

import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter3d_session/flutter3d_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

Widget _panel(int value) => ColoredBox(
  color: Color(0xFF000000 | (value * 4099) % 0xFFFFFF),
  child: Center(
    child: Text(
      'reading: $value',
      textDirection: TextDirection.ltr,
      style: const TextStyle(
        color: Color(0xFFFFFFFF),
        fontSize: 32,
        fontWeight: FontWeight.bold,
      ),
    ),
  ),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('redraw cost of a 512x512 surface on a real device', (
    WidgetTester tester,
  ) async {
    const size = 512;
    const iterations = 60;

    final notifier = ValueNotifier<int>(0);
    final pipeline = WidgetSurfacePipeline(
      width: size,
      height: size,
      child: ValueListenableBuilder<int>(
        valueListenable: notifier,
        builder: (context, value, _) => _panel(value),
      ),
    );
    addTearDown(pipeline.dispose);
    addTearDown(notifier.dispose);

    final dirty = Stopwatch();
    for (var i = 1; i <= iterations; i++) {
      notifier.value = i;
      dirty.start();
      pipeline.redrawIfDirty();
      final image = await pipeline.currentImage();
      await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      dirty.stop();
    }

    final skipped = Stopwatch();
    for (var i = 0; i < iterations; i++) {
      skipped.start();
      pipeline.redrawIfDirty();
      skipped.stop();
    }

    final dirtyMs = dirty.elapsedMicroseconds / iterations / 1000.0;
    final skippedMs = skipped.elapsedMicroseconds / iterations / 1000.0;

    // ignore: avoid_print
    print(
      'wg-00 512x512 (device): dirty redraw ${dirtyMs.toStringAsFixed(3)} '
      'ms/frame, skip ${skippedMs.toStringAsFixed(4)} ms/frame '
      '(n=$iterations each)',
    );
  });
}
