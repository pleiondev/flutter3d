/// A force on a body that is a law of where the body is and how fast it
/// goes: [BodyForce].
library;

import 'rigid_body.dart';

/// A force on a body that depends on the body's state: a spring to a point,
/// a planet's pull, a field. Added to `Dynamics.forces`.
///
/// **What the profile does with it.** Under the deterministic profile the
/// force is read once a step, where the body stands at the start of it, and
/// given as an impulse beside gravity's. Under the accurate profile it is
/// read at every stage of the integrator, at the state that stage has, so an
/// orbit closes and a spring's period is the spring's: the force is a law,
/// and the integrator follows it through the step.
///
/// **Extended outside this package: an `abstract base class`** taking one
/// context that can grow ([BodyForceContext]), so a member added in a minor
/// arrives with a default and every force keeps compiling.
abstract base class BodyForce {
  /// A force; a subclass says what it adds in [addForce].
  const BodyForce();

  /// Adds the force on [context]'s body, in newtons, at the state the
  /// context holds, through [BodyForceContext.add]. A force with nothing to
  /// say about a body adds nothing.
  void addForce(BodyForceContext context);
}

/// What a [BodyForce] is asked at: one body at one state of it.
///
/// **Doubles, origin-local**: the position is in the collision world's frame
/// (relative to its floating origin), as a body's collider is, but carried
/// in double precision, which is what the accurate profile keeps the state
/// in. Under the deterministic profile the values are the body's own float32
/// ones, widened.
final class BodyForceContext {
  /// A context for [body], at rest at the origin until [moveTo] places it.
  BodyForceContext(this.body, {this.step = 0.0});

  /// The body the force is asked about.
  final RigidBody body;

  /// The step being taken, in seconds.
  final double step;

  double _t = 0.0;
  double _x = 0.0, _y = 0.0, _z = 0.0;
  double _vx = 0.0, _vy = 0.0, _vz = 0.0;
  double _fx = 0.0, _fy = 0.0, _fz = 0.0;

  /// Seconds since the start of the step being taken.
  double get timeSeconds => _t;

  /// Where the body is along X, in metres, origin-local.
  double get x => _x;

  /// Where the body is along Y, in metres, origin-local.
  double get y => _y;

  /// Where the body is along Z, in metres, origin-local.
  double get z => _z;

  /// How fast it moves along X, in metres per second.
  double get vx => _vx;

  /// How fast it moves along Y, in metres per second.
  double get vy => _vy;

  /// How fast it moves along Z, in metres per second.
  double get vz => _vz;

  /// The force added so far along X, in newtons.
  double get forceX => _fx;

  /// The force added so far along Y, in newtons.
  double get forceY => _fy;

  /// The force added so far along Z, in newtons.
  double get forceZ => _fz;

  /// Adds a force of [fx], [fy], [fz] newtons.
  void add(double fx, double fy, double fz) {
    _fx += fx;
    _fy += fy;
    _fz += fz;
  }

  /// Puts the body at [x], [y], [z] moving at [vx], [vy], [vz], [time]
  /// seconds into the step, and clears the force: what the integrator does
  /// before it asks the forces at a new state.
  void moveTo(
    double time,
    double x,
    double y,
    double z,
    double vx,
    double vy,
    double vz,
  ) {
    _t = time;
    _x = x;
    _y = y;
    _z = z;
    _vx = vx;
    _vy = vy;
    _vz = vz;
    _fx = 0.0;
    _fy = 0.0;
    _fz = 0.0;
  }
}
