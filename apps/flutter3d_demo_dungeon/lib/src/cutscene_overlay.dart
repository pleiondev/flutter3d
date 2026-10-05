/// What a cutscene puts over the picture: the dark of its fade, the words of
/// its subtitles, and the way out of it.
library;

import 'package:flutter/material.dart';

/// Drawn over the crypt while a cutscene plays.
///
/// **Only what the cutscene says, read every frame.** The fade and the
/// subtitle come from `SequencePlayer`, which reads them off the step the
/// simulation reached and the frame's place between two steps; this widget
/// keeps nothing, so a rewind or a skip shows what the step says at once.
final class CutsceneOverlay extends StatelessWidget {
  const CutsceneOverlay({
    super.key,
    required this.fade,
    required this.subtitle,
    required this.skipHint,
    required this.onSkip,
  });

  /// How dark the screen is, nought to one.
  final double fade;

  /// What is being said, or null.
  final String? subtitle;

  /// How to skip, in the words of the device in hand.
  final String skipHint;

  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final said = subtitle;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        IgnorePointer(
          child: ColoredBox(
            color: Colors.black.withValues(alpha: fade.clamp(0.0, 1.0)),
          ),
        ),
        if (said != null)
          Positioned(
            left: 48,
            right: 48,
            bottom: 72,
            child: IgnorePointer(
              child: Text(
                said,
                key: const ValueKey<String>('cutscene:subtitle'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  shadows: <Shadow>[
                    Shadow(blurRadius: 6, color: Colors.black),
                    Shadow(blurRadius: 2, color: Colors.black),
                  ],
                ),
              ),
            ),
          ),
        Positioned(
          right: 16,
          bottom: 16,
          child: TextButton(
            key: const ValueKey<String>('cutscene:skip'),
            onPressed: onSkip,
            child: Text(
              skipHint,
              style: const TextStyle(color: Color(0xCCFFFFFF)),
            ),
          ),
        ),
      ],
    );
  }
}
