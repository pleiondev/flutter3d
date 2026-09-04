/// Something a step did, told to whoever is watching.
///
/// The seam a game needs and a simulation kept refusing to give it: a shot was
/// fired, a runner landed, a tyre broke traction. Without it every game reads
/// the state twice a frame and reconstructs the moment by difference — was the
/// ammo count lower than last frame, is the runner on the ground now and was it
/// not before — which is slower, wrong at the edges, and impossible for
/// anything that happens and undoes itself inside one step. A shot fired and
/// resolved between two frames leaves no difference to find.
///
/// **Open, deliberately.** A game invents events the way it invents weapons,
/// and a closed list would mean a template deciding what can happen in a game
/// written on top of it. Subclass this, put whatever the moment carries on the
/// subclass, and hand it to [GameEvents.add] from your own step.
///
/// **It says what happened, not what to do about it.** No sound, no particle,
/// no screen shake — those are decisions, and they belong to the game. A
/// simulation that named a sound file would be a simulation that could not run
/// on a server, and running there is the whole reason this package has no
/// Flutter in it.
abstract class GameEvent {
  const GameEvent();

  /// For logs, tests and a debug overlay. Not an identity: two events of the
  /// same name are still two events, and nothing here dispatches on it.
  String get name;

  @override
  String toString() => name;
}

/// What a step recorded, for the frame that is about to read it.
///
/// **A drained buffer rather than a `Stream`, and that is not a preference.**
/// A stream delivers asynchronously: the listener runs on a later microtask,
/// after the step that produced the event has finished and possibly after the
/// next one has started. Every simulation here is fixed-step, and two of them
/// reproduce a recorded run exactly — a racing replay and an input tape. An
/// event arriving between two steps would let a listener mutate the world in
/// the gap, which is precisely the state no replay can reproduce, and the
/// failure would be a race that only shows up on somebody else's machine.
///
/// So events are appended during the step and drained by the caller after it,
/// in the order they happened, on the same turn of the loop.
///
/// **Nobody watching is the normal case.** A headless test, a server, and every
/// one of this repository's thousands of simulation tests step without draining.
/// So the buffer is capped: past [limit] the oldest go, because a simulation
/// that grows a list forever is a simulation that runs out of memory on a long
/// game rather than a short test. [dropped] says how many were lost, so a
/// caller that cares can notice rather than wonder.
final class GameEvents {
  GameEvents({this.limit = 256}) : assert(limit > 0, 'a buffer of none is off');

  /// How many events are kept before the oldest are dropped.
  ///
  /// Generous for one step of anything here — a busy shooter step is a handful
  /// — and small enough that forgetting to drain costs nothing that matters.
  final int limit;

  final List<GameEvent> _pending = <GameEvent>[];

  /// How many events were dropped, in total, because nobody drained.
  ///
  /// Stays at zero for a caller that drains every frame. A number here means
  /// either a game that is not reading its events or a step that is producing
  /// far more than expected, and both are worth knowing.
  int dropped = 0;

  /// Whether anything is waiting. Cheaper than draining to find out.
  bool get isEmpty => _pending.isEmpty;

  /// Records [event]. Called from inside a step.
  void add(GameEvent event) {
    if (_pending.length >= limit) {
      _pending.removeAt(0);
      dropped++;
    }
    _pending.add(event);
  }

  /// Takes everything recorded since the last call, oldest first.
  ///
  /// Returns a fresh list and empties the buffer, so a caller may hold what it
  /// took across frames without the next step writing into it.
  List<GameEvent> drain() {
    if (_pending.isEmpty) return const <GameEvent>[];
    final taken = List<GameEvent>.of(_pending);
    _pending.clear();
    return taken;
  }

  /// Forgets everything pending, without reading it.
  ///
  /// For a game that is restarting a level: the events of the run that just
  /// ended are not events of the run about to start, and delivering them after
  /// the reset would fire a death sound over a fresh spawn.
  void clear() => _pending.clear();
}
