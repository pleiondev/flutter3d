/// This app's own `LessonScreen`, opened the way a person opens it: the real
/// `openDevice` (the software rasteriser, headless), the shipped tour, the
/// step buttons — and everything it started stopping once it is gone.
///
///     flutter test test/lesson_screen_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_lesson_viewer/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('opens the shipped tour, shows the step buttons, and stops '
      'its clock when it goes', (tester) async {
    // Every frame here is drawn by the software rasteriser, so the window is
    // kept small enough for a frame to cost little.
    tester.view
      ..physicalSize = const Size(640, 480)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const LessonViewerApp());
    // **Pumped a bounded number of frames, never settled**: once the lesson
    // is up the screen's own ticker redraws its widget surfaces every frame,
    // so there is no frame after which nothing is scheduled. The real pause
    // between frames lets the asset read, which answers outside the fake
    // clock, land.
    for (
      var frame = 0;
      frame < 50 && find.byIcon(Icons.arrow_back).evaluate().isEmpty;
      frame++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward), findsOneWidget);

    // The first step has nothing before it.
    final back = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.arrow_back),
        matching: find.byType(IconButton),
      ),
    );
    expect(back.onPressed, isNull);

    // The screen's clock is running while it is up, and stops with it.
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
