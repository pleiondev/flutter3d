import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:vector_math/vector_math.dart';

/// What the driver is asking for this step, whoever the driver is.
///
/// The same object a player's keys fill in and an AI writes into, so that the
/// two are the same kind of thing and a recorded lap can be played back through
/// either. Values are held between steps rather than being events: a throttle
/// is a position, not a press.
final class VehicleInput {
  /// How hard the driven wheels are being turned, from nought to one.
  double throttle = 0.0;

  /// How hard the brakes are on, from nought to one. Also reverse, once the car
  /// has stopped.
  double brake = 0.0;

  /// Steering, from `-1` (full left) to `1` (full right).
  double steer = 0.0;

  /// Locks the wheels. Not a drift button — see [VehicleController.slipAngle]
  /// for why that distinction is the whole design.
  bool handbrake = false;

  /// Whether the driver is spending boost, if the car has any.
  bool boost = false;

  /// How much of the air is already out of the way, from nought to one.
  ///
  /// **A slipstream is less drag, and drag is the car's business**, so what
  /// arrives here is how sheltered the car is and not a force. One means the
  /// air ahead is completely still, which nothing produces; the simulation
  /// fills it from how close and how directly behind another car this one is.
  ///
  /// On the input rather than on [VehicleController] because that interface
  /// answers questions about the car and this is something being done to it —
  /// and because a recorded lap replays through the same object, so a ghost
  /// driven in somebody's wake is driven in it again.
  double shelter = 0.0;

  void reset() {
    throttle = 0.0;
    brake = 0.0;
    steer = 0.0;
    handbrake = false;
    boost = false;
    shelter = 0.0;
  }

  void setFrom(VehicleInput other) {
    throttle = other.throttle;
    brake = other.brake;
    steer = other.steer;
    handbrake = other.handbrake;
    boost = other.boost;
    shelter = other.shelter;
  }
}

/// A car, as everything except the car itself needs to see it.
///
/// The camera, the engine note, the tyre smoke, the lap counter, the AI and the
/// heads-up display all read from here, and none of them knows how the car is
/// simulated. That is the point of the interface existing before there are two
/// implementations of it: the first model is a single sphere with the body
/// drawn on top, which is what an arcade racer usually is, and the second will
/// be four rays with springs on them. Everything above has to survive that
/// change without noticing it, so the questions it may ask are fixed now, while
/// there is still only one thing answering them.
abstract interface class VehicleController {
  /// Where the car is. The body's centre, not the wheels.
  Vector3 get position;

  /// How fast it is going, and in which direction. Not necessarily the
  /// direction it is pointing — the gap between the two is a slide.
  Vector3 get velocity;

  /// Which way the nose points, in radians about the vertical.
  double get headingYaw;

  /// The nose direction and the ground's tilt, together, for drawing the body.
  ///
  /// Kept separate from [headingYaw] because a car on a cambered corner leans
  /// with the road, and a heading alone cannot say that.
  Matrix3 get visualBasis;

  /// How fast it is going, in metres per second.
  double get speed;

  /// The angle between where the car is pointing and where it is going, in
  /// radians.
  ///
  /// The number that makes a drift a drift, and the reason the handbrake is not
  /// a drift button. Locking the wheels spends the tyres' whole grip budget on
  /// stopping them, which leaves nothing to hold the car sideways; meanwhile
  /// the steering keeps turning the nose. The slide is what falls out of that,
  /// not a mode that has been entered — so it can be caught, held, and driven
  /// out of, and scoring it is only a matter of reading this.
  double get slipAngle;

  /// How far the wheels are turning faster or slower than the ground beneath
  /// them. Positive under power, negative under braking, `-1` locked.
  double get slipRatio;

  /// Whether the car is on something.
  bool get grounded;

  /// How hard something pushed the car back this step, in metres per second
  /// taken out of it. Zero on a clean lap.
  ///
  /// **One number for both walls.** A circuit has two kinds and a driver
  /// arriving at either has arrived at a wall: the track's own barrier, which
  /// is a number in the document, and geometry — a pillar, a wall built out of
  /// brushes, another car. Only the first of the two used to be reported, so
  /// bouncing off the scenery at ninety was the quietest thing on the circuit.
  ///
  /// A step edge: it says what happened, not what is, and is cleared at the top
  /// of every step. Here rather than on the implementation because what reads
  /// it is a game deciding what a crash looks like, and a game should not have
  /// to know which class it has.
  /// **A number, and that is why it is still here** while the flags around the
  /// genre became events. An edge — jumped, landed, crossed the line — is a
  /// moment, and a moment belongs in the step's buffer where two of them can be
  /// told apart and put in order. This is how hard the car is being scraped or
  /// struck *now*, which is state, and a game implementing this interface says
  /// it by answering rather than by being handed a sink to write into.
  double get impactThisStep;

  /// The engine's speed, from nought to one, for whoever is making the noise.
  double get rpm;

  /// How far along the track the car was last seen, in metres.
  ///
  /// Kept by the car because it is the car that asks the ground where it is,
  /// and the answer has to be fed back in on the next step to keep the search
  /// on the right part of a track that folds back beside itself.
  double get trackDistance;

  /// The car's body in the collision world: what other cars, walls and the
  /// volumes lying on the road meet.
  Collider get collider;

  /// Advances one fixed step.
  void step(double dt, VehicleInput input);

  /// Puts the car somewhere, stopped and facing a given way.
  ///
  /// For the starting grid and for being put back on the track. Everything
  /// carried between steps is dropped, so that a car returning from a spin does
  /// not arrive still spinning.
  void placeAt(Vector3 position, double headingYaw, {double? trackDistance});

  /// Everything about this car that a race is made of.
  ///
  /// **Part of the interface rather than of one implementation**, because a
  /// race that can be saved has to be able to save whatever is driving in it.
  /// A game may bring its own vehicle — that is what this interface is for —
  /// and one that could not be written down would be a car that turns into a
  /// stationary copy of itself the moment somebody loads a save.
  ///
  /// What belongs here is what changes as the race runs. Tuning, grips and the
  /// body's shape are what the game *is*, and they come back from the circuit
  /// that was loaded; see `RacingSimulation.save`.
  Map<String, Object?> save();

  /// Reads back what [save] wrote, leniently: a field that is missing keeps
  /// whatever the car has now, which is what lets a save from an older build
  /// load at all.
  void restore(Map<String, Object?> from);
}
