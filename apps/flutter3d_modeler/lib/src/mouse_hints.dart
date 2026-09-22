/// What the three buttons do right now — `ux-26`.
///
/// **The one question a person new to a 3D editor asks first, and the one no
/// editor answers.** Which button orbits is a setting here (`ux-04`), what
/// the left button does depends on what is armed, and the right button is
/// either a menu or free-look depending on the same setting — so the answer
/// changes several times a minute and there is nowhere on screen it is
/// written down. This writes it in the status line, where it costs three
/// short words and is true at the moment it is read.
///
/// **A pure function over the two things that decide it**, so the strip that
/// shows it holds no rules of its own and a test asks the question directly.
library;

import 'settings.dart' show NavigationScheme;
import 'ui/tools.dart' show kDragTools;

/// What each button means, in the fewest words that are still an answer.
typedef MouseHints = ({String left, String middle, String right});

/// The hints for [scheme] with [tool] armed, in [mode].
///
/// [tool] is `ModelerReady.tool` — the rail's own lit button, null when the
/// pointer itself is armed.
MouseHints mouseHintsFor({
  required NavigationScheme scheme,
  String? tool,
  bool lookingAround = false,
}) {
  // A free-look in progress answers for every button: the walk keys are live
  // and the buttons are not what they usually are, which is exactly the
  // moment somebody looks down at the strip to find out what happened.
  if (lookingAround) {
    return (left: 'Look', middle: 'Look', right: 'Hold to look · WASD walks');
  }

  final bool drag = tool != null && kDragTools.contains(tool);
  final bool lasso = tool == 'mesh.lasso';

  final String left = switch ((drag, lasso, scheme)) {
    (true, _, _) => 'Drag to transform',
    (_, true, _) => 'Lasso',
    // Under left-drag orbit an empty-space drag is the camera and a drag on
    // the model is a box; the shorter half of that is the one worth saying.
    (_, _, NavigationScheme.leftDragOrbit) => 'Select · drag orbits',
    (_, _, NavigationScheme.middleMouseOrbit) => 'Select · drag boxes',
  };

  final String middle = switch (scheme) {
    NavigationScheme.middleMouseOrbit => 'Orbit · Shift pans',
    NavigationScheme.leftDragOrbit => 'Orbit',
  };

  // `ux-25`'s menu, except where `ux-04` has already spent the button.
  final String right = switch (scheme) {
    NavigationScheme.middleMouseOrbit => 'Menu',
    NavigationScheme.leftDragOrbit => 'Hold to look',
  };

  return (left: left, middle: middle, right: right);
}

/// The hints as one line for a strip that has room for one — "L Select ·
/// M Orbit · R Menu".
String mouseHintLine(MouseHints hints) =>
    'L ${hints.left} · M ${hints.middle} · R ${hints.right}';
