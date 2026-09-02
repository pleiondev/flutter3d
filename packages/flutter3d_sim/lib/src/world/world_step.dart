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
  WorldStep({required this.collision, this.mechanisms, this.dynamics});

  final CollisionWorld collision;
  final MechanismWorld? mechanisms;
  final Dynamics? dynamics;

  /// Whether a step has run [movers] and not yet reached [publish].
  ///
  /// Only ever written inside an `assert`, so it costs nothing in a release
  /// build and does not exist in one. See [movers] for what it is guarding.
  bool _owesPublish = false;

  /// Doors, lifts, and anything else the level drives.
  ///
  /// A game with actors decides for itself whether they move here — where
  /// [index] will catch them — or after everything, where they answer the
  /// player's new position instead. Both are defensible and the two games in
  /// this repository chose differently.
  ///
  /// **This asserts that the previous step reached [publish], and that is not
  /// housekeeping.** It shipped: `PlatformerSimulation.step` moved its
  /// mechanisms and never published them, so `takenThisStep` was empty on every
  /// step of every run. The purse still filled — the taking happens inside
  /// `settle` — so nothing looked wrong except that no coin ever made a sound,
  /// and no test could see it because every test read the simulation.
  ///
  /// The class documents constraints rather than enforcing them, deliberately;
  /// this is the one that has already been broken in a shipped game, and a
  /// debug assert is the cheapest thing that would have caught it the same
  /// afternoon.
  void movers(double dt) {
    assert(() {
      if (_owesPublish) {
        throw StateError(
          'a step ran movers() and never reached publish(). The machinery '
          'changed the world and then nobody asked it what it did, so every '
          'consequence read out of its events — a sound, a message, a door '
          'opening — silently did not happen. See WorldStep.publish.',
        );
      }
      _owesPublish = mechanisms != null;
      return true;
    }());
    mechanisms?.step(dt);
  }

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
  /// changing. [movers] asserts that the previous step got here.
  void publish() {
    assert(() {
      _owesPublish = false;
      return true;
    }());
    mechanisms?.publish();
  }

  /// Puts the world back in agreement with itself after a snapshot has been
  /// applied.
  ///
  /// A restore moves every body at once, by teleport, with no step around it —
  /// so the broadphase is still describing where everything was before, and
  /// the kinematic deltas still say how far things moved on a step that is now
  /// somebody else's. Three calls, and they are [index]'s and [settle]'s
  /// without the parts that only make sense inside a step: the rigid bodies do
  /// not integrate here, because a restore is not time passing.
  ///
  /// **Written out twice and once at a third of its length.** The shooter and
  /// the platformer each ended `restore` with the same three lines; the racing
  /// simulation called `reindex` alone, which leaves one step after every load
  /// dispatching overlaps computed for the pre-restore world — a car reported
  /// off the track it is now on, a trigger that fires again for somebody who
  /// already left it.
  void afterRestore() {
    collision.reindex();
    collision.update();
    collision.clearKinematicDeltas();
    assert(() {
      // A restore is not a step and owes nobody a publish. Without this, a
      // load between two steps trips the assert in [movers] for a step that
      // never ran.
      _owesPublish = false;
      return true;
    }());
  }
}
