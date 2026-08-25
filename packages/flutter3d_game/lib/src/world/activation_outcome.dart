/// What came of asking a mechanism to do something.
///
/// A sealed hierarchy rather than a bool because the interesting case is the
/// middle one: a locked door has to tell the player *why* nothing happened, and
/// a caller that only knows "it did not work" cannot.
sealed class ActivationOutcome {
  const ActivationOutcome();

  /// Something worth showing the player, or null when there is nothing to say.
  String? get message => null;
}

/// It did what it was asked.
final class Activated extends ActivationOutcome {
  const Activated();
}

/// It would not, and here is what to tell the player.
final class Refused extends ActivationOutcome {
  const Refused(this.message);

  @override
  final String message;
}

/// There was nothing to do — already open, still moving, or no such name.
///
/// Distinct from [Refused] because pressing a button twice is not a failure and
/// should not print anything.
final class NothingToDo extends ActivationOutcome {
  const NothingToDo();
}
