import 'package:flutter3d_physics/flutter3d_physics.dart';

import 'mechanism.dart';

/// The order the world is stepped in, which three games had written out.
///
/// Six calls, and what is worth having in one place is not the six — it is the
/// **constraints between them**, which were arrived at by argument and by bug
/// and were then copied. Each genre's `step` had its own transcription, and two
/// of them said so out loud: "the same order and the same reason as the
/// shooter's", and "the shooter's step ends with the same call for the same
/// reason". A thing three files agree about, and one of them explains, is a
/// thing that should be somewhere none of them is.
///
/// This exists for the reason [GameLoop] gives about itself: small enough to
/// inline at the call site and deliberately not inlined, because the order is
/// the part that is easy to get wrong and every place that steps a world would
/// otherwise have to get it right again.
///
/// ## The order, and how much each step of it is worth
///
/// **Movers first.** Doors and lifts move before anything sweeps against them,
/// so a crate falling onto a lift that moved this step lands on where the lift
/// is now, and a body arriving a moment later is stopped by where the crate is
/// now.
///
/// **`reindex` before the bodies — by argument, not by test, and said plainly.**
/// It keeps the broadphase consistent with geometry that already moved this
/// step, which is right. But the narrow phase reads live positions, a broadphase
/// cell is four metres, and the previous step's `update` already rebuilt the
/// grid — so a stale index loses a mover only if it left its cell inside one
/// step, which nothing calling itself a door does. No test here pretends
/// otherwise.
///
/// **`clearKinematicDeltas` after the bodies — this one is tested.** A platform
/// moving *sideways* carries its passenger only through the delta, and clearing
/// it early leaves the player standing while the floor departs. Note sideways:
/// the comment this replaced claimed a rising lift could not carry you, and that
/// is measurably false — a lift penetrates the capsule on it and the controller
/// pushes it out, upwards, delta or no delta.
///
/// **`update` before `publish`.** Overlaps dispatch inside `update`: things are
/// taken, hazards bite, triggers light up, each reporting through a flag rather
/// than a return value. `publish` is what asks the machinery what it did.
/// Without it the events stay the empty lists they were built with and every
/// consequence read out of them — a sound, a message, a door opening — silently
/// never happens while the world goes on changing.
///
/// ## Phases rather than one call, and that is a finding
///
/// The first draft was `run(dt, bodies)` — one call with the game in the middle
/// — and it could not be written honestly. The platformer steps its **actors
/// before `reindex`**, so the index catches them and the runner's sweep does not
/// find a patrol in last step's place; the shooter steps its actors **after
/// everything**, so a monster reacts to where the player has just got to. Both
/// arguments are good and neither is this class's to settle. A single `run`
/// would have picked one silently.
///
/// So the phases are named and the game calls them in order. That records the
/// constraints instead of enforcing them, which is the honest trade: what was
/// duplicated was never the six calls, it was the paragraph explaining them.
final class WorldStep {
  const WorldStep({
    required this.collision,
    this.mechanisms,
    this.dynamics,
  });

  final CollisionWorld collision;
  final MechanismWorld? mechanisms;
  final Dynamics? dynamics;

  /// Doors, lifts, and anything else the level drives.
  ///
  /// A game with actors decides for itself whether they move here — where
  /// [index] will catch them — or after everything, where they answer the
  /// player's new position instead. Both are defensible and the two games in
  /// this repository chose differently.
  void movers(double dt) => mechanisms?.step(dt);

  /// Rebuilds the broadphase over what has just moved, and runs the rigid
  /// bodies.
  void index(double dt) {
    collision.reindex();
    dynamics?.step(dt);
  }

  /// Dispatches the overlaps, after the game's own bodies have moved.
  ///
  /// Never before them — see the note on `clearKinematicDeltas` above, which is
  /// the one ordering here that a test will catch. Things are taken inside this
  /// call, hazards bite, triggers light up, and each reports through a flag
  /// rather than a return value, which is what [publish] is then for.
  void settle() {
    collision.update();
    collision.clearKinematicDeltas();
  }

  /// Asks the machinery what it did this step.
  ///
  /// **Separate from [settle], because one game has something to do between
  /// them.** The shooter's use key can start a door, and it is pressed after
  /// the overlaps — publishing before that would report the door a step late,
  /// every time. The other two have nothing in between and call the two
  /// together.
  ///
  /// Not optional anywhere. Without it the events stay the empty lists they
  /// were built with, and every consequence read out of them — a sound, a
  /// message, a door opening — silently never happens while the world goes on
  /// changing.
  void publish() => mechanisms?.publish();
}
