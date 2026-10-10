import 'package:flutter/material.dart';
import 'package:flutter3d_game_ui/screens.dart' show TitleSheet;

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
/// card in the middle of a run. Laid out by `TitleSheet`; what is here is
/// this game's name and the lines about its keys.
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
          // The one control on this build that stays on after the finger has
          // gone, so it is the one that has to be described rather than found.
          'Sprint is a switch, not a button: tap it on and it stays on.',
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
  Widget build(BuildContext context) => TitleSheet(
    title: 'Ascent',
    tagline: 'Two hundred and sixty metres, three lives, and a summit.',
    lines: _controls,
    notice: resuming ? 'Your last checkpoint is waiting.' : null,
    credits: credits.models,
    prompt: prompt,
  );
}
