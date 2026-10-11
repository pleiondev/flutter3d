import 'package:flutter/material.dart';
import 'package:flutter3d_app/flutter3d_app.dart' show LoadingScreen;

/// What the lab shows while the device opens.
///
/// **Reads the system's reduced-motion flag.** A spinner is motion with no
/// information in it, so with `MediaQuery.disableAnimationsOf` set this is
/// `flutter3d_app`'s still [LoadingScreen], which says it in words; either
/// way a screen reader hears that the lab is loading.
class LabLoadingScreen extends StatelessWidget {
  const LabLoadingScreen({super.key});

  static const String _label = 'Loading the lab';

  @override
  Widget build(BuildContext context) => MediaQuery.disableAnimationsOf(context)
      ? const LoadingScreen(message: '$_label…')
      : const Scaffold(
          backgroundColor: Color(0xFF14161A),
          body: Center(
            child: CircularProgressIndicator(semanticsLabel: _label),
          ),
        );
}
