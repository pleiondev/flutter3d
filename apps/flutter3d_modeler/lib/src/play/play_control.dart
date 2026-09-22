/// The handle an agent drives Play through — `ux-52`.
///
/// **A registry of one, not a second copy of the session.** `PlayScreen`
/// owns the running game; this is the one place anything outside the route
/// can ask whether there is one and press its buttons. The screen fills it
/// in when it mounts and empties it when it goes, so "is Play running" is
/// the same fact for the person looking at the window and for the agent
/// asking over MCP — rather than a flag somebody has to remember to clear.
library;

import 'package:vector_math/vector_math.dart' show Vector3;

import 'play_template.dart';

/// What a running game offers whoever is not inside it.
typedef PlayRunning = ({
  PlayTemplate template,

  /// Brings the running game to the document as it is now.
  void Function() reload,

  /// Closes the route.
  void Function() stop,

  /// Where the body is standing, for `play.console` to report.
  Vector3 Function() where,
});

/// Whether Play is running, and how to press its buttons if it is.
final class PlayControl {
  /// The running game, or null when the modeller is the thing on screen.
  PlayRunning? running;

  bool get isRunning => running != null;
}
