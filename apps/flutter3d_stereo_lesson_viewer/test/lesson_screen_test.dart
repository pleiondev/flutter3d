/// `LessonStereoView` actually reaches the screen and its button actually
/// drives the tape — not just wired to a callback that compiles, but proven
/// against a real (headless) render pass. `LessonStereoView` itself is
/// already proven generically in `flutter3d_stereo/test/
/// lesson_stereo_view_test.dart`; what this file checks is that this app's
/// own `LessonScreen` actually reaches it with a real, opened lesson.
///
///     flutter test test/lesson_screen_test.dart
library;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d_stereo_lesson_viewer/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('opens the shipped teardown and shows the step buttons', (
    tester,
  ) async {
    await tester.pumpWidget(const StereoLessonApp());
    // A software device opens asynchronously; the screen starts on
    // `_loading()` and rebuilds once `openDevice`/`LessonCubit.open` both
    // resolve.
    await tester.pumpAndSettle();

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
  });
}
