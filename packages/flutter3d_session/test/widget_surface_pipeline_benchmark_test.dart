/// `wg-00`'s other half: what a redraw costs, and what skipping one costs.
///
///     flutter test test/widget_surface_pipeline_benchmark_test.dart
///     flutter test --platform chrome test/widget_surface_pipeline_benchmark_test.dart
///     flutter test --platform chrome --wasm test/widget_surface_pipeline_benchmark_test.dart
///
/// **Prints rather than asserts a threshold.** A number that has to stay
/// under a fixed millisecond count is a number this file would have to know
/// the machine it is about to run on, and the point of `wg-00` was to find
/// that out rather than assume it — the same reason
/// `flutter3d_sim/test/parity_test.dart` records a trace instead of a
/// tolerance. What is asserted is only that a redraw costs measurably more
/// than skipping one, which is the whole argument for `redrawIfDirty`
/// existing at all; the actual milliseconds go into `doc/tooling-plan.md` §8
/// by hand, once per platform, the way `rp-00`'s table did.
library;

import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter3d_session/flutter3d_session.dart';
import 'package:flutter_test/flutter_test.dart';

/// Text and a coloured background — not a bare [ColoredBox], because a sign
/// or a HUD readout is what `wg-01` will actually draw, and text is where a
/// rasteriser spends time a flat fill does not.
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
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'redraw cost of a 512x512 surface, dirty and skipped',
    (tester) async {
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

      // `Image.toImage()`/`toByteData()` resolve through a real engine
      // callback rather than a microtask, and `flutter_test` runs a test body
      // inside a fake-async zone that never lets one of those fire — the
      // benchmark hangs at its own timeout otherwise, having measured
      // nothing. `runAsync` is the documented escape hatch.
      final dirtyMs = await tester.runAsync(() async {
        final dirty = Stopwatch();
        for (var i = 1; i <= iterations; i++) {
          notifier.value = i;
          expect(pipeline.isDirty, isTrue);
          dirty.start();
          final drew = pipeline.redrawIfDirty();
          final image = await pipeline.currentImage();
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
          image.dispose();
          dirty.stop();
          expect(drew, isTrue);
        }
        return dirty.elapsedMicroseconds / iterations / 1000.0;
      });

      final skipped = Stopwatch();
      for (var i = 0; i < iterations; i++) {
        skipped.start();
        final drew = pipeline.redrawIfDirty();
        skipped.stop();
        expect(drew, isFalse, reason: 'nothing changed between skips');
      }

      final skippedMs = skipped.elapsedMicroseconds / iterations / 1000.0;
      expect(
        dirtyMs,
        isNotNull,
        reason: 'runAsync only returns null if it never ran',
      );

      // ignore: avoid_print
      print(
        'wg-00 512x512: dirty redraw ${dirtyMs!.toStringAsFixed(3)} ms/frame, '
        'skip ${skippedMs.toStringAsFixed(4)} ms/frame '
        '(n=$iterations each)',
      );

      expect(
        dirtyMs,
        greaterThan(skippedMs),
        reason:
            'a redraw that does the same work as a skip is a dirty flag doing '
            'nothing — the whole argument for redrawIfDirty existing',
      );
    },
    // Rasterising sixty 512x512 frames plus their readback is real work, and
    // this file's job is to measure it rather than to be fast.
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
