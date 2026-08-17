import 'package:flutter3d_game/flutter3d_game.dart';

/// Moving a control to somewhere the player can reach.
///
/// **The accommodation that matters most and was missing entirely.** The
/// bindings have always been a table, they have always been saved, and there has
/// never been a way for a player to change one — so a player who cannot reach
/// `Ctrl`, or who plays one-handed, or whose controller has a dead button, had
/// no game. Everything needed was already there; nothing asked for it.
///
/// Its own class, and not four lines inside `main.dart`, for one reason: the
/// rules below are the part that can be wrong, and `main.dart` is imported by no
/// test. Here they are ordinary Dart and the file that feeds it events stays
/// event plumbing.
final class Rebinding {
  Rebinding({required this.bindings});

  /// The table being edited. The same one the keyboard and the pad read, so a
  /// change takes effect on the next key press rather than on the next launch.
  final Bindings bindings;

  GameAction? _waiting;

  /// What is listening for its new control, if anything.
  GameAction? get waitingFor => _waiting;

  void start(GameAction action) => _waiting = action;

  void cancel() => _waiting = null;

  /// Points the waiting action at [source], and stops waiting.
  ///
  /// **Replaces rather than adds**, which is the decision worth defending: a
  /// player rebinding a control is nearly always moving it off something they
  /// cannot use, and an "as well" that left the old key working would leave them
  /// exactly where they started. What that costs is the ability to have two keys
  /// for one action, which the defaults already provide and which a player who
  /// wants it can rebuild with [reset].
  ///
  /// Returns whether it took the source, so a caller can go on treating the
  /// event as its own if not.
  bool capture(InputSource source) {
    final action = _waiting;
    if (action == null) return false;
    // A source bound to something else is taken from it. Two actions on one key
    // is a table where the last writer wins silently, and a player who cannot
    // see which one won is a player who thinks the rebinding failed.
    bindings
      ..unbind(source)
      ..clearAction(action)
      ..bind(source, action);
    _waiting = null;
    return true;
  }

  /// Puts the table back the way it shipped.
  ///
  /// The way out of a rebinding that made the game unplayable — which is not a
  /// hypothetical, because the fastest way to find that out is to bind movement
  /// to a key you then cannot reach.
  void reset(Bindings defaults) {
    _waiting = null;
    for (final source in bindings.sources.toList()) {
      bindings.unbind(source);
    }
    for (final source in defaults.sources) {
      final action = defaults[source];
      if (action != null) bindings.bind(source, action);
    }
  }
}
