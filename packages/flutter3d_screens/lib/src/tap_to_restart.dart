/// The way back into a finished run for a player who has no keyboard.
///
/// **Two of the three games could not be restarted on a phone at all.** The
/// crypt and the platformer each offered exactly two ways back in — the R key
/// and a gamepad Start — and a touch build has neither: the on-screen layer
/// carries the verbs the *level* needs, and a finished level has none of them.
/// A player who died on a handset was told to press R, and the only thing left
/// that would work was closing the application.
///
/// A whole-screen tap rather than another button beside the stick, because the
/// moment it is offered is a moment when nothing else on screen does anything
/// — the run is over — and a target the size of the screen is the one target
/// nobody has to find.
library;

import 'package:flutter/material.dart';

/// Covers the game and restarts it when tapped.
///
/// Mount it only while a run is over and only where a tap is the way in; both
/// are the caller's to decide, because "over" is the game's word and whether
/// there is a keyboard is the build's. Nothing here reads `Playing` for the
/// same reason `TitleCard` does not: a widget that asks the platform cannot be
/// pumped in a test, and `flutter_test` reports itself as Android.
final class TapToRestart extends StatelessWidget {
  const TapToRestart({
    super.key,
    required this.onRestart,
    this.label = 'Tap to play again',
  });

  final VoidCallback onRestart;

  /// What the tap is for, under whatever the game has already said.
  final String label;

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: GestureDetector(
      // Opaque: the drag-look layer underneath would otherwise take the touch
      // and turn the camera of a body that is dead.
      behavior: HitTestBehavior.opaque,
      onTap: onRestart,
      child: SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 40.0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18.0,
                  vertical: 10.0,
                ),
                child: Text(
                  label,
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
