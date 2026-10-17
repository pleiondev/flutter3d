import 'package:flutter3d_sim/flutter3d_sim.dart';

import '../input/action_map.dart';
import '../input/bindings.dart' show InputSource;

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
///
/// ## Over the action map
///
/// Every kind of action can be rebound — a button, an axis's two keys and a
/// dual axis's four, by [start] with the part — and the map decides what a
/// source already in use means, by [onConflict]: taken from the other action,
/// traded with it, or refused. [lastConflicts] says what was in the way, so a
/// screen can tell the player that `J` was jump's.
///
/// It edited a bare button table as well, through a second `start` and a
/// second `waitingFor` that only knew buttons. One model is the map, which
/// holds the button table: a game passes the map it handed its devices.
final class Rebinding {
  Rebinding({required this.actions, this.onConflict = ConflictPolicy.steal});

  /// The action map being edited. The same one the keyboard and the pad read,
  /// so a change takes effect on the next key press rather than on the next
  /// launch.
  final ActionMap actions;

  /// What a source already in use means — see [ConflictPolicy].
  ConflictPolicy onConflict;

  InputAction<Object>? _waiting;
  CompositePart? _part;
  List<BindingConflict> _conflicts = const <BindingConflict>[];

  /// What is listening for its new control, of whatever kind, if anything.
  InputAction<Object>? get waitingFor => _waiting;

  /// Which part of a composite is listening, if the action is an axis bound
  /// to keys.
  CompositePart? get waitingPart => _part;

  /// Who had the source the last capture took, before it took it.
  List<BindingConflict> get lastConflicts => _conflicts;

  /// Starts listening for [action]'s new control, or for one [part] of it.
  void start(InputAction<Object> action, {CompositePart? part}) {
    _waiting = action;
    _part = part;
    _conflicts = const <BindingConflict>[];
  }

  void cancel() {
    _waiting = null;
    _part = null;
  }

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
  /// event as its own if not. The map does the work — see [ActionMap.rebind] —
  /// and under [ConflictPolicy.refuse] a source in use is not taken: this
  /// returns true all the same (the key was the rebinding's, not the game's),
  /// goes on waiting, and [lastConflicts] says why.
  bool capture(InputSource source) {
    final action = _waiting;
    if (action == null) return false;
    final outcome = actions.rebind(
      action,
      source,
      part: _part,
      onConflict: onConflict,
    );
    _conflicts = outcome.conflicts;
    if (outcome.applied) cancel();
    return true;
  }

  /// Puts the whole action map back the way it shipped, buttons and axes.
  ///
  /// The way out of a rebinding that made the game unplayable — which is not a
  /// hypothetical, because the fastest way to find that out is to bind movement
  /// to a key you then cannot reach.
  void reset(ActionMap defaults) {
    cancel();
    _conflicts = const <BindingConflict>[];
    actions.copyFrom(defaults);
  }
}
