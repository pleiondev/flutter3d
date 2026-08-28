import 'package:flutter/material.dart';
import 'package:flutter3d_app/flutter3d_app.dart'; // SettingsOverlay, Credit

import 'credits.dart';

/// What the game says before it starts.
///
/// **The control lines were wrong, and that is worth recording.** They were a
/// `const` list, so they said "click to dash" in a browser where clicking turns
/// the camera, and they promised that Escape opens the settings when Escape only
/// released the mouse. A list of what the keys do, written beside the keys and
/// checked by nothing, drifts the first time either changes — so the lines are
/// built from what the build actually is, and a test renders both.
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
  const TitleCard({
    super.key,
    required this.prompt,
    required this.dashOnPointer,
    this.touch = false,
    this.resuming = false,
  });

  /// What the player has to do to begin. Different on the web, where there is
  /// no pointer to capture.
  final String prompt;

  /// Whether the mouse button dashes, which is true of the desktop build only.
  ///
  /// **This card said "click to dash" on the web, where clicking turns the
  /// camera and `Q` dashes.** An argument rather than a `kIsWeb` read inside
  /// this file, so a test can render both without pretending to be a browser —
  /// which is how the wrong line survived: nothing could look at it.
  final bool dashOnPointer;

  /// Whether this build is played with fingers, in which case none of the keys
  /// below exist and describing them would be a screen of nonsense.
  final bool touch;

  /// What the game is actually driven by, said once.
  List<String> get _controls => touch
      ? const <String>[
          'The stick walks. Jump twice to reach the high ledges.',
          'Dash across the wide gaps; drop through the thin platforms.',
          'Drag anywhere else to look around.',
          'A controller works too, if one is paired.',
        ]
      : <String>[
          'W A S D to move, space to jump — twice, in the air.',
          dashOnPointer
              ? 'Shift to sprint, Ctrl or C to crouch, click to dash.'
              : 'Shift to sprint, Ctrl or C to crouch, Q to dash.',
          // Positions, not printed labels: this game cannot know whether the pad
          // in the player's hands calls its lower face button `A` or Cross, and
          // deliberately does not try to find out.
          // One sentence over two lines, not two entries missing a comma —
          // which is the mistake the lint exists to catch, and it cannot tell
          // them apart.
          // ignore: no_adjacent_strings_in_list
          'Or a controller: left stick to move, the lower face button to jump, '
              'the right one to dash.',
          dashOnPointer
              ? 'Escape gives the mouse back and opens the settings.'
              : 'Escape opens the settings.',
        ];

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
                for (final line in _controls)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      line,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
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
                const CreditsSection(credits: Credits.models),
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
