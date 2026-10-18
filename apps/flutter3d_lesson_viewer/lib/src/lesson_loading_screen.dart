import 'package:flutter/material.dart';
import 'package:flutter3d_app/flutter3d_app.dart' show LoadingScreen;

import 'lesson_theme.dart';

/// What the viewer shows while the device opens and the lesson loads.
///
/// **Reads the system's reduced-motion flag.** A spinner is motion with no
/// information in it, so with `MediaQuery.disableAnimationsOf` set this is
/// `flutter3d_app`'s still [LoadingScreen], which says it in words; either
/// way a screen reader hears that the lesson is loading.
class LessonLoadingScreen extends StatelessWidget {
  /// The loading screen; it takes nothing, and reads the motion flag from
  /// the context it is built in.
  const LessonLoadingScreen({super.key});

  static const String _label = 'Loading the lesson';

  @override
  Widget build(BuildContext context) => MediaQuery.disableAnimationsOf(context)
      ? const LoadingScreen(message: '$_label…')
      : const Scaffold(
          backgroundColor: LessonTheme.background,
          body: Center(
            child: CircularProgressIndicator(semanticsLabel: _label),
          ),
        );
}
