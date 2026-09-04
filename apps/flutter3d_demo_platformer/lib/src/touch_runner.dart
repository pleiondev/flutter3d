/// The climb under two thumbs.
///
/// **The one verb a phone could not say was sprint.** It is bound to shift and
/// to a shoulder button, and the touch build had neither — so the run speed the
/// longer jumps in this game are tuned for was reachable on a desktop and on a
/// pad and nowhere else, and a player on a handset met gaps the level's own
/// author had crossed at a run.
///
/// It is a *switch* rather than a button, which is the whole reason it did not
/// simply join the row: a held sprint costs the thumb that is already on the
/// stick. That is the same barrier the `a11y.toggleSprint` setting exists for,
/// arriving from the hardware rather than from the player — see
/// [InputState.toggle], which does the right thing whichever way that setting
/// is left.
///
/// Four lines of layout in a file of its own, and that is on purpose: this used
/// to be a `TouchControls(...)` inside a thousand-line `build`, where nothing
/// could pump it and no test in this application had ever pressed one of its
/// buttons.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';

/// Everything the runner can be driven by, on a device with no keyboard.
class TouchRunner extends StatelessWidget {
  const TouchRunner({super.key, required this.state, required this.onSprint});

  final InputState state;

  /// Flips the sprint. The screen above owns the call so that it can rebuild:
  /// [TouchToggle] draws what it is told and keeps nothing.
  final VoidCallback onSprint;

  @override
  Widget build(BuildContext context) => TouchControls(
    state: state,
    buttons: const <TouchAction>[
      TouchAction(PlatformerActions.dropThrough, 'drop'),
      TouchAction(PlatformerActions.dash, 'dash'),
      // Nearest the thumb, because it is the one pressed most.
      TouchAction(GameAction.jump, 'jump'),
    ],
    toggles: <TouchToggle>[
      TouchToggle(
        label: 'sprint',
        // Asked of the input rather than kept beside it. A copy here would go
        // out of step the first time the run was restarted, which clears
        // everything held.
        on: state.held(GameAction.sprint),
        onTap: onSprint,
      ),
    ],
  );
}
