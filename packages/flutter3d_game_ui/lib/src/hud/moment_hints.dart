/// A sentence a player is told once, at the moment it is useful: the first
/// time a step's events hold one that [when] accepts.
///
/// **A rule, not a timer.** A hint shown at the start of a level is read
/// before it means anything; the same hint shown the first time the player
/// does the thing it is about is read while it is true. [E] is whatever a
/// game's steps hand out — its own event type, or the bus's.
///
/// ```dart
/// const firstJump = MomentHint<GameEvent>(
///   'Hold to jump higher.',
///   when: _isJump,
/// );
/// ```
final class MomentHint<E> {
  const MomentHint(this.text, {required this.when});

  /// What the player is told.
  final String text;

  /// Whether [E] is the moment.
  final bool Function(E event) when;

  /// [text], when [events] hold the moment and it has not been said yet;
  /// null otherwise.
  ///
  /// A pure function, so a caller that keeps its own flag (one bool for one
  /// hint) needs nothing else. [MomentHints] keeps the flags for several.
  String? hintFor(Iterable<E> events, {required bool alreadyTaught}) {
    if (alreadyTaught) return null;
    return events.any(when) ? text : null;
  }
}

/// Several [MomentHint]s, each said once, and which of them have been.
///
/// A step that holds the moments of two hints says the first of them in
/// [hints] order; the second waits for its moment to come round again, so a
/// player is never handed two sentences on one step.
final class MomentHints<E> {
  MomentHints(List<MomentHint<E>> hints)
    : hints = List<MomentHint<E>>.unmodifiable(hints);

  final List<MomentHint<E>> hints;

  final Set<MomentHint<E>> _taught = <MomentHint<E>>{};

  /// Whether [hint] has been said since the last [forget].
  bool taught(MomentHint<E> hint) => _taught.contains(hint);

  /// The sentence [events] call for, marked as said; null when none does.
  String? next(Iterable<E> events) {
    for (final hint in hints) {
      final said = hint.hintFor(events, alreadyTaught: taught(hint));
      if (said != null) {
        _taught.add(hint);
        return said;
      }
    }
    return null;
  }

  /// Forgets what has been said, for a new run.
  void forget() => _taught.clear();
}
