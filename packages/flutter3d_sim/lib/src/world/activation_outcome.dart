/// What came of asking a mechanism to do something.
///
/// A hierarchy rather than a bool because the interesting case is the middle
/// one: a locked door has to tell the player *why* nothing happened, and a
/// caller that only knows "it did not work" cannot.
///
/// **Open, and it was sealed on the same reflex as everything else here.** The
/// three below are the outcomes this package could think of, not the outcomes
/// there are: a game with a door that takes a coin, or one that starts a
/// conversation instead of opening, has a fourth. Nothing in the repository
/// ever switched over the three exhaustively — callers read [message] or ask
/// `is Activated` — so sealing bought nothing and cost a game the ability to
/// say what happened at its own door.
///
/// A subclass owes [message]: null when there is nothing to tell the player,
/// and text when there is. That is the whole contract, and it is what every
/// caller here actually uses.
abstract class ActivationOutcome {
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
