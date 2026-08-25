import 'package:flutter/material.dart';

/// The screen an application shows when it could not open a renderer.
///
/// **Five applications had their own**, and the differences between them were
/// a background colour and a text colour — the same `Scaffold`, `Center`,
/// `Padding` and `Text` written out five times. The one difference that
/// mattered is the sentence, and that stays with the caller: the platformer's
/// says where the shader bundle comes from, and that is the most useful thing
/// anybody has ever put on this screen.
///
/// ## Why there is a screen at all
///
/// Because the alternative is what two of the three games did before
/// `RunSession`: catch the throw, print it, and show black for ever. A line in
/// a console is not something a person playing the game can see, and "the
/// window is black" is indistinguishable from a scene with no lights in it.
class DidNotStart extends StatelessWidget {
  const DidNotStart(
    this.error, {
    super.key,
    this.explaining,
    this.background = Colors.black,
    this.foreground = Colors.white70,
  });

  /// Whatever was thrown. Shown as it is: a stack trace on screen is ugly and
  /// is still the fastest route from "it did not start" to why.
  final Object error;

  /// What the application knows that the error does not.
  ///
  /// The shader bundle is the case this exists for: its format is tied to the
  /// SDK version, it is not in the repository, and "no such asset" is a
  /// perfectly accurate message that tells nobody to run
  /// `tool/build_shaders.sh`.
  final String? explaining;

  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: background,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              explaining == null ? '$error' : '$error\n\n$explaining',
              style: TextStyle(color: foreground),
            ),
          ),
        ),
      );
}
