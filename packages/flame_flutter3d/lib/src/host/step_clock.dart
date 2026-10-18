/// What a thing drawn between two steps needs from whatever steps it.
library;

/// Something drawn between its last two steps: told, before each step, to
/// keep where it is as where it was.
///
/// **Mixed in, not implemented** (`extends Object3dComponent with
/// StepFollower`): a base mixin class, so a member a minor adds arrives with
/// a body and a component written against 1.0 keeps compiling.
abstract base mixin class StepFollower {
  /// Keeps the present place as the place before the next step. Nothing by
  /// default: a follower with no place of its own to keep draws where it is.
  void rememberPlace() {}
}

/// Whatever steps a simulation: how far the frame is past its last step, and
/// who to tell before each one.
///
/// **One type, because three things step and one of them is the game.**
/// `PhysicsStepComponent` steps rigid bodies and `ActorSystemComponent` steps
/// actors; a game whose simulation steps itself in `HasFixedStep.fixedUpdate`
/// — a genre's own `step`, with the actors and the bodies in it — is the third,
/// and a follower handed only the first two could not draw a body the game
/// moved between its places. It remembered after the game's step had already
/// moved it, and drew the body where it already was.
///
/// **A mixin class, mixed in beside the Flame type a clock already
/// extends** (`extends Component with StepClock`): a member a minor adds
/// arrives with a body, and a clock written against 1.0 keeps compiling.
/// Not `base`: `HasFixedStep` is a clock, and a `base` clock would make
/// every game that mixes it in a `base` or `final` class. A mixin, which
/// cannot mix in a class, still writes `implements StepClock`, as
/// `HasFixedStep` does.
///
/// **Every member has a body**, so a clock that mixes it in and overrides
/// only what it steps keeps compiling when a minor adds one. A clock that
/// says nothing is at its newest step (an [alpha] of 1) and refuses
/// followers, by name, rather than dropping them unheard.
abstract mixin class StepClock {
  /// How far this frame is past the last step, a fraction from 0 up to 1;
  /// 1 by default, the newest step.
  double get alpha => 1.0;

  /// Tells [follower] before each step. Refused by default: a clock that
  /// takes followers overrides it and [unfollow].
  void follow(StepFollower follower) => throw UnsupportedError(
    '$runtimeType does not tell followers before its steps; override '
    'StepClock.follow and StepClock.unfollow to take them',
  );

  /// Stops telling [follower]. Refused by default, as [follow] is.
  void unfollow(StepFollower follower) => throw UnsupportedError(
    '$runtimeType does not tell followers before its steps; override '
    'StepClock.follow and StepClock.unfollow to take them',
  );
}
