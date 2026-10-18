/// `LessonStereoView` actually reaches the screen and its button actually
/// drives the tape — not just wired to a callback that compiles, but proven
/// against a real (headless) render pass. `LessonStereoView` itself is
/// already proven generically in `flutter3d_stereo/test/
/// lesson_stereo_view_test.dart`; what this file checks is that this app's
/// own `LessonScreen` actually reaches it with a real, opened lesson.
///
///     flutter test test/lesson_screen_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_stereo_lesson_viewer/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('opens the shipped teardown and shows the step buttons', (
    tester,
  ) async {
    // Every frame here is drawn by the software rasteriser, so the window is
    // kept small enough for a frame to cost little.
    tester.view
      ..physicalSize = const Size(320, 180)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const StereoLessonApp());
    // A software device opens asynchronously; the screen starts on
    // `_loading()` and rebuilds once `openDevice`/`LessonCubit.open` both
    // resolve. **Pumped a bounded number of frames, never settled**: once
    // the lesson is up the stereo view draws continuously, so there is no
    // frame after which nothing is scheduled, and `pumpAndSettle` would draw
    // ten minutes of fake time a frame at a time before giving up. The real
    // pause between frames lets the asset read, which answers outside the
    // fake clock, land.
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

    // The view's clock is running — which is the reason the loop above is
    // bounded — and stops with the screen.
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
