import 'package:flutter/material.dart';

import 'credits.dart';

/// What the game says before it starts.
///
/// **There was nothing here.** The application opened straight into the
/// tutorial with a `Click to play` banner over it, so the game had no name on
/// screen, no statement of what the keys were, and nowhere for the attribution
/// its models' licence requires. A player who quit before finishing — which is
/// most of them — never saw a credit.
///
/// Shown until the game is first played and never again in that session: a
/// title card that comes back every time the pointer is released is a title
/// card in the middle of a run.
class TitleCard extends StatelessWidget {
  const TitleCard({super.key, required this.prompt, this.resuming = false});

  /// What the player has to do to begin. Different on the web, where there is
  /// no pointer to capture.
  final String prompt;

  /// Whether there is a saved run behind this card.
  ///
  /// Worth saying out loud: a checkpoint is only reassuring if the player knows
  /// it happened, and the game writes one silently.
  final bool resuming;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.78),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Ascent',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 46,
                    fontWeight: FontWeight.w200,
                    letterSpacing: 6,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Two hundred and sixty metres, three lives, and a summit.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 22),
                for (final line in const <String>[
                  'W A S D to move, space to jump — twice, in the air.',
                  'Shift to sprint, Ctrl or C to crouch, click to dash.',
                  'Escape releases the mouse and opens the settings.',
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      line,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    ),
                  ),
                if (resuming) ...<Widget>[
                  const SizedBox(height: 14),
                  Text(
                    'Your last checkpoint is waiting.',
                    style: TextStyle(
                      color: Colors.amber.withValues(alpha: 0.85),
                      fontSize: 14,
                    ),
                  ),
                ],
                const SizedBox(height: 26),
                const CreditsSection(),
                const SizedBox(height: 26),
                Text(
                  prompt,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
